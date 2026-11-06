import XCTest
@testable import PetCare360

/// Premium flow tests (2026-11-06 brief): paywall state derivation,
/// honest savings maths over real prices, prompt copy, and the
/// entitlement source of truth. StoreKit sandbox purchases themselves
/// require a signed build (Xcode/Codemagic) and are NOT exercised here.
@MainActor
final class PetCare360PremiumTests: XCTestCase {

    // MARK: Paywall display state — the "Trying Again" dead end

    func testPaywallStateLoadingBeforeFirstAttempt() {
        XCTAssertEqual(PaywallDisplayState.resolve(isLoading: false, hasAttemptedLoad: false, productCount: 0, loadError: nil), .loading)
    }

    func testPaywallStateLoadingWhileFetching() {
        XCTAssertEqual(PaywallDisplayState.resolve(isLoading: true, hasAttemptedLoad: true, productCount: 0, loadError: nil), .loading)
    }

    func testPaywallStateContentWhenProductsExist() {
        XCTAssertEqual(PaywallDisplayState.resolve(isLoading: false, hasAttemptedLoad: true, productCount: 2, loadError: nil), .content)
    }

    func testPaywallStateEmptyWhenAppleReturnsNoProducts() {
        // Product.products(for:) returns [] (no throw) when the IDs
        // are unavailable — this must be its own state, not a loop.
        XCTAssertEqual(PaywallDisplayState.resolve(isLoading: false, hasAttemptedLoad: true, productCount: 0, loadError: nil), .empty)
    }

    func testPaywallStateFailedCarriesMessage() {
        XCTAssertEqual(PaywallDisplayState.resolve(isLoading: false, hasAttemptedLoad: true, productCount: 0, loadError: "boom"), .failed("boom"))
    }

    func testPaywallStateContentWinsOverStaleError() {
        XCTAssertEqual(PaywallDisplayState.resolve(isLoading: false, hasAttemptedLoad: true, productCount: 1, loadError: "stale"), .content)
    }

    // MARK: Savings — computed from real prices only

    func testYearlySavingsAtConfiguredPrices() {
        // $4.99/mo = $59.88/yr vs $29.99/yr -> ~50%.
        XCTAssertEqual(PremiumPricing.yearlySavingsPercent(monthlyPrice: Decimal(string: "4.99")!,
                                                           yearlyPrice: Decimal(string: "29.99")!), 50)
    }

    func testNoSavingsClaimWhenYearlyIsNotCheaper() {
        XCTAssertNil(PremiumPricing.yearlySavingsPercent(monthlyPrice: Decimal(string: "4.99")!,
                                                         yearlyPrice: Decimal(string: "59.88")!))
        XCTAssertNil(PremiumPricing.yearlySavingsPercent(monthlyPrice: 0, yearlyPrice: 10))
    }

    // MARK: Prompt copy — every gate explains and offers the upgrade

    func testPremiumPromptsAreComplete() {
        for prompt in [PremiumPrompt.addPet, .restorePet, .householdMembers, .documentScanning, .premiumFeature, .savedBrands] {
            XCTAssertFalse(prompt.title.isEmpty)
            XCTAssertFalse(prompt.message.isEmpty)
        }
        XCTAssertTrue(PremiumPrompt.addPet.message.contains("one pet"))
    }

    // MARK: Entitlement source of truth

    func testStoreStartsNonPremiumWithCleanLoadState() {
        let store = StoreManager()
        XCTAssertFalse(store.isPremium)
        XCTAssertNil(store.loadError)
        XCTAssertNil(store.purchaseError)
    }
}
