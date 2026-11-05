import XCTest
import SwiftData
@testable import PetCare360

/// v1.2.2 audit-correction tests. WRITTEN, not executed — no Xcode in the
/// build environment. See docs/TEST_REPORT.md.
final class PetCare360V122Tests: XCTestCase {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))!
    }

    // MARK: Reminder replenishment windows (brief §2, §7)

    func testWeeklyMedicationHasSlotsInBothRollingWindows() {
        let med = Medication(name: "Weekly", dosage: "1")
        med.frequencyRaw = MedicationFrequency.weekly.rawValue
        med.startDate = day(-30)
        med.doseMinutes = [480]
        let weekday = Calendar.current.component(.weekday, from: day(0))
        med.weekdays = [weekday]
        // Window 1: days 0...6 contain exactly one dose day (today's weekday).
        let window1 = (0..<7).flatMap { MedicationService.slots(for: med, on: day($0)) }
        XCTAssertEqual(window1.count, 1)
        // Window 2: days 7...13 — after the next foreground replenishment,
        // the same weekday produces the next dose. This is what keeps
        // reminders alive beyond the first seven days.
        let window2 = (7..<14).flatMap { MedicationService.slots(for: med, on: day($0)) }
        XCTAssertEqual(window2.count, 1)
    }

    func testReplenishmentWindowStopsAtEndDateInSecondWeek() {
        let med = Medication(name: "Course", dosage: "5mg")
        med.startDate = day(-3)
        med.endDate = day(9)   // ends inside the second window
        med.doseMinutes = [480]
        let firstWindow = (0..<7).flatMap { MedicationService.slots(for: med, on: day($0)) }
        XCTAssertEqual(firstWindow.count, 7, "Daily doses for the whole first window")
        let secondWindow = (7..<14).flatMap { MedicationService.slots(for: med, on: day($0)) }
        XCTAssertEqual(secondWindow.count, 3, "Only days 7, 8 and the end date (day 9) remain")
    }

    func testFutureStartDateAppearsOnlyInLaterWindow() {
        let med = Medication(name: "Future", dosage: "5mg")
        med.startDate = day(10)
        med.doseMinutes = [480]
        XCTAssertTrue((0..<7).flatMap { MedicationService.slots(for: med, on: day($0)) }.isEmpty)
        let later = (7..<14).flatMap { MedicationService.slots(for: med, on: day($0)) }
        XCTAssertEqual(later.count, 4, "Days 10–13 of the second window")
    }

    // MARK: Refill cancellation (brief §3)

    func testCancellationPrefixesCoverDoseAndRefillIdentifiers() {
        let id = UUID()
        let prefixes = NotificationService.medicationCancellationPrefixes(medicationID: id)
        XCTAssertTrue(prefixes.contains("pc360-med-\(id.uuidString)-"), "Dose reminders covered")
        XCTAssertTrue(prefixes.contains("pc360-refill-\(id.uuidString)"),
                      "Refill reminders use a different identifier shape and MUST be covered too")
        XCTAssertEqual(NotificationService.refillReminderID(medicationID: id), "refill-\(id.uuidString)")
        // Every prefix matches the full pending identifier it targets.
        let pendingDose = "pc360-med-\(id.uuidString)-20251106-480"
        let pendingRefill = "pc360-refill-\(id.uuidString)"
        XCTAssertTrue(prefixes.contains { pendingDose.hasPrefix($0) })
        XCTAssertTrue(prefixes.contains { pendingRefill.hasPrefix($0) })
    }

    // MARK: Legal URL guard (brief §1, §7)

    func testIncorrectLegalHostIsAbsent() {
        for url in [AppConfig.privacyPolicyURL, AppConfig.termsOfUseURL, AppConfig.websiteURL] {
            XCTAssertEqual(url.host, "salmanalihere.github.io")
            XCTAssertFalse(url.absoluteString.contains("salmanali.github.io"),
                           "The incorrect hostname must not survive anywhere in the config")
        }
    }

    // MARK: CloudKit + storage handling (brief §4, §5)

    func testCloudKitIsNotAutoActivated() {
        XCTAssertFalse(AppConfig.cloudKitSyncEnabled,
                       "CloudKit must stay off until the owner completes the Developer setup")
    }

    func testStorageFactoryBuildsAContainer() throws {
        let config = ModelConfiguration(schema: PetCare360App.appSchema(), isStoredInMemoryOnly: true)
        let container = try PetCare360App.makeContainer(configuration: config)
        XCTAssertNotNil(container, "The storage factory must produce a working container for a valid configuration")
    }
}
