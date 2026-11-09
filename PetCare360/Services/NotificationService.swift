import Foundation
import UserNotifications


/// Serializes multi-step work whose steps complete asynchronously:
/// only one pass runs at a time; passes submitted while one is running
/// are coalesced — only the LATEST queued pass runs next. Used for
/// reminder synchronization so a launch pass and a foreground pass can
/// never interleave their pending-request cleanup and scheduling
/// (v1.2.5). Pure logic, unit-tested.
final class SyncCoordinator {
    private let stateQueue = DispatchQueue(label: "com.xenon-media.petcare360.sync-coordinator")
    private var running = false
    private var queued: (() -> Void)?

    /// `work` receives a completion it MUST call exactly once when its
    /// asynchronous steps have finished.
    func submit(_ work: @escaping (@escaping () -> Void) -> Void) {
        stateQueue.async {
            if self.running {
                self.queued = { self.submit(work) }
                return
            }
            self.running = true
            work {
                self.stateQueue.async {
                    self.running = false
                    let next = self.queued
                    self.queued = nil
                    next?()
                }
            }
        }
    }
}

/// Strict FIFO serialization for notification-centre mutations
/// (ordering review fix, 2026-11-09). Unlike SyncCoordinator this
/// queue NEVER coalesces: every submitted operation runs, exactly
/// once, in submission order, and the next operation does not begin
/// until the running one calls its completion — including any
/// asynchronous getPendingNotificationRequests snapshot the
/// operation performs and any scheduling its completion performs.
///
/// Why: the only ordering UNUserNotificationCenter leaves to the
/// app is the order in which the app SUBMITS calls, and the app's
/// cancel-then-reschedule flows submit their follow-up calls from
/// getPending completion handlers. Without serialization, two
/// overlapping flows (two rapid saves of one medication, a save and
/// a global cancelAll) can have their completions fire in either
/// order, letting the OLDER action's schedule land after the NEWER
/// action's cancellation. Routing every snapshot-based cancel,
/// cancelAll, and synchronization pass through this single queue
/// makes submission order equal to user-action order, so the
/// latest action always wins. ALL centre mutations go through
/// this queue — adds, explicit-id cancels, cancelAll, snapshot
/// cancels and sync passes (final review fix, 2026-11-09): a
/// queued operation's centre calls are only submitted when the
/// operation RUNS, so a direct add could otherwise land between
/// a queued operation's enqueue and its execution and be removed
/// by it, or survive a removal it should not. Code already
/// running inside an operation uses the Locked variants, which
/// mutate directly as part of that operation. Pure logic, same
/// pattern as SyncCoordinator.
final class NotificationOperationQueue {
    private let stateQueue = DispatchQueue(label: "com.xenon-media.petcare360.notification-operations")
    private var running = false
    private var pending: [(@escaping () -> Void) -> Void] = []

    /// `work` receives a completion it MUST call exactly once when
    /// all of its asynchronous steps have finished.
    func submit(_ work: @escaping (@escaping () -> Void) -> Void) {
        stateQueue.async {
            self.pending.append(work)
            self.pump()
        }
    }

    private func pump() {
        guard !running, !pending.isEmpty else { return }
        running = true
        let work = pending.removeFirst()
        work {
            self.stateQueue.async {
                self.running = false
                self.pump()
            }
        }
    }
}

/// Foreground presentation (2026-11-09 reliability fix): the app
/// previously set NO UNUserNotificationCenter delegate, so iOS
/// applied its default foreground behaviour — a reminder that fired
/// while the app was open was silently swallowed (no banner, no
/// sound). This presenter asks iOS to present foreground reminders
/// the same way as background ones. It is installed once, in
/// PetCare360App.init, before any reminder can fire. It changes
/// presentation ONLY; delivery itself is always iOS's decision.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()
    private override init() { super.init() }

    /// The options requested for foreground delivery: banner,
    /// Notification Centre list, sound and badge. Exposed as a
    /// plain value so the configuration is unit-testable without a
    /// running notification centre.
    static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .list, .sound, .badge]

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        Self.foregroundOptions
    }
}

/// Local notifications only. Authorization is requested when the
/// user enables reminders — during onboarding, in Settings, or the
/// first time a reminder is saved. Identifiers are namespaced
/// `pc360-` and are deterministic per schedule, so re-scheduling
/// never duplicates.
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default: return false
        }
    }

    /// Schedules a reminder AND makes sure notification permission
    /// has been REQUESTED at least once. Reminder editor saves use
    /// this: previously they scheduled without ever asking, so a
    /// user who skipped the onboarding personalization pages was
    /// never prompted and iOS silently dropped every reminder.
    ///
    /// ORDER IS LOAD-BEARING (review fix, 2026-11-09): the schedule
    /// runs FIRST, synchronously, in the caller's own sequencing —
    /// for the medication editor that is inside the
    /// cancel-then-schedule completion, so the v1.2.4 guarantee
    /// (a save's cancellation always lands before its scheduling,
    /// and any later cancelAll / category cancel lands after and
    /// wins) is preserved exactly. The authorization request runs
    /// afterwards in a detached Task. An earlier version of this
    /// helper awaited the request BEFORE scheduling, which parked
    /// the closure for as long as the iOS prompt stayed open: a
    /// reminder disabled in the meantime (per-medication toggle,
    /// category toggle, or the global cancelAll) would then be
    /// resurrected by the parked closure landing afterwards, and
    /// rapid successive edits could execute out of order.
    /// Scheduling before the prompt is safe: iOS stores the
    /// requests but delivers nothing unless permission is granted,
    /// and the launch/foreground synchronization re-arms everything
    /// once the user allows notifications in iOS Settings.
    func scheduleAndRequestAuthorizationIfNeeded(_ schedule: () -> Void) {
        schedule()
        Task { _ = await requestAuthorizationIfNeeded() }
    }

    private func schedule(id: String, title: String, body: String, fireDate: Date, repeatsDaily: Bool = false, soundName: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Custom sound only when a bundled file was resolved; iOS
        // falls back to the system default when the name is nil.
        // System sound/permission settings always win — this app
        // cannot (and does not try to) force a sound to play.
        content.sound = soundName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let dailyComps = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: repeatsDaily ? dailyComps : comps, repeats: repeatsDaily)
        let request = UNNotificationRequest(identifier: "pc360-\(id)", content: content, trigger: trigger)
        // LOCKED primitive (2026-11-09): this add is submitted
        // directly and must only be reached from within an
        // operation — every public scheduling entry point either
        // enqueues an operation that calls its Locked variant, or
        // is itself a Locked variant called inside one. That is
        // what makes the order of centre submissions identical to
        // the order of user actions across every mutation path.
        UNUserNotificationCenter.current().add(request)
    }

    /// Schedules one-off reminders for the medication's ACTUAL dose slots
    /// over the next 7 days, using MedicationService.slots — so frequency,
    /// selected weekdays, start date and end date are all honoured
    /// (previously a daily-repeating trigger ignored the course end date,
    /// and weekly reminders fired on the wrong weekday, once).
    /// Identifiers are deterministic per medication/day/dose, and
    /// UNUserNotificationCenter replaces a pending request that reuses an
    /// identifier, so re-scheduling never duplicates.
    /// Schedules one-off reminders for the medication's ACTUAL dose slots
    /// over the next 7 days, using MedicationService.slots — so frequency,
    /// selected weekdays, start date and end date are all honoured.
    /// Identifiers are deterministic per medication/day/dose, and
    /// UNUserNotificationCenter replaces a pending request that reuses an
    /// identifier, so re-scheduling never duplicates. `budget` caps how
    /// many new requests may be added (iOS allows ~64 pending per app);
    /// returns the remaining budget.
    /// LOCKED (2026-11-09): every caller already runs inside an
    /// operation — the medication editor's dose-cancellation
    /// completion and rescheduleAllLocked — so the adds are
    /// submitted directly as part of that operation.
    @discardableResult
    func scheduleMedicationReminderLocked(medication: Medication, petName: String, budget: Int = .max) -> Int {
        guard ReminderCategory.medications.isEnabled else { return budget }
        var remaining = budget
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let stamp = DateFormatter()
        stamp.calendar = calendar
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd"
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for slot in MedicationService.slots(for: medication, on: day) where slot.scheduledDate > Date() {
                guard remaining > 0 else { return 0 }
                schedule(id: Self.doseReminderID(medicationID: medication.id, day: day, minutes: slot.minutes),
                         title: "Medication time for \(petName)",
                         body: "\(medication.name) \(medication.dosage)".trimmingCharacters(in: .whitespaces),
                         fireDate: slot.scheduledDate,
                         soundName: NotificationSoundPreferences.resolvedFileName(species: medication.pet?.species))
                remaining -= 1
            }
        }
        return remaining
    }

    /// Rolling replenishment (v1.2.2): rebuilds the next 7 days of
    /// medication reminders for every active medication. Called whenever
    /// the app becomes active, so reminders keep rolling forward WITHOUT
    /// anyone reopening the medication editor. Inactive medications get
    /// no new reminders; deleted medications' reminders are removed by
    /// the wholesale med-* cleanup. Does nothing when reminders are off
    /// or notification permission was never granted / was denied — it
    /// never prompts for permission itself.
    /// Whether one medication's own reminder preference allows dose
    /// reminders. A medication with NO schedule record defaults to
    /// enabled (the MedicationSchedule default, and the behaviour for
    /// records created before preferences were wired end-to-end).
    static func isReminderEnabled(medicationID: UUID, schedules: [MedicationSchedule]) -> Bool {
        schedules.first { $0.medicationID == medicationID }?.reminderEnabled ?? true
    }

    /// The (medication, petName) pairs a replenishment pass may schedule:
    /// active pets only, active medications only, and each medication's
    /// individual reminder preference respected. Pure and testable.
    static func eligibleReminders(pets: [Pet], schedules: [MedicationSchedule]) -> [(medication: Medication, petName: String)] {
        pets.filter { !$0.isArchived }.flatMap { pet in
            pet.medications
                .filter { $0.isActive && isReminderEnabled(medicationID: $0.id, schedules: schedules) }
                .map { (medication: $0, petName: pet.name) }
        }
    }

    /// Insurance policies eligible for renewal reminders: only policies
    /// whose pet exists and is NOT archived (v1.2.7). Restoring the pet
    /// makes its policies eligible again on the next rebuild, because
    /// eligibility is computed from current data every pass. Pure and
    /// testable.
    static func eligibleInsurancePolicies(policies: [InsurancePolicy], pets: [Pet]) -> [InsurancePolicy] {
        let activePetIDs = Set(pets.filter { !$0.isArchived }.map { $0.id })
        return policies.filter { activePetIDs.contains($0.petID) }
    }

    /// Deterministic pending-request identifier for one dose reminder.
    /// Stable across calls, which is what makes replenishment idempotent:
    /// re-adding the same identifier replaces, never duplicates.
    static func doseReminderID(medicationID: UUID, day: Date, minutes: Int) -> String {
        let stamp = DateFormatter()
        stamp.calendar = Calendar.current
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyyMMdd"
        return "med-\(medicationID.uuidString)-\(stamp.string(from: day))-\(minutes)"
    }

    /// Cancels ONLY a medication's dose reminders (not its refill
    /// reminder). Used when the medication's own reminder toggle is
    /// switched off in the editor.
    func cancelDoseReminders(medicationID: UUID) {
        cancelDoseReminders(medicationID: medicationID, completion: nil)
    }

    /// Completion variant: the completion runs only AFTER the removal has
    /// been submitted, so callers that cancel-then-reschedule (the
    /// medication editor) cannot have their new requests removed by a
    /// late-running snapshot of the old ones (v1.2.4 race fix).
    /// The whole sequence — snapshot, removal, AND the completion
    /// (whose scheduling is therefore submitted before this
    /// operation ends) — runs as ONE operation on the FIFO queue
    /// (2026-11-09): two rapid saves of the same medication can no
    /// longer have their completions interleave, and a cancelAll
    /// submitted afterwards is guaranteed to be submitted to the
    /// centre after this save's schedule.
    func cancelDoseReminders(medicationID: UUID, completion: (() -> Void)?) {
        let prefix = "pc360-med-\(medicationID.uuidString)-"
        let center = UNUserNotificationCenter.current()
        operations.submit { done in
            center.getPendingNotificationRequests { requests in
                let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
                center.removePendingNotificationRequests(withIdentifiers: ids)
                completion?()
                done()
            }
        }
    }

    /// Completed appointments never get reminders; past ones neither.
    static func shouldScheduleAppointmentReminder(_ appointment: VetAppointment) -> Bool {
        !appointment.isCompleted && !appointment.isCancelled && appointment.date > Date()
    }

    func rescheduleAllMedicationReminders(pets: [Pet], schedules: [MedicationSchedule], remindersEnabled: Bool, completion: (() -> Void)? = nil) {
        operations.submit { done in
            self.rescheduleAllMedicationRemindersLocked(pets: pets, schedules: schedules,
                                                        remindersEnabled: remindersEnabled) {
                completion?()
                done()
            }
        }
    }

    /// The reschedule itself. Callers must already hold the
    /// operation queue (the public wrapper above, or a
    /// synchronization pass) — this variant never submits its own
    /// operation, so passes cannot deadlock waiting for themselves.
    private func rescheduleAllMedicationRemindersLocked(pets: [Pet], schedules: [MedicationSchedule], remindersEnabled: Bool, completion: (() -> Void)? = nil) {
        guard remindersEnabled else { completion?(); return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { completion?(); return }
            center.getPendingNotificationRequests { requests in
                let stale = requests.map(\.identifier).filter { $0.hasPrefix("pc360-med-") }
                center.removePendingNotificationRequests(withIdentifiers: stale)
                var budget = max(0, 60 - (requests.count - stale.count))
                for eligible in Self.eligibleReminders(pets: pets, schedules: schedules) {
                    budget = self.scheduleMedicationReminderLocked(medication: eligible.medication, petName: eligible.petName, budget: budget)
                }
                completion?()
            }
        }
    }

    /// Removes every pending medication reminder for one medication,
    /// whatever day/dose identifiers were used. Called on edit (before
    /// re-scheduling), on delete, and when the owning pet is deleted, so
    /// no notification is ever generated for a deleted or expired schedule.
    /// Every pending-identifier prefix that belongs to one medication:
    /// its dose reminders AND its refill reminder (which uses a different
    /// identifier shape). Deletion paths rely on this being complete.
    static func medicationCancellationPrefixes(medicationID: UUID) -> [String] {
        ["pc360-med-\(medicationID.uuidString)-",
         "pc360-\(refillReminderID(medicationID: medicationID))"]
    }

    static func refillReminderID(medicationID: UUID) -> String {
        "refill-\(medicationID.uuidString)"
    }

    func cancelMedicationReminders(medicationID: UUID) {
        let prefixes = Self.medicationCancellationPrefixes(medicationID: medicationID)
        let center = UNUserNotificationCenter.current()
        operations.submit { done in
            center.getPendingNotificationRequests { requests in
                let ids = requests.map(\.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
                center.removePendingNotificationRequests(withIdentifiers: ids)
                done()
            }
        }
    }

    func scheduleFeedingReminder(schedule food: FoodSchedule, petName: String) {
        operations.submit { done in
            self.scheduleFeedingReminderLocked(schedule: food, petName: petName)
            done()
        }
    }

    private func scheduleFeedingReminderLocked(schedule food: FoodSchedule, petName: String) {
        guard ReminderCategory.feeding.isEnabled else { return }
        var date = Calendar.current.date(bySettingHour: food.timeMinutes / 60, minute: food.timeMinutes % 60, second: 0, of: Date()) ?? Date()
        if date < Date() { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date }
        schedule(id: "feed-\(food.id.uuidString)", title: "Feeding time for \(petName)",
                 body: "\(food.foodBrand) — \(food.portion)", fireDate: date, repeatsDaily: true,
                 soundName: NotificationSoundPreferences.resolvedFileName(species: food.pet?.species))
    }

    func scheduleOneOff(id: String, title: String, body: String, fireDate: Date, species: PetSpecies? = nil) {
        operations.submit { done in
            self.scheduleOneOffLocked(id: id, title: title, body: body, fireDate: fireDate, species: species)
            done()
        }
    }

    private func scheduleOneOffLocked(id: String, title: String, body: String, fireDate: Date, species: PetSpecies? = nil) {
        guard fireDate > Date() else { return }
        if id.hasPrefix("appt-"), !ReminderCategory.appointments.isEnabled { return }
        if id.hasPrefix("ins-"), !ReminderCategory.insurance.isEnabled { return }
        schedule(id: id, title: title, body: body, fireDate: fireDate,
                 soundName: NotificationSoundPreferences.resolvedFileName(species: species))
    }

    func scheduleVaccinationReminder(_ vaccination: VaccinationRecord, petName: String) {
        operations.submit { done in
            self.scheduleVaccinationReminderLocked(vaccination, petName: petName)
            done()
        }
    }

    private func scheduleVaccinationReminderLocked(_ vaccination: VaccinationRecord, petName: String) {
        guard let exp = vaccination.expirationDate else { return }
        let fire = Calendar.current.date(byAdding: .day, value: -7, to: exp) ?? exp
        guard ReminderCategory.vaccinations.isEnabled else { return }
        scheduleOneOffLocked(id: "vax-\(vaccination.id.uuidString)", title: "Vaccination due soon",
                       body: "\(petName): \(vaccination.vaccineName) expires \(exp.formatted(date: .abbreviated, time: .omitted))", fireDate: fire,
                       species: vaccination.pet?.species)
    }

    func scheduleRefillReminder(medication: Medication, petName: String) {
        operations.submit { done in
            self.scheduleRefillReminderLocked(medication: medication, petName: petName)
            done()
        }
    }

    private func scheduleRefillReminderLocked(medication: Medication, petName: String) {
        // Refill reminders belong to the Medications category
        // (audit fix, 2026-11-09): without this guard, logging the
        // final dose re-scheduled a refill reminder even when the
        // user had switched the Medications category off — every
        // other scheduling method already checks its category.
        guard ReminderCategory.medications.isEnabled else { return }
        let fire = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        scheduleOneOffLocked(id: Self.refillReminderID(medicationID: medication.id), title: "Refill reminder",
                       body: "\(petName): \(medication.name) is running low (\(medication.remainingSupply) left)", fireDate: fire,
                       species: medication.pet?.species)
    }

    /// Rebuilds the one-off reminder types from current data, using the
    /// same deterministic identifiers as the save-time scheduling, so
    /// nothing duplicates: active feeding schedules, vaccinations with a
    /// future expiry, future uncompleted appointments, and insurance
    /// renewals. Called when the user switches global reminders back on
    /// and permission is granted (v1.2.3).
    func rebuildOneOffReminders(pets: [Pet], policies: [InsurancePolicy], completion: (() -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { completion?(); return }
            self.rebuildOneOffRemindersAuthorized(pets: pets, policies: policies)
            completion?()
        }
    }

    /// The single FIFO queue every notification-centre mutation
    /// sequence runs on (2026-11-09 ordering fix).
    private let operations = NotificationOperationQueue()

    /// THE centralized reminder synchronization entry point (v1.2.5):
    /// launch, foreground, Settings re-enable and pet restoration all
    /// call this. The whole pass — category cleanup, medication
    /// rebuild, one-off rebuild — runs as ONE operation on the FIFO
    /// queue (2026-11-09; previously SyncCoordinator, whose
    /// coalescing could drop a queued pass — the FIFO queue runs
    /// every pass, in order, never interleaved with an editor's
    /// cancel/schedule sequence or a cancelAll).
    func synchronizeReminders(pets: [Pet], schedules: [MedicationSchedule],
                              policies: [InsurancePolicy], remindersEnabled: Bool) {
        operations.submit { done in
            // Category cleanup (2026-11-06): a category the user
            // switched off loses its pending requests at the next
            // sync, not just its future scheduling. Runs INSIDE the
            // pass operation so its snapshot cannot interleave with
            // another operation's scheduling.
            let disabled = remindersEnabled
                ? ReminderCategory.allCases.filter { !$0.isEnabled }
                : []
            self.cancelPendingLocked(withPrefixes: disabled.flatMap(\.pendingPrefixes)) {
                self.rescheduleAllMedicationRemindersLocked(pets: pets, schedules: schedules,
                                                              remindersEnabled: remindersEnabled) {
                    if remindersEnabled {
                        self.rebuildOneOffReminders(pets: pets, policies: policies) { done() }
                    } else {
                        done()
                    }
                }
            }
        }
    }

    private func rebuildOneOffRemindersAuthorized(pets: [Pet], policies: [InsurancePolicy]) {
        for pet in pets where !pet.isArchived {
            for food in pet.foodSchedules where food.isActive {
                scheduleFeedingReminderLocked(schedule: food, petName: pet.name)
            }
            for vax in pet.vaccinations {
                scheduleVaccinationReminderLocked(vax, petName: pet.name)
            }
            for appt in pet.appointments where Self.shouldScheduleAppointmentReminder(appt) {
                scheduleOneOffLocked(id: "appt-\(appt.id.uuidString)",
                               title: "Vet appointment: \(pet.name)", body: appt.title,
                               fireDate: appt.date.addingTimeInterval(-3600), species: pet.species)
            }
        }
        for policy in Self.eligibleInsurancePolicies(policies: policies, pets: pets) {
            guard let renewal = policy.renewalDate else { continue }
            let fire = Calendar.current.date(byAdding: .day, value: -14, to: renewal) ?? renewal
            scheduleOneOffLocked(id: "ins-\(policy.id.uuidString)", title: "Insurance renewal soon",
                           body: "\(policy.petName): \(policy.provider) renews soon", fireDate: fire,
                           species: pets.first(where: { $0.id == policy.petID })?.species)
        }
        // Refill reminders are part of the rebuild too (v1.2.4): any
        // active medication already at/below its refill threshold gets
        // its (deterministic-ID) refill reminder re-armed.
        for pet in pets where !pet.isArchived {
            for medication in pet.medications where medication.isActive && medication.needsRefill {
                scheduleRefillReminderLocked(medication: medication, petName: pet.name)
            }
        }
    }

    func cancelAll() {
        // Queued like every other mutation sequence (2026-11-09):
        // a save whose cancellation snapshot is still in flight
        // must have its schedule submitted BEFORE this removal, or
        // the removal would be submitted first and the save's
        // reminders would land after it and survive.
        operations.submit { done in
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            done()
        }
    }

    func cancel(ids: [String]) {
        // Queued like every other mutation (final review fix,
        // 2026-11-09): an editor's cancel-then-add pair now reaches
        // the centre as two FIFO operations in call order, so the
        // cancellation-before-add behavior is preserved by the
        // queue itself rather than by same-call-stack timing.
        operations.submit { done in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids.map { "pc360-\($0)" })
            done()
        }
    }

    /// Cancels pending requests whose namespaced id starts with any
    /// of the given raw prefixes (e.g. "appt-"), used when a reminder
    /// category is switched off and by the sync's category cleanup.
    func cancelPending(withPrefixes prefixes: [String]) {
        operations.submit { done in
            self.cancelPendingLocked(withPrefixes: prefixes, completion: done)
        }
    }

    /// The cancellation itself; callers must already hold the
    /// operation queue (the public wrapper above, or a
    /// synchronization pass). An empty prefix list completes
    /// immediately without touching the centre.
    private func cancelPendingLocked(withPrefixes prefixes: [String], completion: @escaping () -> Void) {
        guard !prefixes.isEmpty else { completion(); return }
        let namespaced = prefixes.map { "pc360-\($0)" }
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { id in namespaced.contains { id.hasPrefix($0) } }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            completion()
        }
    }

    /// Settings → "Send test notification": a real local notification
    /// ~5 seconds out, using the sound that a reminder for the given
    /// pet species would actually use right now.
    func scheduleTestNotification(species: PetSpecies?) {
        let content = UNMutableNotificationContent()
        content.title = "PetCare 360 test notification"
        content.body = "This is the sound your reminders will use."
        let soundName = NotificationSoundPreferences.resolvedFileName(species: species)
        content.sound = soundName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "pc360-test-\(UUID().uuidString)", content: content, trigger: trigger)
        operations.submit { done in
            UNUserNotificationCenter.current().add(request)
            done()
        }
    }
}
