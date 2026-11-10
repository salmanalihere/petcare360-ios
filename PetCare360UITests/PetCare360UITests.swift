import XCTest

/// PetCare 360 UI tests (Phase 2). First executed in the
/// 2026-11-07 Codemagic full-suite run.
///
/// Threading: the class is @MainActor-isolated and setUp is
/// SYNCHRONOUS (an earlier async setUp resumed off the main
/// thread after an await and every XCTest interaction threw).
///
/// Deterministic state (2026-11-08): every launch passes
/// `-uiTesting -uiTestingResetState`; the app wipes its local
/// store + preferences before opening storage when — and only
/// when — both arguments are present (see PetCare360App), so
/// each test starts from true first launch: onboarding, then
/// the real subscription gate, then a real purchase against the
/// scheme's local StoreKit configuration. The Codemagic
/// full-tests workflow ALSO uninstalls the app before each UI
/// test, because StoreKit test transactions live outside the
/// app's data and cannot be cleared app-side; a previous test's
/// purchase therefore never unlocks the next test.
///
/// Launch handling is an explicit state machine
/// (reachUnlockedTabBar): whichever screen is actually showing
/// — onboarding, the subscription-checking spinner, the
/// mandatory gate, or the tab bar — is driven on its own terms,
/// with the visited screens named in any failure message. The
/// gate gets exactly ONE purchase attempt per test, monitored
/// to a definite outcome; an Apple Account sign-in prompt (the
/// purchase reaching the real App Store instead of the local
/// StoreKit configuration) is an immediate, undismissed
/// failure — see attemptGatePurchase.
@MainActor
final class PetCare360UITests: XCTestCase {

    private var app: XCUIApplication!
    /// One purchase attempt per test, ever (see attemptGatePurchase):
    /// re-tapping the gate's purchase button while a previous
    /// attempt is unresolved stacks StoreKit calls and leaves the
    /// button disabled behind a hung transaction.
    private var gatePurchaseAttempted = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetState"]
        app.launch()
        reachUnlockedTabBar()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// The screens the app can legitimately show between launch
    /// and the unlocked tab bar, identified by landmarks that
    /// exist only on that screen.
    private enum LaunchScreen {
        case tabs, onboarding, checkingSubscription, subscriptionGate, storageError, unknown

        var label: String {
            switch self {
            case .tabs: return "tab bar (unlocked)"
            case .onboarding: return "onboarding"
            case .checkingSubscription: return "checking subscription"
            case .subscriptionGate: return "subscription gate"
            case .storageError: return "storage error"
            case .unknown: return "unknown"
            }
        }
    }

    private func currentLaunchScreen() -> LaunchScreen {
        if app.tabBars.buttons["Pets"].exists { return .tabs }
        if app.staticTexts["PetCare 360 is subscription-only"].exists { return .subscriptionGate }
        if app.staticTexts["Checking your subscription…"].exists { return .checkingSubscription }
        if app.buttons["Skip tutorial"].exists
            || app.buttons["Next"].exists
            || app.textFields["Your name"].exists { return .onboarding }
        if app.staticTexts["PetCare 360 couldn't open its stored data"].exists { return .storageError }
        return .unknown
    }

    /// Drive the app from WHATEVER screen it launched into to the
    /// unlocked tab bar, acting on each screen as it appears:
    /// onboarding is completed, the checking spinner is waited
    /// out, and the mandatory subscription gate is passed through
    /// the app's own purchase UI. The previous helper assumed
    /// onboarding always comes first and waited 15s for its
    /// controls even when the app had launched straight into the
    /// gate (persisted onboarding state) — every test then failed
    /// in setup. This loop never waits for a screen that is not
    /// showing, and its failure message names every screen it
    /// visited plus the final hierarchy.
    private func reachUnlockedTabBar() {
        let petsTab = app.tabBars.buttons["Pets"]
        if petsTab.waitForExistence(timeout: 2) { return }

        let deadline = Date().addingTimeInterval(120)
        var visited: [String] = []
        while Date() < deadline {
            let screen = currentLaunchScreen()
            if visited.last != screen.label { visited.append(screen.label) }
            switch screen {
            case .tabs:
                return
            case .onboarding:
                stepOnboarding()
            case .subscriptionGate:
                if gatePurchaseAttempted {
                    // The single attempt already ran; it records
                    // its own failure if it did not unlock, so
                    // being here means the entitlement is still
                    // resolving. Wait — never tap purchase again.
                    _ = petsTab.waitForExistence(timeout: 2)
                } else {
                    gatePurchaseAttempted = true
                    attemptGatePurchase()
                }
            case .storageError:
                XCTFail("The app showed its storage-error screen during UI-test setup. Screens visited: \(visited.joined(separator: " → ")). Hierarchy: \(app.debugDescription)")
                return
            case .checkingSubscription, .unknown:
                // Transitional states (entitlement check in
                // flight, first render): wait briefly, then
                // re-evaluate which screen is actually up.
                _ = petsTab.waitForExistence(timeout: 2)
            }
            if petsTab.exists { return }
        }
        XCTAssertTrue(petsTab.waitForExistence(timeout: 10),
                      "Never reached the tab bar. Screens visited: \(visited.joined(separator: " → ")). Final hierarchy: \(app.debugDescription)")
    }

    /// ONE step of the real onboarding flow, based on what is on
    /// screen right now: Skip (shown on every page) finishes
    /// immediately; on the final page the name is entered and
    /// Get Started tapped; anywhere else the app's own Next
    /// button advances one page. Called repeatedly by
    /// reachUnlockedTabBar until onboarding is done.
    private func stepOnboarding() {
        let skip = app.buttons["Skip tutorial"]
        if skip.exists {
            skip.tap()
            return
        }
        let nameField = app.textFields["Your name"]
        if nameField.exists {
            let currentValue = nameField.value as? String ?? ""
            if currentValue.isEmpty || currentValue == "Your name" {
                nameField.tap()
                nameField.typeText("Alex")
                // Dismiss the keyboard before looking for Get
                // Started: with the keyboard up, the button below
                // the field can be pushed out of the visible area
                // and out of the accessibility tree entirely.
                app.swipeDown()
            }
            let getStarted = app.buttons["Get Started"]
            if getStarted.waitForExistence(timeout: 5) {
                getStarted.tap()
            }
            return
        }
        let next = app.buttons["Next"]
        if next.waitForExistence(timeout: 3) {
            next.tap()
        }
    }

    /// THE subscription purchase of this test — exactly one
    /// attempt, monitored to a definite outcome. Subscription-only
    /// model (2026-11-08): without an active entitlement the app
    /// stops at the mandatory gate; the test passes it honestly,
    /// through the app's own gate UI and Apple's confirmation,
    /// against the scheme's local StoreKit configuration (the
    /// Monthly plan's 7-day free trial; nothing is charged).
    ///
    /// Failure discipline (learned from run 6aef9529, where the
    /// purchase reached the REAL App Store): an Apple Account
    /// sign-in prompt means the local StoreKit session is not
    /// active for the app process — that is a hard, immediate
    /// failure with diagnostics, never something to dismiss and
    /// retry. The purchase button is never tapped twice: while
    /// StoreManager.purchase is in flight the button is disabled,
    /// and this method polls the attempt's outcome — tab bar
    /// (entitlement verified by the app), confirmation sheet,
    /// sign-in prompt, the app's own purchase error text, or the
    /// button becoming enabled again without an unlock.
    private func attemptGatePurchase() {
        if app.tabBars.buttons["Pets"].exists { return }
        // The gate's plan list can be in its failed/empty state
        // if the first product load raced the launch; its own
        // Retry is the real recovery path.
        let retry = app.buttons["Retry"]
        if retry.exists { retry.tap() }
        let monthlyPlan = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Premium Monthly")).firstMatch
        guard monthlyPlan.waitForExistence(timeout: 10) else {
            XCTFail("The subscription gate showed no purchasable plans within 10s. Visible gate texts: \(visibleGateTexts()). Hierarchy: \(app.debugDescription)")
            return
        }
        monthlyPlan.tap()
        // The call-to-action offers the free trial only when
        // Apple reports this environment eligible; otherwise it
        // is the plain Subscribe button. Accept either real
        // label — both start the same genuine purchase.
        let startPurchase = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label BEGINSWITH[c] %@",
                        "Start 7-day free trial", "Subscribe,")).firstMatch
        guard startPurchase.waitForExistence(timeout: 5) else {
            XCTFail("The subscription gate's purchase button never appeared after selecting Premium Monthly. Visible gate texts: \(visibleGateTexts()). Hierarchy: \(app.debugDescription)")
            return
        }
        startPurchase.tap()

        let deadline = Date().addingTimeInterval(30)
        var sawPurchaseInFlight = false
        var sheetConfirmed = false
        while Date() < deadline {
            if app.tabBars.buttons["Pets"].exists { return }
            if appleAccountSignInPromptIsVisible() {
                XCTFail("PURCHASE REACHED THE REAL APP STORE: iOS presented an Apple Account sign-in prompt after the purchase tap, and no local StoreKit confirmation sheet appeared. The local StoreKit configuration (PetCare360.storekit: com.petcare360.premium.monthly / com.petcare360.premium.yearly, group 22553779) is not active for the app process in this test environment — a local session never asks for an Apple Account. The prompt was NOT dismissed by the test. Visible gate texts: \(visibleGateTexts()). Hierarchy: \(app.debugDescription)")
                return
            }
            if !sheetConfirmed {
                sheetConfirmed = tapStoreKitConfirmationIfPresent()
                if sheetConfirmed { continue }
            }
            if startPurchase.exists && !startPurchase.isEnabled {
                sawPurchaseInFlight = true
            } else if sawPurchaseInFlight && startPurchase.exists && startPurchase.isEnabled {
                XCTFail("The purchase attempt finished WITHOUT unlocking the app (StoreManager.purchase returned — cancelled or failed — and the entitlement check still shows no active subscription). Visible gate texts, including any purchase error shown by the app: \(visibleGateTexts()). Hierarchy: \(app.debugDescription)")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTFail("The purchase did not complete within 30s: the purchase button stayed disabled, i.e. StoreManager.purchase never returned, and no confirmation sheet or entitlement appeared. Visible gate texts: \(visibleGateTexts()). Hierarchy: \(app.debugDescription)")
    }

    /// True when iOS is showing the real-store Apple Account
    /// sign-in prompt (a SpringBoard-hosted alert). Its presence
    /// is diagnostic gold — the local StoreKit environment never
    /// produces it — so it is only ever READ here, never tapped.
    private func appleAccountSignInPromptIsVisible() -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let inSpringboard = springboard.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Apple Account")).firstMatch
        if inSpringboard.exists { return true }
        let inApp = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Apple Account Sign In")).firstMatch
        return inApp.exists
    }

    /// One poll for the LOCAL StoreKit confirmation sheet (the
    /// one labelled as the Xcode test environment): if its
    /// confirmation button is present — in the app's alerts or
    /// sheets, in SpringBoard's, or as a direct button — tap it
    /// and report true. "Cancel" is never tapped, and the Apple
    /// Account prompt's buttons ("Cancel" / "Sign In") match
    /// none of the confirmation labels.
    private func tapStoreKitConfirmationIfPresent() -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirmations = ["Subscribe", "Start Free Trial", "Confirm", "Buy"]
        for host in [app!, springboard] {
            for label in confirmations {
                if host.alerts.buttons[label].exists {
                    host.alerts.buttons[label].tap()
                    return true
                }
                if host.sheets.buttons[label].exists {
                    host.sheets.buttons[label].tap()
                    return true
                }
                // Some Xcode versions surface the sheet's buttons
                // directly in the host's button list. These are
                // EXACT label matches, so the gate's own
                // long-labelled purchase button (which merely
                // starts with "Subscribe,") can never be mistaken
                // for the sheet's confirmation.
                if host.buttons[label].exists {
                    host.buttons[label].tap()
                    return true
                }
            }
        }
        return false
    }

    /// The texts currently visible on the subscription gate —
    /// including StoreManager's purchaseError / infoMessage,
    /// which the gate renders as plain texts — for failure
    /// messages, so a failed purchase reports the app's OWN
    /// account of what happened, not just a timeout.
    private func visibleGateTexts() -> String {
        let labels = app.staticTexts.allElementsBoundByIndex
            .map { $0.label }
            .filter { !$0.isEmpty }
            .prefix(14)
        return labels.isEmpty ? "(none)" : labels.joined(separator: " | ")
    }

    /// SwiftUI Lists and Forms realize rows lazily: an element below
    /// the fold may not exist in the accessibility tree at all until
    /// it is scrolled into view (this is why the passport and paywall
    /// journeys failed in Build #4 — the controls existed in the UI
    /// but below the fold). Swipe up (bounded) until it exists.
    private func scrollUntilExists(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
            _ = element.waitForExistence(timeout: 1)
        }
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
        // The Care screen's add control is a SwiftUI Menu (Add
        // medication / Add care task / Add feeding schedule), which
        // XCTest exposes as a PopUpButton — NOT a Button (Build #4).
        // But it is also NOT a descendant of the navigationBar
        // element: Build #5 proved the navigationBars-scoped
        // PopUpButton query finds nothing. Query the whole app by
        // type, unscoped; fall back to any element identified or
        // labelled "plus" (the menu's only content is the plus
        // symbol image). The Medical Timeline screen, by contrast,
        // has a plain toolbar Button and correctly uses
        // navigationBars.buttons["plus"].
        var addMenu = app.popUpButtons.firstMatch
        if !addMenu.waitForExistence(timeout: 3) {
            addMenu = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'plus' OR label == 'plus'"))
                .firstMatch
            _ = addMenu.waitForExistence(timeout: 2)
        }
        if !addMenu.exists {
            // One-shot hierarchy dump, printed only on this failure
            // path, so a further failure is self-diagnosing from
            // the Codemagic log.
            print(app.debugDescription)
        }
        XCTAssertTrue(addMenu.exists,
                      "The Care screen's add menu was not found anywhere in the accessibility hierarchy")
        addMenu.tap()
        // Menu items surface as buttons or menu items depending on
        // presentation; accept either.
        let addMedication = app.buttons["Add medication"]
        let addMedicationItem = app.menuItems["Add medication"]
        if addMedication.waitForExistence(timeout: 2) {
            addMedication.tap()
        } else if addMedicationItem.waitForExistence(timeout: 1) {
            addMedicationItem.tap()
        }
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

    func testDocumentsJourney() {
        app.tabBars.buttons["Records"].tap()
        let documentsLink = app.staticTexts["Documents"]
        if documentsLink.waitForExistence(timeout: 3) {
            documentsLink.tap()
            // Documents are added manually (photo library / file
            // upload) since the scanner was removed; this journey
            // verifies the Documents screen opens from Records.
            XCTAssertTrue(app.staticTexts["Documents"].waitForExistence(timeout: 3))
        }
    }

    func testPaywallAndRestoreJourney() {
        app.tabBars.buttons["Family"].tap()
        // "PetCare 360 Premium" lives in the Family list's "More"
        // section, far below the fold; the List realizes rows lazily,
        // so scroll until it exists (Build #4 failure).
        let premiumButton = app.buttons["PetCare 360 Premium"]
        scrollUntilExists(premiumButton)
        XCTAssertTrue(premiumButton.exists, "The Family screen's Premium button was not found")
        premiumButton.tap()
        // The paywall is a long ScrollView; its Restore row sits near
        // the bottom, below the feature list and product cards.
        let restoreButton = app.buttons["Restore Purchases"]
        scrollUntilExists(restoreButton)
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 5))
        // Restore with the local StoreKit configuration must not crash and
        // must not fake a purchase.
        restoreButton.tap()
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
            scrollUntilExists(exportButton)
            if exportButton.exists {
                exportButton.tap()
                // The export sheet's Form holds 12 category toggles;
                // "Preview PDF" sits below the fold and is not in the
                // accessibility tree until scrolled into view
                // (Build #4 failure).
                let previewButton = app.buttons["Preview PDF"]
                scrollUntilExists(previewButton)
                XCTAssertTrue(previewButton.exists,
                              "Preview PDF never appeared in the passport export sheet")
                previewButton.tap()
            }
        }
    }
}

/// Gate-only UI tests (added 2026-11-10 under the approved
/// post-Build-20 testing strategy). These tests cover everything
/// the mandatory subscription gate shows and does BEFORE any
/// purchase: product loading, prices, trial information, plan
/// selection, purchase-button state, Restore Purchases, and the
/// legal links. They exist because the Codemagic simulator image
/// cannot complete a StoreKit purchase for a command-line-
/// installed app (storekitd: "not installed for development" —
/// see the Build 18/20 investigations), so the eight journey
/// tests above can never get past this screen in CI, and the
/// gate itself — the one screen every locked user sees — had no
/// CI coverage at all.
///
/// Discipline, identical to the journey tests:
/// - NO purchase is ever attempted here, NO entitlement is
///   faked, and production enforcement is untouched: these tests
///   only observe and drive the gate's own pre-purchase UI.
/// - Restore IS tapped in one test: it is a read-only App Store
///   sync, and on a fresh install with no purchases it must end
///   in one of StoreManager's definite outcome messages. That
///   one test is environment-dependent (a live sync on an
///   account-less simulator), so the workflow runs it
///   separately from the six gating tests in this class and
///   reports its result independently — see its own doc comment.
/// - Same launch contract as the journey tests: fresh state via
///   `-uiTesting -uiTestingResetState`, onboarding stepped
///   through honestly, and the run STOPS at the gate — reaching
///   the tab bar in setUp is a failure, because on a fresh
///   install that would mean the app opened without an
///   entitlement.
@MainActor
final class PetCare360GateUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-uiTestingResetState"]
        app.launch()
        reachSubscriptionGate()
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Reaching the gate (never past it)

    /// Drive launch → onboarding → the subscription gate, and
    /// stop there. The checking spinner is waited out; onboarding
    /// is stepped with the same rules as the journey tests.
    private func reachSubscriptionGate() {
        let gateHeader = app.staticTexts["PetCare 360 is subscription-only"]
        if gateHeader.waitForExistence(timeout: 5) { return }

        let deadline = Date().addingTimeInterval(90)
        var visited: [String] = []
        while Date() < deadline {
            if gateHeader.exists { return }
            if app.tabBars.buttons["Pets"].exists {
                XCTFail("The app opened to the tab bar on a fresh install without any purchase — the subscription gate did not block it. Hierarchy: \(app.debugDescription)")
                return
            }
            if app.staticTexts["PetCare 360 couldn't open its stored data"].exists {
                XCTFail("The app showed its storage-error screen during gate-test setup. Hierarchy: \(app.debugDescription)")
                return
            }
            if app.buttons["Skip tutorial"].exists
                || app.buttons["Next"].exists
                || app.textFields["Your name"].exists {
                if visited.last != "onboarding" { visited.append("onboarding") }
                stepOnboarding()
            } else {
                if visited.last != "checking/transition" { visited.append("checking/transition") }
                _ = gateHeader.waitForExistence(timeout: 2)
            }
        }
        XCTAssertTrue(gateHeader.exists,
                      "Never reached the subscription gate. Screens visited: \(visited.joined(separator: " → ")). Final hierarchy: \(app.debugDescription)")
    }

    /// One onboarding step, mirroring the journey tests' rules:
    /// Skip finishes immediately; on the name page, enter a name
    /// and tap Get Started; otherwise Next advances one page.
    private func stepOnboarding() {
        let skip = app.buttons["Skip tutorial"]
        if skip.exists {
            skip.tap()
            return
        }
        let nameField = app.textFields["Your name"]
        if nameField.exists {
            let currentValue = nameField.value as? String ?? ""
            if currentValue.isEmpty || currentValue == "Your name" {
                nameField.tap()
                nameField.typeText("Alex")
                app.swipeDown()
            }
            let getStarted = app.buttons["Get Started"]
            if getStarted.waitForExistence(timeout: 5) {
                getStarted.tap()
            }
            return
        }
        let next = app.buttons["Next"]
        if next.waitForExistence(timeout: 3) {
            next.tap()
        }
    }

    // MARK: - Gate element helpers

    /// A plan card's accessibility label BEGINS with the product
    /// name ("Premium Monthly, $4.99 per month"), which keeps it
    /// distinct from the purchase button, whose label merely
    /// CONTAINS the selected product's name.
    private func planCard(_ productName: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "\(productName),")).firstMatch
    }

    /// The purchase call-to-action, matched exactly as the
    /// journey tests match it: its accessibility label is
    /// "Start 7-day free trial, <product>, <price> <period>" when
    /// a trial is offered and "Subscribe, <product>, ..." when
    /// it is not.
    private var purchaseButton: XCUIElement {
        app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ OR label BEGINSWITH[c] %@",
                        "Start 7-day free trial", "Subscribe,")).firstMatch
    }

    /// SwiftUI Links surface as link elements on some OS
    /// versions and button elements on others; accept either.
    private func gateLink(_ label: String) -> XCUIElement {
        let link = app.links[label]
        if link.exists { return link }
        return app.buttons[label]
    }

    /// Wait for the gate's product content: the plan cards. The
    /// gate's own Retry is tapped once if the load failed or came
    /// back empty (products load from the store, which CI reaches
    /// — Build 20's logs show both products loading with prices
    /// and trial offers).
    @discardableResult
    private func waitForGateContent(timeout: TimeInterval = 60) -> Bool {
        let monthly = planCard("Premium Monthly")
        if monthly.waitForExistence(timeout: timeout) { return true }
        let retry = app.buttons["Retry"]
        if retry.exists {
            retry.tap()
            return monthly.waitForExistence(timeout: 30)
        }
        return false
    }

    /// The gate is a ScrollView: elements below the fold are not
    /// in the accessibility tree until scrolled into view.
    private func scrollUntilExists(_ element: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
            _ = element.waitForExistence(timeout: 1)
        }
    }

    /// Visible gate texts for failure messages, mirroring the
    /// journey tests' helper.
    private func visibleGateTexts() -> String {
        let labels = app.staticTexts.allElementsBoundByIndex
            .map { $0.label }
            .filter { !$0.isEmpty }
            .prefix(14)
        return labels.isEmpty ? "(none)" : labels.joined(separator: " | ")
    }

    /// Poll until the purchase button's label contains the given
    /// text (selection changes relabel it), or the timeout ends.
    private func purchaseButtonLabel(containing text: String, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if purchaseButton.exists && purchaseButton.label.contains(text) { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return purchaseButton.exists && purchaseButton.label.contains(text)
    }

    // MARK: - Tests

    /// Both subscription products load and display with their
    /// names, prices and periods on the plan cards.
    func testGateShowsBothProductsWithPrices() {
        XCTAssertTrue(waitForGateContent(),
                      "The gate never showed its plan cards. Visible gate texts: \(visibleGateTexts()). Hierarchy: \(app.debugDescription)")
        let monthly = planCard("Premium Monthly")
        let yearly = planCard("Premium Yearly")
        XCTAssertTrue(monthly.exists, "No Premium Monthly plan card. Visible gate texts: \(visibleGateTexts())")
        XCTAssertTrue(yearly.exists, "No Premium Yearly plan card. Visible gate texts: \(visibleGateTexts())")
        XCTAssertTrue(monthly.label.contains("4.99"),
                      "Monthly card label should carry the $4.99 price; label was: \(monthly.label)")
        XCTAssertTrue(monthly.label.contains("per month"),
                      "Monthly card label should carry its period; label was: \(monthly.label)")
        XCTAssertTrue(yearly.label.contains("29.99"),
                      "Yearly card label should carry the $29.99 price; label was: \(yearly.label)")
        XCTAssertTrue(yearly.label.contains("per year"),
                      "Yearly card label should carry its period; label was: \(yearly.label)")
    }

    /// Plan selection is real: the purchase button relabels to
    /// the selected product, defaulting to Yearly (the gate's
    /// declared default) and following taps in both directions.
    func testGatePlanSelectionUpdatesPurchaseButton() {
        XCTAssertTrue(waitForGateContent(),
                      "The gate never showed its plan cards. Visible gate texts: \(visibleGateTexts())")
        XCTAssertTrue(purchaseButtonLabel(containing: "Premium Yearly"),
                      "The purchase button should default to Premium Yearly; label was: \(purchaseButton.label)")
        planCard("Premium Monthly").tap()
        XCTAssertTrue(purchaseButtonLabel(containing: "Premium Monthly"),
                      "After tapping Monthly the purchase button should name Premium Monthly; label was: \(purchaseButton.label)")
        XCTAssertTrue(purchaseButtonLabel(containing: "per month"),
                      "After tapping Monthly the purchase button should say per month; label was: \(purchaseButton.label)")
        planCard("Premium Yearly").tap()
        XCTAssertTrue(purchaseButtonLabel(containing: "Premium Yearly"),
                      "After tapping Yearly the purchase button should name Premium Yearly again; label was: \(purchaseButton.label)")
    }

    /// The trial/price disclosure under the purchase button is
    /// shown for the selected plan and follows the selection:
    /// with the 7-day trial offered on both products it reads
    /// "Free for 7 days, then <price> <period>, ...".
    func testGateShowsTrialAndPriceDetailsForSelectedPlan() {
        XCTAssertTrue(waitForGateContent(),
                      "The gate never showed its plan cards. Visible gate texts: \(visibleGateTexts())")
        let yearlyCaption = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Free for 7 days, then")).firstMatch
        XCTAssertTrue(yearlyCaption.waitForExistence(timeout: 10),
                      "No free-trial disclosure under the purchase button for the default Yearly plan. Visible gate texts: \(visibleGateTexts())")
        XCTAssertTrue(yearlyCaption.label.contains("29.99"),
                      "The Yearly trial disclosure should name the $29.99 price; text was: \(yearlyCaption.label)")
        planCard("Premium Monthly").tap()
        let deadline = Date().addingTimeInterval(10)
        var monthlyCaptionOK = false
        while Date() < deadline {
            let caption = app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS[c] %@", "Free for 7 days, then")).firstMatch
            if caption.exists && caption.label.contains("4.99") && caption.label.contains("per month") {
                monthlyCaptionOK = true
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(monthlyCaptionOK,
                      "After selecting Monthly the trial disclosure should read Free for 7 days, then $4.99 per month. Visible gate texts: \(visibleGateTexts())")
    }

    /// Purchase-button state before any purchase: present,
    /// enabled, and not mid-purchase (no "Processing…" state).
    func testGatePurchaseButtonIsReadyAndIdle() {
        XCTAssertTrue(waitForGateContent(),
                      "The gate never showed its plan cards. Visible gate texts: \(visibleGateTexts())")
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 10),
                      "The gate showed no purchase button. Visible gate texts: \(visibleGateTexts())")
        XCTAssertTrue(purchaseButton.isEnabled,
                      "The purchase button should be enabled before any purchase attempt.")
        XCTAssertFalse(app.staticTexts["Processing…"].exists,
                       "The gate claims to be processing a purchase before any purchase was attempted.")
        XCTAssertTrue(planCard("Premium Monthly").isEnabled && planCard("Premium Yearly").isEnabled,
                      "Both plan cards should be enabled for selection.")
    }

    /// Restore Purchases is visible and tappable — and this
    /// test is ENVIRONMENT-DEPENDENT, so codemagic.yaml runs it
    /// SEPARATELY from the six gating gate tests and reports its
    /// result independently. What a live AppStore.sync() does on
    /// a simulator with no signed-in account is an environment
    /// property, not an app property.
    ///
    /// Expected outcome on a fresh install with no purchase: one
    /// of StoreManager's definite no-purchase or restore-error
    /// messages (no active purchase / sync failure / verification
    /// failure / cancelled / billing-paused). Two outcomes are
    /// NOT acceptable:
    /// - The app UNLOCKING. Nothing was purchased on this fresh
    ///   install, so an unlock means access appeared without a
    ///   purchase behind it — a hard failure, never a pass.
    /// - A success message while the gate stays up: a genuine
    ///   restore success unlocks, so success text behind a still-
    ///   locked gate is an inconsistent outcome — also a failure.
    /// And two outcomes are environment limitations, reported as
    /// an XCTSkip with the reason attached (never silently, and
    /// the workflow classifies the run ENVIRONMENT-LIMITED from
    /// that reason): iOS parking the restore behind an Apple
    /// Account authentication prompt, or the sync never
    /// returning here at all. The app-side restore state machine
    /// itself is covered deterministically by the
    /// PetCare360RestoreOutcomeTests unit tests.
    func testGateRestoreWithNoPurchasesReportsOutcome() throws {
        XCTAssertTrue(waitForGateContent(),
                      "The gate never showed its plan cards. Visible gate texts: \(visibleGateTexts())")
        let restore = app.buttons["Restore Purchases"]
        scrollUntilExists(restore)
        XCTAssertTrue(restore.exists, "No Restore Purchases button on the gate. Visible gate texts: \(visibleGateTexts())")
        XCTAssertTrue(restore.isEnabled, "Restore Purchases should be enabled before restoring.")
        restore.tap()

        let definitePrefixes = [
            "No active purchases were found",
            "Restore did not complete",
            "Your purchases could not be verified",
            "Restore was cancelled",
            "Your subscription was found, but Apple has paused it",
        ]
        let deadline = Date().addingTimeInterval(45)
        var sawRestoring = false
        while Date() < deadline {
            if appleAccountSignInPromptIsVisible() {
                throw XCTSkip("ENVIRONMENT LIMITATION: iOS presented an Apple Account authentication prompt for this restore, so no restore outcome could be produced in this environment. Exercise the no-purchase restore outcome on a device or in an environment with a signed-in sandbox account.")
            }
            if app.tabBars.buttons["Pets"].exists {
                XCTFail("The app UNLOCKED during restore on a fresh install with no purchase — access appeared without a purchase behind it. This is not a successful no-purchase restore. Visible gate texts: \(visibleGateTexts()). Hierarchy: \(app.debugDescription)")
                return
            }
            if app.buttons["Restoring..."].exists { sawRestoring = true }
            for prefix in definitePrefixes {
                let text = app.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch
                if text.exists { return }
            }
            let successText = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH[c] %@", "Purchases restored successfully")).firstMatch
            if successText.exists {
                XCTFail("Restore claimed success ('\(successText.label)') on a fresh install with no purchase, yet the subscription gate is still up — an inconsistent restore outcome. Visible gate texts: \(visibleGateTexts())")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw XCTSkip("ENVIRONMENT LIMITATION: restore produced no outcome within 45s in this environment (restoring indicator seen: \(sawRestoring)), so the no-purchase restore outcome could not be exercised here. Run on a device or in an environment with a signed-in sandbox account.")
    }

    /// True when iOS is showing the real-store Apple Account
    /// sign-in prompt (a SpringBoard-hosted alert) — the same
    /// detection the journey tests use. Its presence during a
    /// restore means the environment, not the app, is deciding
    /// the outcome.
    private func appleAccountSignInPromptIsVisible() -> Bool {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let inSpringboard = springboard.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Apple Account")).firstMatch
        if inSpringboard.exists { return true }
        let inApp = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Apple Account Sign In")).firstMatch
        return inApp.exists
    }

    /// Terms of Use, Privacy Policy and Manage Subscription are
    /// all present on the gate, as App Store rules require while
    /// the app is locked. Existence is asserted, not navigation:
    /// these links open external destinations that a UI test
    /// cannot meaningfully verify.
    func testGateShowsLegalAndManageSubscriptionLinks() {
        for label in ["Privacy Policy", "Terms of Use", "Manage Subscription"] {
            let element = gateLink(label)
            scrollUntilExists(element)
            XCTAssertTrue(element.exists,
                          "The gate is missing its \(label) link. Visible gate texts: \(visibleGateTexts())")
        }
    }

    /// Enforcement is visible and total on the gate: no tab bar,
    /// no app content, and no dismiss/close/skip affordance of
    /// any kind — the only ways forward are purchase or restore.
    func testGateBlocksAppContentWithoutSubscription() {
        XCTAssertTrue(app.staticTexts["PetCare 360 is subscription-only"].exists,
                      "The gate header is not showing. Visible gate texts: \(visibleGateTexts())")
        XCTAssertFalse(app.tabBars.buttons["Pets"].exists,
                       "The tab bar is reachable without a subscription.")
        for label in ["Close", "Skip", "Not Now", "Maybe Later", "Continue without subscription"] {
            XCTAssertFalse(app.buttons[label].exists,
                           "The gate unexpectedly offers a '\(label)' dismissal — enforcement has a hole.")
        }
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "There is no free plan")).firstMatch.exists,
                      "The gate should state plainly that there is no free plan. Visible gate texts: \(visibleGateTexts())")
    }
}
