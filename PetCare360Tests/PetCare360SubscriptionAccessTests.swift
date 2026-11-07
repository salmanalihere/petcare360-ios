import XCTest
@testable import PetCare360

/// Subscription-access policy tests (subscription-only model,
/// 2026-11-08). These replaced the retired app-managed trial tests
/// when the Keychain trial was removed: access now comes ONLY from
/// Apple-verified subscription entitlements, and
/// SubscriptionAccessPolicy is the pure decision over them.
/// StoreKit itself cannot run in this target, so the policy is
/// driven with snapshots shaped exactly like the ones StoreManager
/// builds from verified transactions and subscription statuses.
final class PetCare360SubscriptionAccessTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000) // fixed reference instant
    private var day: TimeInterval { 86_400 }

    private func snapshot(productID: String = PremiumProduct.monthly,
                          expiration: Date?,
                          revoked: Date? = nil,
                          introductory: Bool = false,
                          freeTrialOffer: Bool = false,
                          grace: Bool = false,
                          billingRetry: Bool = false,
                          autoRenew: Bool = true) -> SubscriptionEntitlementSnapshot {
        SubscriptionEntitlementSnapshot(
            productID: productID,
            expirationDate: expiration,
            revocationDate: revoked,
            isIntroductoryPeriod: introductory,
            isFreeTrialOffer: freeTrialOffer,
            inGracePeriod: grace,
            inBillingRetry: billingRetry,
            willAutoRenew: autoRenew)
    }

    // MARK: No entitlement -> locked

    func testNoEntitlementsMeansNoAccess() {
        let state = SubscriptionAccessPolicy.resolve(snapshots: [], now: now)
        XCTAssertEqual(state, .inactive(billingIssue: false))
        XCTAssertFalse(state.hasAccess)
    }

    func testUnknownProductIsIgnored() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(productID: "com.example.other", expiration: now.addingTimeInterval(day))],
            now: now)
        XCTAssertEqual(state, .inactive(billingIssue: false))
    }

    func testExpiredSubscriptionMeansNoAccess() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now.addingTimeInterval(-day))],
            now: now)
        XCTAssertEqual(state, .inactive(billingIssue: false))
        XCTAssertFalse(state.hasAccess)
    }

    func testExpirationExactlyNowMeansNoAccess() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now)],
            now: now)
        XCTAssertFalse(state.hasAccess)
    }

    func testRevokedSubscriptionMeansNoAccessEvenBeforeExpiry() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now.addingTimeInterval(10 * day), revoked: now)],
            now: now)
        XCTAssertEqual(state, .inactive(billingIssue: false))
    }

    // MARK: Active entitlement -> unlocked

    func testActiveMonthlyUnlocks() {
        let expiry = now.addingTimeInterval(30 * day)
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: expiry)],
            now: now)
        XCTAssertEqual(state, .active(productID: PremiumProduct.monthly,
                                      expirationDate: expiry,
                                      isTrialPeriod: false,
                                      willAutoRenew: true,
                                      inGracePeriod: false))
        XCTAssertTrue(state.hasAccess)
    }

    func testActiveYearlyUnlocks() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(productID: PremiumProduct.yearly,
                                 expiration: now.addingTimeInterval(365 * day))],
            now: now)
        XCTAssertTrue(state.hasAccess)
        if case .active(let productID, _, _, _, _) = state {
            XCTAssertEqual(productID, PremiumProduct.yearly)
        } else {
            XCTFail("Expected .active, got \(state)")
        }
    }

    /// Requirement: a cancelled subscription keeps FULL access
    /// until its paid period ends. Cancellation only stops renewal.
    func testCancelledButUnexpiredKeepsAccess() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now.addingTimeInterval(12 * day), autoRenew: false)],
            now: now)
        XCTAssertTrue(state.hasAccess)
        if case .active(_, _, _, let willAutoRenew, _) = state {
            XCTAssertFalse(willAutoRenew)
        } else {
            XCTFail("Expected .active, got \(state)")
        }
    }

    // MARK: Apple's free trial (introductory offer)

    /// During the introductory free trial the user has full access,
    /// flagged as a trial period for honest UI copy.
    func testFreeTrialPeriodUnlocksAndIsFlagged() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now.addingTimeInterval(7 * day),
                                 introductory: true, freeTrialOffer: true)],
            now: now)
        if case .active(_, _, let isTrial, _, _) = state {
            XCTAssertTrue(isTrial)
        } else {
            XCTFail("Expected .active trial, got \(state)")
        }
    }

    /// A cancelled free trial still runs to its expiration date.
    func testCancelledTrialKeepsAccessUntilTrialEnd() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now.addingTimeInterval(3 * day),
                                 introductory: true, freeTrialOffer: true, autoRenew: false)],
            now: now)
        XCTAssertTrue(state.hasAccess)
    }

    /// An introductory offer that is NOT a free trial (e.g. a
    /// discounted first period) grants access but must not be
    /// reported to the user as a free trial.
    func testPaidIntroductoryPeriodIsNotFlaggedAsTrial() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now.addingTimeInterval(30 * day),
                                 introductory: true, freeTrialOffer: false)],
            now: now)
        if case .active(_, _, let isTrial, _, _) = state {
            XCTAssertFalse(isTrial)
        } else {
            XCTFail("Expected .active, got \(state)")
        }
    }

    // MARK: Billing states

    /// Grace period: payment failed, Apple keeps the entitlement
    /// alive while it retries the card — access continues even
    /// though the nominal expiration has passed.
    func testGracePeriodKeepsAccessPastNominalExpiry() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now.addingTimeInterval(-2 * day), grace: true)],
            now: now)
        XCTAssertTrue(state.hasAccess)
        if case .active(_, _, _, _, let inGrace) = state {
            XCTAssertTrue(inGrace)
        } else {
            XCTFail("Expected .active grace period, got \(state)")
        }
    }

    /// Billing retry (after grace): the entitlement is suspended
    /// and the app locks, flagged as a billing issue so the locked
    /// screen can direct the user to fix their payment method.
    func testBillingRetryLocksWithBillingIssueFlag() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [snapshot(expiration: now.addingTimeInterval(-9 * day), billingRetry: true)],
            now: now)
        XCTAssertEqual(state, .inactive(billingIssue: true))
        XCTAssertFalse(state.hasAccess)
    }

    /// An active entitlement on one product wins over a billing
    /// retry reported for the other.
    func testActiveEntitlementWinsOverBillingRetry() {
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [
                snapshot(productID: PremiumProduct.yearly,
                         expiration: now.addingTimeInterval(-9 * day), billingRetry: true),
                snapshot(expiration: now.addingTimeInterval(20 * day)),
            ],
            now: now)
        XCTAssertTrue(state.hasAccess)
    }

    // MARK: Multiple entitlements / state basics

    /// With several snapshots, the one ending latest is the
    /// effective entitlement.
    func testLatestExpirationWins() {
        let yearly = now.addingTimeInterval(300 * day)
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [
                snapshot(expiration: now.addingTimeInterval(10 * day)),
                snapshot(productID: PremiumProduct.yearly, expiration: yearly),
            ],
            now: now)
        if case .active(let productID, let expiration, _, _, _) = state {
            XCTAssertEqual(productID, PremiumProduct.yearly)
            XCTAssertEqual(expiration, yearly)
        } else {
            XCTFail("Expected .active, got \(state)")
        }
    }

    /// The unresolved state grants nothing and is not "resolved":
    /// the UI must show its checking screen, never the app.
    func testUnknownStateGrantsNothing() {
        let state = SubscriptionAccessState.unknown
        XCTAssertFalse(state.hasAccess)
        XCTAssertFalse(state.isResolved)
        XCTAssertTrue(SubscriptionAccessState.inactive(billingIssue: false).isResolved)
    }

    /// Access follows the entitlement only — the policy has no
    /// input for any local flag, so nothing stored on the device
    /// can manufacture access.
    func testAccessIsEntitlementOnly() {
        for snapshots in [[SubscriptionEntitlementSnapshot](), [snapshot(expiration: now.addingTimeInterval(-day))]] {
            XCTAssertFalse(SubscriptionAccessPolicy.resolve(snapshots: snapshots, now: now).hasAccess)
        }
    }
}
