import XCTest
@testable import PetCare360

/// Regression tests for the approved fix batch (2026-11-10):
/// Reptile app icon removed in favour of Turtle, care-task reminder
/// series, dual appointment reminders, Home appointment pinning,
/// and the document-scanning removal. Pure, deterministic logic
/// only — the same discipline as the rest of the suite; actual
/// notification delivery and icon rendering are iOS behaviour and
/// are covered by the manual device checklist in the fix report.
final class PetCare360ApprovedFixesTests: XCTestCase {

    // MARK: App icon — Reptile gone, Turtle kept

    func testNoReptileAppIconOptionRemains() {
        XCTAssertFalse(AppIconOption.all.contains { $0.id == "reptile" })
        XCTAssertFalse(AppIconOption.all.contains { $0.alternateName == "AppIconReptile" })
        XCTAssertFalse(AppIconOption.all.contains { $0.previewImageName == "IconPreviewReptile" })
        XCTAssertFalse(AppIconOption.all.contains { $0.label == "Reptiles" })
    }

    func testTurtleAppIconOptionIsPresentAndCorrect() {
        let turtle = AppIconOption.all.first { $0.id == "turtle" }
        XCTAssertNotNil(turtle)
        XCTAssertEqual(turtle?.label, "Turtle")
        XCTAssertEqual(turtle?.alternateName, "AppIconTurtle")
        XCTAssertEqual(turtle?.previewImageName, "IconPreviewTurtle")
        XCTAssertEqual(AppIconOption.all.count, 8, "The bundled set stays at eight options")
    }

    // MARK: Care Task Reminders category + interval preference

    func testCareTaskReminderCategory() {
        XCTAssertEqual(ReminderCategory.careTasks.label, "Care Task Reminders")
        XCTAssertEqual(ReminderCategory.careTasks.defaultsKey, "pc-notif-careTasks")
        XCTAssertEqual(ReminderCategory.careTasks.pendingPrefixes, ["task-"])
        XCTAssertTrue(ReminderCategory.allCases.contains(.careTasks))
    }

    func testTaskReminderIntervalDefaultsTo45AndValidatesChoices() {
        let defaults = UserDefaults.standard
        let key = TaskReminderPreferences.intervalKey
        let saved = defaults.object(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        XCTAssertEqual(TaskReminderPreferences.intervalMinutes, 45,
                       "No stored preference must mean the 45-minute default")
        defaults.set(60, forKey: key)
        XCTAssertEqual(TaskReminderPreferences.intervalMinutes, 60,
                       "A stored value from the offered choices is honoured")
        defaults.set(37, forKey: key)
        XCTAssertEqual(TaskReminderPreferences.intervalMinutes, 45,
                       "A stored value outside the offered choices falls back to 45")
        XCTAssertEqual(TaskReminderPreferences.intervalChoicesMinutes.first, 15)
        XCTAssertTrue(TaskReminderPreferences.intervalChoicesMinutes.contains(45))
    }

    // MARK: Task reminder series

    func testTaskReminderPlanStartsAtScheduledTimeAndRepeatsOnInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduled = now.addingTimeInterval(3600)
        let plan = NotificationService.taskReminderPlan(
            scheduledDate: scheduled, now: now, intervalMinutes: 45)
        XCTAssertEqual(plan.count, 17)
        XCTAssertEqual(plan.first?.occurrence, 0)
        XCTAssertEqual(plan.first?.fireDate, scheduled,
                       "The first reminder fires AT the task's scheduled time")
        for (previous, next) in zip(plan, plan.dropFirst()) {
            XCTAssertEqual(next.fireDate.timeIntervalSince(previous.fireDate), 2700,
                           "Repeats are spaced by the 45-minute interval")
            XCTAssertEqual(next.occurrence, previous.occurrence + 1)
        }
    }

    func testTaskReminderPlanForOverdueTaskResumesOnTheGrid() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduled = now.addingTimeInterval(-100 * 60) // 100 minutes ago
        let plan = NotificationService.taskReminderPlan(
            scheduledDate: scheduled, now: now, intervalMinutes: 45)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > now },
                      "No reminder is scheduled in the past")
        // Grid anchored at the scheduled time: fires at +0,45,90,135…
        // minutes from it, so the first future fire is at +135.
        XCTAssertEqual(plan.first?.occurrence, 3)
        XCTAssertEqual(plan.first?.fireDate, scheduled.addingTimeInterval(135 * 60))
    }

    func testTaskReminderPlanHonoursCustomInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = NotificationService.taskReminderPlan(
            scheduledDate: now.addingTimeInterval(600), now: now, intervalMinutes: 30)
        XCTAssertEqual(plan.count, 17)
        XCTAssertEqual(plan[1].fireDate.timeIntervalSince(plan[0].fireDate), 1800)
    }

    func testTaskReminderIdentifiersAreDeterministic() {
        let id = UUID()
        XCTAssertEqual(NotificationService.taskReminderID(taskID: id, occurrence: 2),
                       "task-\(id.uuidString)-2")
    }

    func testTaskReminderEligibility() {
        let pet = Pet(name: "Buddy")
        let archived = Pet(name: "Old")
        archived.isArchived = true
        let open = CareTask(title: "Walk", petID: pet.id, petName: pet.name, date: Date().addingTimeInterval(3600))
        let done = CareTask(title: "Feed", petID: pet.id, petName: pet.name, date: Date().addingTimeInterval(1800))
        done.isCompleted = true
        let orphan = CareTask(title: "Vet", petID: UUID(), petName: "Ghost", date: Date().addingTimeInterval(900))
        let archivedPetTask = CareTask(title: "Meds", petID: archived.id, petName: archived.name, date: Date().addingTimeInterval(900))
        XCTAssertTrue(NotificationService.shouldScheduleTaskReminder(open))
        XCTAssertFalse(NotificationService.shouldScheduleTaskReminder(done),
                       "A completed task never gets reminders")
        let eligible = NotificationService.eligibleTaskReminders(
            tasks: [open, done, orphan, archivedPetTask], pets: [pet, archived])
        XCTAssertEqual(eligible.map { $0.task.id }, [open.id],
                       "Completed, orphaned and archived-pet tasks are all excluded")
        XCTAssertEqual(eligible.first?.petName, "Buddy")
    }

    // MARK: Appointment reminders — one hour AND thirty minutes

    func testAppointmentReminderIDsCoverBothReminders() {
        let id = UUID()
        XCTAssertEqual(NotificationService.appointmentReminderIDs(appointmentID: id),
                       ["appt-\(id.uuidString)", "appt30-\(id.uuidString)"])
        XCTAssertEqual(ReminderCategory.appointments.pendingPrefixes, ["appt-", "appt30-"],
                       "Category cleanup must match BOTH appointment reminder prefixes")
    }

    func testAppointmentScheduleHasBothRemindersWhenBothAreInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        let schedule = NotificationService.appointmentReminderSchedule(
            appointmentID: id, date: now.addingTimeInterval(2 * 3600), now: now)
        XCTAssertEqual(schedule.count, 2)
        XCTAssertEqual(schedule[0].id, "appt-\(id.uuidString)")
        XCTAssertEqual(schedule[0].fireDate, now.addingTimeInterval(3600))
        XCTAssertEqual(schedule[1].id, "appt30-\(id.uuidString)")
        XCTAssertEqual(schedule[1].fireDate, now.addingTimeInterval(5400))
    }

    func testAppointmentScheduleKeepsOnlyTheValidReminder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let id = UUID()
        // 45 minutes away: the 1-hour time has passed, the
        // 30-minute time has not — only the valid one is scheduled.
        let schedule = NotificationService.appointmentReminderSchedule(
            appointmentID: id, date: now.addingTimeInterval(45 * 60), now: now)
        XCTAssertEqual(schedule.count, 1)
        XCTAssertEqual(schedule.first?.id, "appt30-\(id.uuidString)")
        XCTAssertEqual(schedule.first?.fireDate, now.addingTimeInterval(15 * 60))
        // 20 minutes away: both times have passed — nothing scheduled.
        XCTAssertTrue(NotificationService.appointmentReminderSchedule(
            appointmentID: id, date: now.addingTimeInterval(20 * 60), now: now).isEmpty)
    }

    func testAppointmentReminderNoticeExplainsPassedTimes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertNil(NotificationService.appointmentReminderNotice(
            appointmentDate: now.addingTimeInterval(2 * 3600), now: now),
            "Both reminders valid — no notice needed")
        let partial = NotificationService.appointmentReminderNotice(
            appointmentDate: now.addingTimeInterval(45 * 60), now: now)
        XCTAssertTrue(partial?.contains("only the 30-minute reminder") ?? false,
                      "A passed 1-hour time is explained, never silently dropped")
        let both = NotificationService.appointmentReminderNotice(
            appointmentDate: now.addingTimeInterval(20 * 60), now: now)
        XCTAssertTrue(both?.contains("Both reminder times") ?? false)
        let past = NotificationService.appointmentReminderNotice(
            appointmentDate: now.addingTimeInterval(-600), now: now)
        XCTAssertTrue(past?.contains("already passed") ?? false)
    }

    // MARK: Home — nearest upcoming appointment pinned first

    private func item(_ kind: ScheduleItem.Kind, _ title: String, _ date: Date, id: String) -> ScheduleItem {
        ScheduleItem(id: id, petID: UUID(), petName: "Buddy", species: .dog, kind: kind,
                     title: title, detail: "", date: date,
                     status: ScheduleStatus.bucket(for: date, now: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    func testHomeCardPinsNearestUpcomingAppointmentFirst() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let overdueVax = item(.vaccination, "Rabies due", now.addingTimeInterval(-30 * 86400), id: "vax-1")
        let feeding = item(.feeding, "Feeding", now.addingTimeInterval(3600), id: "feed-1")
        let laterAppt = item(.appointment, "Checkup", now.addingTimeInterval(5 * 86400), id: "appt-2")
        let nearAppt = item(.appointment, "Dental", now.addingTimeInterval(2 * 86400), id: "appt-1")
        // Chronological order from HomeSchedule.build: overdue first.
        let items = [overdueVax, feeding, nearAppt, laterAppt]
        let card = HomeSchedule.homeCardItems(items, now: now)
        XCTAssertEqual(card.first?.id, "appt-1",
                       "The NEAREST upcoming appointment leads the card, ahead of overdue items")
        XCTAssertEqual(card.filter { $0.id == "appt-1" }.count, 1,
                       "The pinned appointment is never duplicated in the fill")
        XCTAssertEqual(Set(card.map { $0.id }).count, card.count)
        XCTAssertEqual(card.count, 4)
        XCTAssertEqual(card.dropFirst().map { $0.id }, ["vax-1", "feed-1", "appt-2"],
                       "Remaining slots fill chronologically")
    }

    func testHomeCardDoesNotPinAnAppointmentWhoseTimeHasPassed() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let earlierToday = item(.appointment, "Morning visit", now.addingTimeInterval(-3600), id: "appt-0")
        let feeding = item(.feeding, "Feeding", now.addingTimeInterval(3600), id: "feed-1")
        let card = HomeSchedule.homeCardItems([earlierToday, feeding], now: now)
        XCTAssertEqual(card.map { $0.id }, ["appt-0", "feed-1"],
                       "No pinning when there is no upcoming appointment — plain order")
    }

    func testHomeCardWithoutAppointmentsIsTheChronologicalPrefix() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let items = (0..<7).map { item(.feeding, "Feeding \($0)", now.addingTimeInterval(Double($0) * 3600), id: "feed-\($0)") }
        let card = HomeSchedule.homeCardItems(items, now: now)
        XCTAssertEqual(card.count, 5)
        XCTAssertEqual(card.map { $0.id }, items.prefix(5).map { $0.id })
    }

    // MARK: Document storage (scanning removed)

    func testDocumentStorageReplacesScanningAsThePremiumFeature() {
        XCTAssertEqual(PremiumFeature.documentStorage.label, "Document storage")
        XCTAssertTrue(PremiumFeature.paywallFeatures.contains(.documentStorage),
                      "The paywall keeps advertising the document benefit, without scanning")
        XCTAssertFalse(PremiumFeature.documentStorage.label.lowercased().contains("scan"))
        XCTAssertFalse(PremiumPrompt.documentStorage.title.lowercased().contains("scan"))
        XCTAssertFalse(PremiumPrompt.documentStorage.message.lowercased().contains("scan"))
        XCTAssertFalse(PremiumPrompt.documentStorage.message.lowercased().contains("ocr"))
    }

    // MARK: Identifier contract — scheduled ids vs cleanup (audit 2026-11-10)
    //
    // Scheduling code uses RAW identifiers; every request that
    // actually sits in the notification centre carries the pc360-
    // namespace applied by NotificationService.pendingIdentifier.
    // Cleanup paths match pending requests, so they must compare
    // in the namespaced form. These tests pin that contract for
    // every category: if a raw id format or a cleanup prefix ever
    // drifts (the reported "task- vs pc360-task-" mismatch), they
    // fail.

    func testPendingIdentifierAppliesTheNamespace() {
        XCTAssertEqual(NotificationService.pendingIdentifier(for: "task-X-0"), "pc360-task-X-0")
        XCTAssertEqual(NotificationService.pendingIdentifier(for: "appt-Y"), "pc360-appt-Y")
    }

    func testTaskCleanupPrefixesMatchScheduledTaskIdentifiers() {
        let taskID = UUID()
        // The identifiers a scheduled series actually has in the centre.
        let scheduled = (0..<17).map {
            NotificationService.pendingIdentifier(
                for: NotificationService.taskReminderID(taskID: taskID, occurrence: $0))
        }
        XCTAssertEqual(scheduled.first, "pc360-task-\(taskID.uuidString)-0")
        // Edit-time cleanup (scheduleTaskReminderLocked) matches the
        // per-task namespaced prefix.
        let editPrefix = NotificationService.pendingIdentifier(for: "task-\(taskID.uuidString)")
        XCTAssertTrue(scheduled.allSatisfy { $0.hasPrefix(editPrefix) },
                      "Edit-time cleanup must match every occurrence of the task's series")
        // Complete/delete cleanup (cancelTaskReminders → cancelPending)
        // and the sync's wholesale cleanup both reduce to the
        // category prefix, namespaced.
        let categoryPrefix = NotificationService.pendingIdentifier(
            for: ReminderCategory.careTasks.pendingPrefixes[0])
        XCTAssertEqual(categoryPrefix, "pc360-task-")
        XCTAssertTrue(scheduled.allSatisfy { $0.hasPrefix(categoryPrefix) },
                      "Category/rebuild cleanup must match the task series")
        // An unrelated task's reminders must NOT match this task's
        // per-task prefix.
        let other = NotificationService.pendingIdentifier(
            for: NotificationService.taskReminderID(taskID: UUID(), occurrence: 0))
        XCTAssertFalse(other.hasPrefix(editPrefix),
                       "One task's cleanup must never remove another task's reminders")
        XCTAssertTrue(other.hasPrefix(categoryPrefix))
    }

    func testAppointmentCleanupPrefixesMatchBothScheduledIdentifiers() {
        let apptID = UUID()
        let ids = NotificationService.appointmentReminderIDs(appointmentID: apptID)
        let pending = ids.map { NotificationService.pendingIdentifier(for: $0) }
        XCTAssertEqual(ReminderCategory.appointments.pendingPrefixes, ["appt-", "appt30-"])
        XCTAssertTrue(pending[0].hasPrefix(
            NotificationService.pendingIdentifier(for: "appt-")))
        XCTAssertTrue(pending[1].hasPrefix(
            NotificationService.pendingIdentifier(for: "appt30-")))
        // The 30-minute identifier does NOT carry the plain appt-
        // prefix — which is exactly why cleanup must list both.
        XCTAssertFalse(pending[1].hasPrefix(
            NotificationService.pendingIdentifier(for: "appt-")))
    }

    func testMedicationCleanupPrefixesMatchScheduledIdentifiers() {
        let medID = UUID()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        let dosePending = NotificationService.pendingIdentifier(
            for: NotificationService.doseReminderID(medicationID: medID, day: day, minutes: 480))
        let refillPending = NotificationService.pendingIdentifier(
            for: NotificationService.refillReminderID(medicationID: medID))
        // Production cancellation prefixes (already in pending form).
        let prefixes = NotificationService.medicationCancellationPrefixes(medicationID: medID)
        XCTAssertEqual(prefixes.count, 2)
        XCTAssertTrue(dosePending.hasPrefix(prefixes[0]),
                      "Dose-reminder cleanup must match scheduled dose identifiers")
        XCTAssertTrue(refillPending.hasPrefix(prefixes[1]),
                      "Refill cleanup must match the scheduled refill identifier")
        XCTAssertEqual(ReminderCategory.medications.pendingPrefixes, ["med-", "refill-"])
    }

    func testTaskReminderPlanHonoursCapacityCap() {
        // The save path passes min(17, capacity) as maxOccurrences;
        // a capacity of zero must arm nothing, a small capacity a
        // short series — the plan function is what enforces it.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduled = now.addingTimeInterval(3600)
        XCTAssertTrue(NotificationService.taskReminderPlan(
            scheduledDate: scheduled, now: now, intervalMinutes: 45, maxOccurrences: 0).isEmpty)
        XCTAssertEqual(NotificationService.taskReminderPlan(
            scheduledDate: scheduled, now: now, intervalMinutes: 45, maxOccurrences: 3).count, 3)
    }

    func testTaskReminderPlanIsDeterministicSoReschedulingReplaces() {
        // Duplicate prevention rests on this: the same task at the
        // same moment always yields the same occurrences, hence
        // the same identifiers, so re-scheduling replaces the
        // pending requests instead of duplicating them.
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let scheduled = now.addingTimeInterval(-30 * 60)
        let first = NotificationService.taskReminderPlan(
            scheduledDate: scheduled, now: now, intervalMinutes: 45)
        let second = NotificationService.taskReminderPlan(
            scheduledDate: scheduled, now: now, intervalMinutes: 45)
        XCTAssertEqual(first.map { $0.occurrence }, second.map { $0.occurrence })
        XCTAssertEqual(first.map { $0.fireDate }, second.map { $0.fireDate })
        XCTAssertEqual(Set(first.map { $0.occurrence }).count, first.count,
                       "Occurrences within one plan are unique — no self-duplication")
    }

    func testCareTaskCategoryDisableGateReadsUserDefaults() {
        let defaults = UserDefaults.standard
        let key = ReminderCategory.careTasks.defaultsKey
        let saved = defaults.object(forKey: key)
        defer {
            if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        XCTAssertTrue(ReminderCategory.careTasks.isEnabled, "Categories default ON")
        defaults.set(false, forKey: key)
        XCTAssertFalse(ReminderCategory.careTasks.isEnabled,
                       "Switching Care Task Reminders off must close the scheduling gate")
    }

    // MARK: Cleanup selection — production logic (review 2026-11-10)
    //
    // These tests drive NotificationService.staleIdentifiers, the
    // ONE pure function every snapshot-based cleanup path in the
    // service now uses to decide which pending requests to remove
    // (task edit/rebuild, dose + medication cancellation, category
    // prefix cancellation). What they prove: given a realistic
    // pending list, the production selection picks exactly the
    // right identifiers. What they do NOT prove: that
    // UNUserNotificationCenter actually removes or delivers
    // anything — that needs the live centre in the app process,
    // which this suite deliberately never touches (see the final
    // review report for the proposed injectable seam).

    /// A realistic mixed pending list, in PENDING form.
    private func mixedPendingIdentifiers(taskA: UUID, taskB: UUID, appt: UUID, med: UUID, otherMed: UUID) -> [String] {
        let p = NotificationService.pendingIdentifier(for:)
        return [
            p(NotificationService.taskReminderID(taskID: taskA, occurrence: 0)),
            p(NotificationService.taskReminderID(taskID: taskA, occurrence: 1)),
            p(NotificationService.taskReminderID(taskID: taskA, occurrence: 2)),
            p(NotificationService.taskReminderID(taskID: taskB, occurrence: 0)),
            p(NotificationService.appointmentReminderIDs(appointmentID: appt)[0]),
            p(NotificationService.appointmentReminderIDs(appointmentID: appt)[1]),
            p(NotificationService.doseReminderID(medicationID: med, day: Date(timeIntervalSince1970: 1_700_000_000), minutes: 480)),
            p(NotificationService.refillReminderID(medicationID: med)),
            p(NotificationService.doseReminderID(medicationID: otherMed, day: Date(timeIntervalSince1970: 1_700_000_000), minutes: 480))
        ]
    }

    func testCleanupSelectionForTaskEditRemovesOnlyThatTaskSeries() {
        let (a, b, appt, med, otherMed) = (UUID(), UUID(), UUID(), UUID(), UUID())
        let pending = mixedPendingIdentifiers(taskA: a, taskB: b, appt: appt, med: med, otherMed: otherMed)
        // The exact selection scheduleTaskReminderLocked performs
        // before re-arming an edited task's series.
        let selected = NotificationService.staleIdentifiers(
            in: pending,
            matchingAnyPrefix: [NotificationService.pendingIdentifier(for: "task-\(a.uuidString)")])
        XCTAssertEqual(selected.count, 3, "All three pending occurrences of the edited task")
        XCTAssertTrue(selected.allSatisfy { $0.contains(a.uuidString) })
        XCTAssertFalse(selected.contains { $0.contains(b.uuidString) },
                       "Another task's reminders are never selected")
    }

    func testCleanupSelectionForCareTaskCategoryDisableRemovesAllTaskRequestsOnly() {
        let (a, b, appt, med, otherMed) = (UUID(), UUID(), UUID(), UUID(), UUID())
        let pending = mixedPendingIdentifiers(taskA: a, taskB: b, appt: appt, med: med, otherMed: otherMed)
        // The selection the category cleanup performs when Care
        // Task Reminders is switched off (cancelPending path).
        let selected = NotificationService.staleIdentifiers(
            in: pending,
            matchingAnyPrefix: ReminderCategory.careTasks.pendingPrefixes.map {
                NotificationService.pendingIdentifier(for: $0)
            })
        XCTAssertEqual(selected.count, 4, "Every task request (3 of A + 1 of B), nothing else")
        XCTAssertTrue(selected.allSatisfy { $0.hasPrefix("pc360-task-") })
    }

    func testCleanupSelectionForAppointmentCategoryDisableRemovesBothIdentifiers() {
        let (a, b, appt, med, otherMed) = (UUID(), UUID(), UUID(), UUID(), UUID())
        let pending = mixedPendingIdentifiers(taskA: a, taskB: b, appt: appt, med: med, otherMed: otherMed)
        let selected = NotificationService.staleIdentifiers(
            in: pending,
            matchingAnyPrefix: ReminderCategory.appointments.pendingPrefixes.map {
                NotificationService.pendingIdentifier(for: $0)
            })
        XCTAssertEqual(selected.count, 2, "Both the -60 and -30 appointment reminders")
        XCTAssertTrue(selected.allSatisfy { $0.contains(appt.uuidString) })
    }

    func testCleanupSelectionForMedicationCancelRemovesDosesAndRefillOnly() {
        let (a, b, appt, med, otherMed) = (UUID(), UUID(), UUID(), UUID(), UUID())
        let pending = mixedPendingIdentifiers(taskA: a, taskB: b, appt: appt, med: med, otherMed: otherMed)
        // Production cancellation prefixes for one medication.
        let selected = NotificationService.staleIdentifiers(
            in: pending,
            matchingAnyPrefix: NotificationService.medicationCancellationPrefixes(medicationID: med))
        XCTAssertEqual(selected.count, 2, "The medication's dose reminder AND its refill reminder")
        XCTAssertFalse(selected.contains { $0.contains(otherMed.uuidString) },
                       "Another medication's reminders are never selected")
    }

    // MARK: Appointment status flow decisions (authorization fix, 2026-11-10)
    //
    // setAppointmentStatus always cancels BOTH reminder ids, then
    // reschedules only when shouldScheduleAppointmentReminder
    // passes. These tests pin that production decision chain for
    // the exact transitions the Complete / Cancel / Reopen actions
    // perform. (The view's call into the authorization wrapper
    // itself is not unit-testable without the notification-centre
    // seam, which is deliberately out of scope for this batch.)

    func testReopenedAppointmentSchedulesBothReminders() {
        // The eligibility gate compares against the REAL clock, so
        // the reference date must be current — a fixed past
        // timestamp would make every appointment "past" and the
        // gate would (correctly) refuse. The same `now` is passed
        // explicitly to the schedule function to keep its
        // assertions deterministic.
        let now = Date()
        let appt = VetAppointment(title: "Checkup", date: now.addingTimeInterval(3 * 3600))
        appt.isCompleted = true
        XCTAssertFalse(NotificationService.shouldScheduleAppointmentReminder(appt),
                       "A completed appointment stays silent")
        // Reopen: the transition setAppointmentStatus performs.
        appt.isCompleted = false
        appt.isCancelled = false
        XCTAssertTrue(NotificationService.shouldScheduleAppointmentReminder(appt),
                      "A reopened future appointment is schedulable again")
        let schedule = NotificationService.appointmentReminderSchedule(
            appointmentID: appt.id, date: appt.date, now: now)
        XCTAssertEqual(schedule.count, 2, "Reopening re-arms BOTH reminders")
        XCTAssertEqual(Set(schedule.map { $0.id }),
                       Set(NotificationService.appointmentReminderIDs(appointmentID: appt.id)),
                       "The scheduled identifiers are exactly the pair the status flow cancels and reschedules")
        XCTAssertEqual(schedule[0].fireDate, appt.date.addingTimeInterval(-3600),
                       "First reminder fires one hour before")
        XCTAssertEqual(schedule[1].fireDate, appt.date.addingTimeInterval(-1800),
                       "Second reminder fires thirty minutes before")
    }

    func testCancelledAppointmentSchedulesNothing() {
        let appt = VetAppointment(title: "Surgery", date: Date().addingTimeInterval(3 * 3600))
        appt.isCancelled = true
        XCTAssertFalse(NotificationService.shouldScheduleAppointmentReminder(appt),
                       "A cancelled appointment must not be rescheduled by a status change")
    }

    func testReopenedAppointmentWithOnlyThirtyMinuteReminderLeft() {
        // Current reference date (the eligibility gate reads the
        // real clock), passed explicitly to the schedule function.
        let now = Date()
        // 45 minutes out: the -60 slot has passed, -30 has not.
        let appt = VetAppointment(title: "Vaccine", date: now.addingTimeInterval(45 * 60))
        XCTAssertTrue(NotificationService.shouldScheduleAppointmentReminder(appt))
        let schedule = NotificationService.appointmentReminderSchedule(
            appointmentID: appt.id, date: appt.date, now: now)
        XCTAssertEqual(schedule.count, 1,
                       "Reopening never schedules a reminder time that has already passed")
        XCTAssertEqual(schedule.first?.id, "appt30-\(appt.id.uuidString)",
                       "The surviving reminder is the SECOND identifier (appt30-)")
        XCTAssertEqual(schedule.first?.id,
                       NotificationService.appointmentReminderIDs(appointmentID: appt.id)[1])
        // Fire date is the appointment minus 30 minutes — i.e. 15
        // minutes after the reference time. The exact equality
        // mirrors the production computation on the same inputs;
        // the accuracy assertion states the 15-minute relationship
        // directly.
        XCTAssertEqual(schedule.first?.fireDate, appt.date.addingTimeInterval(-1800))
        XCTAssertEqual(schedule.first?.fireDate.timeIntervalSince(now) ?? -1, 15 * 60, accuracy: 1.0)
    }

    func testCategoryCleanupPrefixesCannotSelectAnotherCategory() {
        // Cancellation safety across categories: no category's
        // namespaced cleanup prefix may be a prefix of another
        // category's, so disabling one category can never select
        // another category's requests (identifiers begin with
        // their category prefix by construction).
        let namespaced = ReminderCategory.allCases.map { category in
            (category, category.pendingPrefixes.map { NotificationService.pendingIdentifier(for: $0) })
        }
        for (categoryA, prefixesA) in namespaced {
            for (categoryB, prefixesB) in namespaced where categoryA != categoryB {
                for prefix in prefixesA {
                    for other in prefixesB {
                        XCTAssertFalse(other.hasPrefix(prefix),
                                       "\(categoryA) cleanup prefix \(prefix) must not match \(categoryB) prefix \(other)")
                    }
                }
            }
        }
    }
}
