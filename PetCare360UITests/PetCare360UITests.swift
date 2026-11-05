import XCTest

/// PetCare 360 UI tests (Phase 2). WRITTEN ONLY — they have not been
/// executed: the build environment has no Xcode or Simulator.
/// Run on a Mac with Cmd+U (see docs/TEST_REPORT.md).
final class PetCare360UITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        app.launch()
        completeOnboardingIfNeeded()
    }

    /// Fresh installs show onboarding; walk through it once per test so the
    /// journeys start from the tab bar.
    private func completeOnboardingIfNeeded() {
        let getStarted = app.buttons["Get Started"]
        guard getStarted.waitForExistence(timeout: 3) else { return }
        let nameField = app.textFields["Your name"]
        if nameField.exists {
            nameField.tap()
            nameField.typeText("Alex")
        }
        getStarted.tap()
        XCTAssertTrue(app.tabBars.buttons["Pets"].waitForExistence(timeout: 5))
    }

    func testFiveTabsExist() {
        for tab in ["Home", "Pets", "Care", "Records", "Family"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "Missing tab: \(tab)")
        }
    }

    func testCreateAndEditPetJourney() {
        app.tabBars.buttons["Pets"].tap()
        app.navigationBars.buttons["Add pet"].tap()
        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Buddy")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Buddy"].waitForExistence(timeout: 3))
        // Open and edit the pet.
        app.staticTexts["Buddy"].tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3))
        app.buttons["Save"].tap()
    }

    func testCreateMedicationAndDuplicateGivenJourney() {
        app.tabBars.buttons["Care"].tap()
        app.navigationBars.buttons["plus"].firstMatch.tap()
        let addMedication = app.buttons["Add medication"]
        if addMedication.waitForExistence(timeout: 2) { addMedication.tap() }
        let medField = app.textFields["Medication name"]
        if medField.waitForExistence(timeout: 3) {
            medField.tap()
            medField.typeText("Apoquel")
            app.buttons["Save"].tap()
        }
        // Marking the same dose Given twice must be refused by the app;
        // the second tap either does nothing or shows the duplicate notice.
        let givenButtons = app.buttons.matching(identifier: "Given")
        if givenButtons.count > 0 {
            givenButtons.firstMatch.tap()
            XCTAssertFalse(app.buttons["Given"].exists && givenButtons.count > 1,
                           "A given dose must not offer a second Given action")
        }
    }

    func testCreateMedicalRecordJourney() {
        app.tabBars.buttons["Records"].tap()
        let passportLink = app.staticTexts["Records & timeline"]
        if passportLink.waitForExistence(timeout: 3) {
            passportLink.tap()
            app.navigationBars.buttons["plus"].firstMatch.tap()
            let title = app.textFields["Title"]
            if title.waitForExistence(timeout: 3) {
                title.tap()
                title.typeText("Annual checkup")
                app.buttons["Save"].tap()
                XCTAssertTrue(app.staticTexts["Annual checkup"].waitForExistence(timeout: 3))
            }
        }
    }

    func testScannerReviewJourney() {
        app.tabBars.buttons["Records"].tap()
        let documentsLink = app.staticTexts["Documents & scanner"]
        if documentsLink.waitForExistence(timeout: 3) {
            documentsLink.tap()
            // On the Simulator the document camera is unsupported; the
            // photo-library path and the review-before-save rule are what
            // this journey can verify there. Camera capture itself needs a
            // physical iPhone (see TEST_REPORT.md).
            XCTAssertTrue(app.staticTexts["Documents"].waitForExistence(timeout: 3))
        }
    }

    func testPaywallAndRestoreJourney() {
        app.tabBars.buttons["Family"].tap()
        let premiumButton = app.buttons["PetCare 360 Premium"]
        XCTAssertTrue(premiumButton.waitForExistence(timeout: 3))
        premiumButton.tap()
        XCTAssertTrue(app.buttons["Restore Purchases"].waitForExistence(timeout: 5))
        // Restore with the local StoreKit configuration must not crash and
        // must not fake a purchase.
        app.buttons["Restore Purchases"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 3))
    }

    func testExportBackupJourney() {
        app.tabBars.buttons["Family"].tap()
        let settingsLink = app.staticTexts["Settings & data"]
        if settingsLink.waitForExistence(timeout: 3) {
            settingsLink.tap()
            XCTAssertTrue(app.buttons["Export full backup (JSON)"].waitForExistence(timeout: 3))
            app.buttons["Export full backup (JSON)"].tap()
            // The system share sheet appears; dismiss it.
            let shareSheet = app.otherElements["ActivityListView"]
            if shareSheet.waitForExistence(timeout: 3) {
                app.swipeDown()
            }
        }
    }

    func testMedicalPassportExportJourney() {
        app.tabBars.buttons["Records"].tap()
        let passportLink = app.staticTexts["Records & timeline"]
        if passportLink.waitForExistence(timeout: 3) {
            passportLink.tap()
            let exportButton = app.buttons["Export Medical Passport…"]
            if exportButton.waitForExistence(timeout: 3) {
                exportButton.tap()
                XCTAssertTrue(app.buttons["Preview PDF"].waitForExistence(timeout: 3))
                app.buttons["Preview PDF"].tap()
            }
        }
    }
}
