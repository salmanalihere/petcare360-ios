import XCTest
import StoreKit
import StoreKitTest
@testable import PetCare360

/// ISOLATED StoreKit diagnostic (2026-11-08) — not a regression
/// test for the app; a verdict on the ENVIRONMENT.
///
/// Question it answers: can THIS simulator, under THIS
/// command-line test run, sustain a local StoreKit session at
/// all — session creation from the bundled PetCare360.storekit,
/// product loading, a programmatic monthly purchase
/// (SKTestSession with dialogs disabled — no confirmation sheet
/// involved), transaction verification, and a resulting current
/// entitlement?
///
/// Context: the full-suite UI tests reach the subscription
/// gate, load both products, tap purchase — and
/// Product.purchase() then suspends forever with no sheet, no
/// result, no error (runs 6af01f68 / 6af02598). The generated
/// .xctestrun for the split build-for-testing /
/// test-without-building pipeline contains NO StoreKit keys, so
/// the UI launches may never receive a session. This diagnostic
/// removes the UI, the app, and the scheme from the equation:
/// SKTestSession loads the configuration explicitly, in-process,
/// in the app-hosted unit-test target. Its SKDIAG lines print
/// every step's outcome, including the exact error domain/code
/// on failure (on the iOS 26.x runtime, session creation is
/// reported to fail with SKInternalErrorDomain Code 3, "Error
/// saving configuration file").
///
/// Whatever this test's verdict, production purchase /
/// subscription / entitlement code is untouched by it, and
/// nothing here grants access: the entitlement assertion reads
/// only StoreKit-verified transactions.
final class PetCare360StoreKitDiagnosticsTests: XCTestCase {

    private func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "domain=\(ns.domain) code=\(ns.code) \"\(error.localizedDescription)\""
    }

    func testSKTestSessionLocalPurchaseCompletes() async throws {
        // STEP 1 — the configuration file must be IN this bundle
        // (proves the project wiring, separately from StoreKit).
        guard let configURL = Bundle(for: Self.self)
            .url(forResource: "PetCare360", withExtension: "storekit") else {
            XCTFail("SKDIAG config MISSING: PetCare360.storekit is not in the unit-test bundle — the project wiring failed before StoreKit was involved")
            return
        }
        print("SKDIAG config found in unit-test bundle: \(configURL.lastPathComponent)")

        // STEP 2 — session creation. THE verdict step on this
        // runtime: if storekitd cannot accept a configuration
        // under a command-line run, it fails here, with the error.
        let session: SKTestSession
        do {
            session = try SKTestSession(contentsOf: configURL)
            print("SKDIAG session CREATED from PetCare360.storekit")
        } catch {
            XCTFail("SKDIAG session creation FAILED: \(describe(error)) — the local StoreKit session could not be established in this environment at all")
            return
        }

        // STEP 3 — clean slate + programmatic purchases.
        session.disableDialogs = true
        do {
            try session.clearTransactions()
            print("SKDIAG session transactions cleared")
        } catch {
            print("SKDIAG clearTransactions error (continuing): \(describe(error))")
        }

        // STEP 4 — product loading through the session's
        // configuration.
        let products: [Product]
        do {
            products = try await Product.products(for: PremiumProduct.all)
            let summary = products.map { "\($0.id)@\($0.displayPrice)" }.joined(separator: ", ")
            print("SKDIAG products loaded: [\(summary)]")
        } catch {
            XCTFail("SKDIAG product loading FAILED: \(describe(error))")
            return
        }
        XCTAssertEqual(Set(products.map(\.id)), Set(PremiumProduct.all),
                       "SKDIAG both configured products must load through the test session")

        // STEP 5 — the purchase itself: programmatic, no sheet,
        // no UI. If a local transaction can complete in this
        // environment, it completes here.
        let transaction: Transaction
        do {
            transaction = try await session.buyProduct(identifier: PremiumProduct.monthly)
            print("SKDIAG purchase RETURNED transaction id \(transaction.id) product \(transaction.productID)")
        } catch {
            XCTFail("SKDIAG buyProduct FAILED: \(describe(error)) — a local purchase could not complete in this environment")
            return
        }
        XCTAssertEqual(transaction.productID, PremiumProduct.monthly,
                       "SKDIAG the returned transaction must be for the monthly product")

        // STEP 6 — the entitlement must be real: a VERIFIED
        // transaction visible through Transaction.currentEntitlements,
        // the same source the app's access policy reads.
        var verifiedIDs: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let current) = result {
                verifiedIDs.insert(current.productID)
            }
        }
        print("SKDIAG verified current entitlements: [\(verifiedIDs.sorted().joined(separator: ", "))]")
        XCTAssertTrue(verifiedIDs.contains(PremiumProduct.monthly),
                      "SKDIAG the purchase must produce a verified current entitlement for the monthly product")
        print("SKDIAG VERDICT: local StoreKit purchase COMPLETES in this environment (session, products, purchase, verification, entitlement all OK)")
    }
}
