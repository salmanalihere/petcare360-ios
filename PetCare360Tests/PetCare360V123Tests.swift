import XCTest
@testable import PetCare360

/// v1.2.3 audit tests: per-medication reminder preferences, launch and
/// foreground replenishment, global toggle rebuild eligibility, and
/// marketing-claim accuracy. WRITTEN, not executed — no Xcode here.
final class PetCare360V123Tests: XCTestCase {

    private func petWithMedication(reminderEnabled: Bool?, active: Bool = true) -> (Pet, Medication, [MedicationSchedule]) {
        let pet = Pet(name: "Buddy")
        let med = Medication(name: "Apoquel", dosage: "16mg")
        med.isActive = active
        med.pet = pet
        pet.medications.append(med)
        var schedules: [MedicationSchedule] = []
        if let reminderEnabled {
            let schedule = MedicationSchedule(medicationID: med.id)
            schedule.reminderEnabled = reminderEnabled
            schedules = [schedule]
        }
        return (pet, med, schedules)
    }

    // MARK: Individual medication reminder preference (brief §1, §6)

    func testMedicationReminderDisabledIsRespected() {
        let (pet, med, schedules) = petWithMedication(reminderEnabled: false)
        XCTAssertFalse(NotificationService.isReminderEnabled(medicationID: med.id, schedules: schedules))
        XCTAssertTrue(NotificationService.eligibleReminders(pets: [pet], schedules: schedules).isEmpty,
                      "A medication whose own reminder toggle is off must never be scheduled by replenishment")
    }

    func testMedicationReminderEnabledIsRespected() {
        let (pet, med, schedules) = petWithMedication(reminderEnabled: true)
        XCTAssertTrue(NotificationService.isReminderEnabled(medicationID: med.id, schedules: schedules))
        let eligible = NotificationService.eligibleReminders(pets: [pet], schedules: schedules)
        XCTAssertEqual(eligible.map { $0.medication.id }, [med.id])
        XCTAssertEqual(eligible.first?.petName, "Buddy")
    }

    func testMissingScheduleDefaultsToEnabled() {
        // Records created before preferences were wired have no schedule
        // row; the saved preference loads as enabled (the editor toggle
        // reads exactly this value).
        let (_, med, schedules) = petWithMedication(reminderEnabled: nil)
        XCTAssertTrue(schedules.isEmpty)
        XCTAssertTrue(NotificationService.isReminderEnabled(medicationID: med.id, schedules: schedules))
    }

    func testPreferenceIsPerMedicationNotGlobal() {
        let pet = Pet(name: "Buddy")
        let on = Medication(name: "On", dosage: "1")
        let off = Medication(name: "Off", dosage: "1")
        for med in [on, off] { med.pet = pet; pet.medications.append(med) }
        let onSchedule = MedicationSchedule(medicationID: on.id); onSchedule.reminderEnabled = true
        let offSchedule = MedicationSchedule(medicationID: off.id); offSchedule.reminderEnabled = false
        let eligible = NotificationService.eligibleReminders(pets: [pet], schedules: [onSchedule, offSchedule])
        XCTAssertEqual(eligible.map { $0.medication.id }, [on.id],
                       "Disabling one medication must not affect another's reminders")
    }

    func testInactiveMedicationIsNeverEligible() {
        let (pet, _, schedules) = petWithMedication(reminderEnabled: true, active: false)
        XCTAssertTrue(NotificationService.eligibleReminders(pets: [pet], schedules: schedules).isEmpty)
    }

    // MARK: Launch / foreground replenishment (brief §2, §6)

    func testDoseReminderIdentifiersAreDeterministic() {
        let id = UUID()
        let day = Calendar.current.startOfDay(for: Date())
        let first = NotificationService.doseReminderID(medicationID: id, day: day, minutes: 480)
        let second = NotificationService.doseReminderID(medicationID: id, day: day, minutes: 480)
        XCTAssertEqual(first, second,
                       "Identical inputs must produce identical identifiers — that is what prevents duplicates when launch and foreground passes both run")
        XCTAssertNotEqual(first, NotificationService.doseReminderID(medicationID: id, day: day, minutes: 481))
    }

    func testGlobalToggleRebuildUsesTheSameEligibility() {
        // The Settings toggle-on path and the launch/foreground path both
        // funnel through eligibleReminders; this pins the shared contract:
        // global on + one med off => only the other med is rebuilt.
        let (pet, med, schedules) = petWithMedication(reminderEnabled: false)
        let other = Medication(name: "Other", dosage: "1")
        other.pet = pet
        pet.medications.append(other)
        let eligible = NotificationService.eligibleReminders(pets: [pet], schedules: schedules)
        XCTAssertEqual(eligible.map { $0.medication.id }, [other.id])
        XCTAssertFalse(eligible.contains { $0.medication.id == med.id })
    }

    // MARK: Marketing accuracy (brief §4, §6)

    func testPremiumFeatureLabelDoesNotPromiseSharing() {
        let label = PremiumFeature.householdSharing.label
        XCTAssertFalse(label.lowercased().contains("sharing"),
                       "The paywall must not promise household sharing — it is not implemented")
        XCTAssertTrue(label.contains("coordination"))
    }

    // Updated 2026-11-07 (owner review): this test asserted the
    // v1.2.3-era disabled state. The owner has since completed the
    // Developer setup and approved CloudKit ON (2026-11-06), so the
    // test now pins the approved configuration instead — same
    // strength, current truth.
    func testCloudKitRemainsEnabledAsApproved() {
        XCTAssertTrue(AppConfig.cloudKitSyncEnabled,
                      "CloudKit stays enabled per the owner's approved configuration")
        XCTAssertEqual(AppConfig.iCloudContainerID, "iCloud.com.xenon-media.petcare360")
    }
}
