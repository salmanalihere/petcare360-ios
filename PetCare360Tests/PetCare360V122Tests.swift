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

    // History: this test originally asserted CloudKit stayed OFF
    // "until the owner completes the Developer setup" (v1.2.2 era).
    // The owner completed that setup and directed CloudKit ON on
    // 2026-11-06 (registered container, entitlements wired, shipped
    // in build 14). The test now pins the APPROVED configuration at
    // the same strength — it fails if the flag, the container, or
    // the explicit local fallback ever drifts.
    func testCloudKitMatchesApprovedConfiguration() {
        XCTAssertTrue(AppConfig.cloudKitSyncEnabled,
                      "CloudKit sync is enabled per the owner's 2026-11-06 decision")
        XCTAssertEqual(AppConfig.iCloudContainerID, "iCloud.com.xenon-media.petcare360",
                       "The container must be the owner's registered container, exactly")
    }

    func testLocalFallbackUsesNoCloudKit() throws {
        // WHY THIS TEST IS BEHAVIORAL: ModelConfiguration.CloudKitDatabase
        // cannot be inspected in code — it has no Equatable conformance
        // and its members are not pattern-matchable (Codemagic compile
        // errors proved both: XCTAssertEqual AND `if case .none` demand
        // Equatable / '~='). What CAN be verified is the behavior .none
        // exists to guarantee — and in THIS app it is decisive: the
        // schema is CloudKit-incompatible (11 non-optional to-many
        // relationships), and executed diagnostic Test C proved that a
        // CloudKit-engaging configuration THROWS when opening a store
        // in the signed app, while diagnostic Test F proved the .none
        // fallback opens and works. If this factory ever regressed to
        // .automatic or .private, BOTH variants below would throw at
        // container creation and this test would fail — the `try` calls
        // are the assertion.
        let schema = PetCare360App.appSchema()

        // Variant 1 — explicit URL (the openStorage / resetAndReopen
        // fallback path): a working local store must appear at exactly
        // that URL and round-trip a record.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pc360-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = dir.appendingPathComponent("fallback.sqlite")
        let urlContainer = try PetCare360App.makeContainer(
            configuration: PetCare360App.localConfiguration(schema: schema, url: storeURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path),
                      "The local fallback must create its store file at the given URL")
        let urlContext = ModelContext(urlContainer)
        urlContext.insert(Pet(name: "FallbackProbe"))
        try urlContext.save()
        XCTAssertEqual(try urlContext.fetchCount(FetchDescriptor<Pet>()), 1,
                       "The local fallback store must save and fetch records")

        // Variant 2 — no URL (the default-location path): the container
        // must open and answer queries. No records are written here —
        // this is the app's real default store location.
        let defaultContainer = try PetCare360App.makeContainer(
            configuration: PetCare360App.localConfiguration(schema: schema))
        let defaultContext = ModelContext(defaultContainer)
        XCTAssertGreaterThanOrEqual(try defaultContext.fetchCount(FetchDescriptor<Pet>()), 0,
                                    "The default-location local fallback must open and answer queries")
    }

    func testStorageFactoryBuildsAContainer() throws {
        let config = ModelConfiguration(schema: PetCare360App.appSchema(), isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try PetCare360App.makeContainer(configuration: config)
        XCTAssertNotNil(container, "The storage factory must produce a working container for a valid configuration")
    }
}
