import Foundation
import UserNotifications


/// Serializes multi-step work whose steps complete asynchronously:
/// only one pass runs at a time; passes submitted while one is running
/// are coalesced — only the LATEST queued pass runs next. Used for
/// reminder synchronization so a launch pass and a foreground pass can
/// never interleave their pending-request cleanup and scheduling
/// (v1.2.5). Pure logic, unit-tested.
final class SyncCoordinator {
    private let stateQueue = DispatchQueue(label: "com.petcare360.sync-coordinator")
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

/// Local notifications only. Authorization is requested solely when the
/// user enables reminders. Identifiers are namespaced `pc360-` and are
/// deterministic per schedule, so re-scheduling never duplicates.
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

    private func schedule(id: String, title: String, body: String, fireDate: Date, repeatsDaily: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let dailyComps = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: repeatsDaily ? dailyComps : comps, repeats: repeatsDaily)
        let request = UNNotificationRequest(identifier: "pc360-\(id)", content: content, trigger: trigger)
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
    @discardableResult
    func scheduleMedicationReminder(medication: Medication, petName: String, budget: Int = .max) -> Int {
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
                         fireDate: slot.scheduledDate)
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
    func cancelDoseReminders(medicationID: UUID, completion: (() -> Void)?) {
        let prefix = "pc360-med-\(medicationID.uuidString)-"
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
            completion?()
        }
    }

    /// Completed appointments never get reminders; past ones neither.
    static func shouldScheduleAppointmentReminder(_ appointment: VetAppointment) -> Bool {
        !appointment.isCompleted && appointment.date > Date()
    }

    func rescheduleAllMedicationReminders(pets: [Pet], schedules: [MedicationSchedule], remindersEnabled: Bool, completion: (() -> Void)? = nil) {
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
                    budget = self.scheduleMedicationReminder(medication: eligible.medication, petName: eligible.petName, budget: budget)
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
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    func scheduleFeedingReminder(schedule food: FoodSchedule, petName: String) {
        var date = Calendar.current.date(bySettingHour: food.timeMinutes / 60, minute: food.timeMinutes % 60, second: 0, of: Date()) ?? Date()
        if date < Date() { date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date }
        schedule(id: "feed-\(food.id.uuidString)", title: "Feeding time for \(petName)",
                 body: "\(food.foodBrand) — \(food.portion)", fireDate: date, repeatsDaily: true)
    }

    func scheduleOneOff(id: String, title: String, body: String, fireDate: Date) {
        guard fireDate > Date() else { return }
        schedule(id: id, title: title, body: body, fireDate: fireDate)
    }

    func scheduleVaccinationReminder(_ vaccination: VaccinationRecord, petName: String) {
        guard let exp = vaccination.expirationDate else { return }
        let fire = Calendar.current.date(byAdding: .day, value: -7, to: exp) ?? exp
        scheduleOneOff(id: "vax-\(vaccination.id.uuidString)", title: "Vaccination due soon",
                       body: "\(petName): \(vaccination.vaccineName) expires \(exp.formatted(date: .abbreviated, time: .omitted))", fireDate: fire)
    }

    func scheduleRefillReminder(medication: Medication, petName: String) {
        let fire = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        scheduleOneOff(id: Self.refillReminderID(medicationID: medication.id), title: "Refill reminder",
                       body: "\(petName): \(medication.name) is running low (\(medication.remainingSupply) left)", fireDate: fire)
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

    private let syncCoordinator = SyncCoordinator()

    /// THE centralized reminder synchronization entry point (v1.2.5):
    /// launch, foreground, Settings re-enable and pet restoration all
    /// call this. Passes are serialized through the SyncCoordinator —
    /// a pass submitted while another is in flight is coalesced and
    /// runs after, never interleaved — so pending-request cleanup and
    /// scheduling from two passes cannot fight. Medication dose
    /// reminders (7-day horizon, per-medication preferences, global
    /// setting, pending-limit budget) run first, then the one-off
    /// types and refill reminders.
    func synchronizeReminders(pets: [Pet], schedules: [MedicationSchedule],
                              policies: [InsurancePolicy], remindersEnabled: Bool) {
        syncCoordinator.submit { done in
            self.rescheduleAllMedicationReminders(pets: pets, schedules: schedules,
                                                  remindersEnabled: remindersEnabled) {
                if remindersEnabled {
                    self.rebuildOneOffReminders(pets: pets, policies: policies) { done() }
                } else {
                    done()
                }
            }
        }
    }

    private func rebuildOneOffRemindersAuthorized(pets: [Pet], policies: [InsurancePolicy]) {
        for pet in pets where !pet.isArchived {
            for food in pet.foodSchedules where food.isActive {
                scheduleFeedingReminder(schedule: food, petName: pet.name)
            }
            for vax in pet.vaccinations {
                scheduleVaccinationReminder(vax, petName: pet.name)
            }
            for appt in pet.appointments where !appt.isCompleted && appt.date > Date() {
                scheduleOneOff(id: "appt-\(appt.id.uuidString)",
                               title: "Vet appointment: \(pet.name)", body: appt.title,
                               fireDate: appt.date.addingTimeInterval(-3600))
            }
        }
        for policy in Self.eligibleInsurancePolicies(policies: policies, pets: pets) {
            guard let renewal = policy.renewalDate else { continue }
            let fire = Calendar.current.date(byAdding: .day, value: -14, to: renewal) ?? renewal
            scheduleOneOff(id: "ins-\(policy.id.uuidString)", title: "Insurance renewal soon",
                           body: "\(policy.petName): \(policy.provider) renews soon", fireDate: fire)
        }
        // Refill reminders are part of the rebuild too (v1.2.4): any
        // active medication already at/below its refill threshold gets
        // its (deterministic-ID) refill reminder re-armed.
        for pet in pets where !pet.isArchived {
            for medication in pet.medications where medication.isActive && medication.needsRefill {
                scheduleRefillReminder(medication: medication, petName: pet.name)
            }
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids.map { "pc360-\($0)" })
    }
}
