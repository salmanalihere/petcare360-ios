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

    // MARK: Trial end date — Apple's date passes through untouched

    /// The app computes NO trial dates of its own: the end of a
    /// free trial is the expirationDate of Apple's verified
    /// transaction, which already encodes the trial's start plus
    /// the duration configured in App Store Connect (7 days).
    /// These tests pin the policy's part of that contract: given a
    /// trial entitlement running Nov 10 → Nov 17, 2026, the
    /// resolved state must carry Nov 17 EXACTLY (the date the
    /// Family and Paywall screens display), in any timezone, and
    /// an earlier-dated entitlement in the same data must never
    /// shadow it.
    private func trialWeek(timeZoneID: String) throws -> (start: Date, end: Date) {
        let timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneID))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9)))
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: start))
        let endParts = calendar.dateComponents([.year, .month, .day], from: end)
        XCTAssertEqual(endParts.year, 2026)
        XCTAssertEqual(endParts.month, 11)
        XCTAssertEqual(endParts.day, 17, "Nov 10 + 7 calendar days must land on Nov 17 in \(timeZoneID)")
        return (start, end)
    }

    func testSevenDayTrialStartingNov102026EndsNov17InEveryTimezone() throws {
        for timeZoneID in ["UTC", "Asia/Kolkata", "America/Los_Angeles", "Pacific/Kiritimati"] {
            let week = try trialWeek(timeZoneID: timeZoneID)
            let state = SubscriptionAccessPolicy.resolve(
                snapshots: [snapshot(expiration: week.end, introductory: true, freeTrialOffer: true)],
                now: week.start)
            XCTAssertEqual(state,
                           .active(productID: PremiumProduct.monthly,
                                   expirationDate: week.end,
                                   isTrialPeriod: true,
                                   willAutoRenew: true,
                                   inGracePeriod: false),
                           "The displayed trial end must be the entitlement's own Nov 17 in \(timeZoneID) — never shifted, never shortened")
        }
    }

    func testLaterTrialEndWinsOverEarlierEntitlement() throws {
        let week = try trialWeek(timeZoneID: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let nov11 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 9)))
        let state = SubscriptionAccessPolicy.resolve(
            snapshots: [
                snapshot(productID: PremiumProduct.yearly, expiration: nov11),
                snapshot(expiration: week.end, introductory: true, freeTrialOffer: true),
            ],
            now: week.start)
        XCTAssertEqual(state,
                       .active(productID: PremiumProduct.monthly,
                               expirationDate: week.end,
                               isTrialPeriod: true,
                               willAutoRenew: true,
                               inGracePeriod: false),
                       "When a Nov 17 trial entitlement exists, an earlier Nov 11 date in the data must not be the one displayed")
    }

    func testTrialStaysActiveUntilItsExactEndInstant() throws {
        let week = try trialWeek(timeZoneID: "UTC")
        let trial = snapshot(expiration: week.end, introductory: true, freeTrialOffer: true)
        let justBefore = SubscriptionAccessPolicy.resolve(
            snapshots: [trial], now: week.end.addingTimeInterval(-60))
        XCTAssertEqual(justBefore,
                       .active(productID: PremiumProduct.monthly,
                               expirationDate: week.end,
                               isTrialPeriod: true,
                               willAutoRenew: true,
                               inGracePeriod: false))
        let atEnd = SubscriptionAccessPolicy.resolve(snapshots: [trial], now: week.end)
        XCTAssertEqual(atEnd, .inactive(billingIssue: false),
                       "At the end instant itself the trial period is over — no extra day is granted")
    }
}

/// Restore Purchases lifecycle tests (2026-11-10). StoreKit's
/// `AppStore.sync()` cannot be driven from this target, so the
/// lifecycle is tested at its decision core: every combination of
/// the run's facts (sync result, cancellation, refresh
/// verification, refreshed access) must land on exactly one
/// terminal `RestoreOutcome` with the right user-facing copy.
/// The precedence rules are the point: cancellation beats
/// everything, a sync failure is never masked by access that was
/// already on screen, and an unverifiable entitlement refresh is
/// never reported as a success or as "no purchases".
final class PetCare360RestoreOutcomeTests: XCTestCase {

    private let activeState = SubscriptionAccessState.active(
        productID: PremiumProduct.monthly,
        expirationDate: Date(timeIntervalSince1970: 1_800_086_400),
        isTrialPeriod: false, willAutoRenew: true, inGracePeriod: false)

    func testRestoredWhenSyncSucceedsAndVerifiedAccessIsActive() {
        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: true, cancelled: false, refreshVerified: true,
            accessState: activeState)
        XCTAssertEqual(outcome, .restored)
        XCTAssertEqual(outcome.message, "Purchases restored successfully.")
        XCTAssertFalse(outcome.isFailure)
    }

    func testRestoredInGracePeriodWhenAccessActiveButPaymentRetrying() {
        // Billing grace period: Apple could not collect the last
        // payment and is retrying, but the entitlement — and
        // therefore Premium access — is still fully active. The
        // restore must succeed AND surface the billing warning,
        // not collapse into a plain success or a failure.
        let graceState = SubscriptionAccessState.active(
            productID: PremiumProduct.monthly,
            expirationDate: Date(timeIntervalSince1970: 1_800_086_400),
            isTrialPeriod: false, willAutoRenew: true, inGracePeriod: true)
        XCTAssertTrue(graceState.hasAccess, "Grace period must preserve Premium access")
        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: true, cancelled: false, refreshVerified: true,
            accessState: graceState)
        XCTAssertEqual(outcome, .restoredInGracePeriod)
        XCTAssertEqual(outcome.message, "Purchases restored successfully. Apple could not collect your last payment and is retrying it — update your payment method in your Apple ID subscription settings to keep your access.")
        XCTAssertFalse(outcome.isFailure)
    }

    func testNoActivePurchaseWhenVerifiedRefreshFindsNoAccess() {
        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: true, cancelled: false, refreshVerified: true,
            accessState: .inactive(billingIssue: false))
        XCTAssertEqual(outcome, .noActivePurchase)
        XCTAssertTrue(outcome.message.contains("No active purchases were found"))
        XCTAssertFalse(outcome.isFailure)
    }

    func testBillingIssueIsDistinctFromNoPurchase() {
        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: true, cancelled: false, refreshVerified: true,
            accessState: .inactive(billingIssue: true))
        XCTAssertEqual(outcome, .billingIssue)
        XCTAssertTrue(outcome.message.contains("billing problem"))
        XCTAssertFalse(outcome.isFailure)
    }

    func testCancellationTakesPrecedenceOverSyncFailureAndExistingAccess() {
        // The user cancelled Apple's prompt: sync did not succeed
        // and an entitlement was already active on screen — the
        // outcome must still be the cancellation, nothing else.
        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: false, cancelled: true, refreshVerified: false,
            accessState: activeState)
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertFalse(outcome.isFailure)
    }

    func testSyncFailureIsNeverMaskedByExistingAccess() {
        // Premium was already accessible before the restore: a
        // throwing sync must NOT be reported as a restoration.
        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: false, cancelled: false, refreshVerified: false,
            accessState: activeState)
        XCTAssertEqual(outcome, .syncFailed)
        XCTAssertTrue(outcome.isFailure)
    }

    func testUnverifiedRefreshIsNeverReportedAsRestored() {
        // Sync completed and access is active from an earlier read,
        // but THIS run's refresh could not be verified — claiming
        // "restored" would be unproven.
        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: true, cancelled: false, refreshVerified: false,
            accessState: activeState)
        XCTAssertEqual(outcome, .verificationFailed)
        XCTAssertTrue(outcome.isFailure)
    }

    func testUnverifiedRefreshIsNeverReportedAsNoPurchases() {
        // The same unverifiable refresh with no access on screen
        // must not claim the Apple ID has no purchases — that is
        // exactly what could not be read.
        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: true, cancelled: false, refreshVerified: false,
            accessState: .inactive(billingIssue: false))
        XCTAssertEqual(outcome, .verificationFailed)
        XCTAssertTrue(outcome.isFailure)
    }

    func testEveryOutcomeHasUserFacingCopy() {
        let outcomes: [RestoreOutcome] = [.restored, .restoredInGracePeriod, .noActivePurchase,
                                          .billingIssue, .cancelled, .syncFailed, .verificationFailed]
        for outcome in outcomes {
            XCTAssertFalse(outcome.message.isEmpty, "\(outcome) must have user-facing copy")
        }
        XCTAssertEqual(RestoreOutcome.restored.message, "Purchases restored successfully.")
        XCTAssertTrue(RestoreOutcome.noActivePurchase.message.contains("No active purchases were found"))
    }

    /// The restore state machine starts idle: no run in flight and
    /// no outcome, so no stale result can be on screen before the
    /// user has ever restored. (Mirrors the StoreManager pattern in
    /// PetCare360PremiumTests.) StoreManager is MainActor-isolated,
    /// so this test runs on the MainActor and reads the values into
    /// locals before asserting — the assertion autoclosures then
    /// never touch actor-isolated state.
    @MainActor
    func testStoreStartsWithNoRestoreInFlightAndNoOutcome() {
        let store = StoreManager()
        let isRestoring = store.isRestoring
        let restoreOutcome = store.restoreOutcome
        XCTAssertFalse(isRestoring)
        XCTAssertNil(restoreOutcome)
    }
}
