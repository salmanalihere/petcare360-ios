import Foundation

/// One Apple-verified subscription entitlement, flattened into plain
/// values so the access decision is a pure function that unit tests
/// can drive without StoreKit. StoreManager builds these ONLY from
/// verified sources: `Transaction.currentEntitlements` and
/// `Product.SubscriptionInfo.status` — never from local storage.
struct SubscriptionEntitlementSnapshot: Equatable {
    var productID: String
    /// When the current paid/trial period ends. Access runs until
    /// this date (a cancelled subscription keeps access until here).
    var expirationDate: Date?
    /// Set when Apple has revoked the transaction (refund/fraud).
    /// A revoked entitlement grants nothing, even before expiry.
    var revocationDate: Date?
    /// The current period began with the product's introductory
    /// offer (Transaction.offerType == .introductory).
    var isIntroductoryPeriod: Bool
    /// The introductory offer is a FREE trial (its payment mode is
    /// .freeTrial in the product's App Store Connect configuration).
    var isFreeTrialOffer: Bool
    /// Apple is in the billing grace period: payment failed but
    /// Apple keeps the entitlement alive while it retries.
    var inGracePeriod: Bool
    /// Apple is in billing retry after the grace period: the
    /// entitlement is suspended until payment succeeds.
    var inBillingRetry: Bool
    var willAutoRenew: Bool

    /// In the introductory FREE-TRIAL period right now.
    var isTrialPeriod: Bool { isIntroductoryPeriod && isFreeTrialOffer }
}

/// The app's subscription access decision — the single source of
/// truth for the app lock. There is deliberately no "free" state:
/// without an active Apple entitlement the app is locked.
enum SubscriptionAccessState: Equatable {
    /// Entitlements have not been read yet (cold start). The UI
    /// shows a loading screen — neither the app nor a purchase
    /// decision — so nothing is ever unlocked by default.
    case unknown
    /// A verified entitlement is active. `isTrialPeriod` marks the
    /// introductory free-trial window for honest UI copy only; it
    /// never affects the access decision itself.
    case active(productID: String, expirationDate: Date?, isTrialPeriod: Bool, willAutoRenew: Bool, inGracePeriod: Bool)
    /// No active entitlement. `billingIssue` is true when Apple
    /// reports the subscription is in billing retry, so the locked
    /// screen can tell the user to fix their payment method instead
    /// of just asking them to subscribe again.
    case inactive(billingIssue: Bool)

    var hasAccess: Bool {
        if case .active = self { return true }
        return false
    }

    var isResolved: Bool { self != .unknown }
}

/// Pure access policy over verified entitlement snapshots.
enum SubscriptionAccessPolicy {
    static func resolve(snapshots: [SubscriptionEntitlementSnapshot], now: Date) -> SubscriptionAccessState {
        // Only our two products count, and a revoked transaction
        // counts for nothing.
        let relevant = snapshots.filter {
            PremiumProduct.all.contains($0.productID) && $0.revocationDate == nil
        }
        // Active = the period has not ended, OR Apple is keeping the
        // entitlement alive in the billing grace period. A cancelled
        // subscription is still active until its expiration date —
        // cancellation only stops renewal (willAutoRenew == false),
        // it never shortens access.
        let active = relevant.filter {
            $0.inGracePeriod || $0.expirationDate == nil || ($0.expirationDate ?? .distantPast) > now
        }
        if let best = active.max(by: { ($0.expirationDate ?? .distantFuture) < ($1.expirationDate ?? .distantFuture) }) {
            return .active(productID: best.productID,
                           expirationDate: best.expirationDate,
                           isTrialPeriod: best.isTrialPeriod,
                           willAutoRenew: best.willAutoRenew,
                           inGracePeriod: best.inGracePeriod)
        }
        if relevant.contains(where: { $0.inBillingRetry }) {
            return .inactive(billingIssue: true)
        }
        return .inactive(billingIssue: false)
    }
}

/// The terminal outcome of one Restore Purchases run. Every restore
/// ends in exactly one of these — including the failure and
/// cancellation paths — so the UI always has something truthful to
/// show. Before this existed, a successful restore against an
/// already-active subscription changed nothing on screen and was
/// indistinguishable from a restore that never ran.
enum RestoreOutcome: Equatable {
    /// App Store sync completed and the verified entitlement
    /// refresh found an active subscription.
    case restored
    /// Restored and active, but Apple is in the billing grace
    /// period: the last payment could not be collected and Apple
    /// is retrying it. Access is fully preserved — the outcome is
    /// distinct from a plain success so the user hears about the
    /// payment problem while they are looking at their
    /// subscription, instead of losing access without warning
    /// when the grace period ends.
    case restoredInGracePeriod
    /// Sync completed and entitlements were verified, but this
    /// Apple ID has no active PetCare 360 subscription.
    case noActivePurchase
    /// A subscription exists but Apple has it paused in billing
    /// retry — it was found, so "no purchases" would be a lie.
    case billingIssue
    /// The user cancelled Apple's authentication/sync prompt.
    case cancelled
    /// `AppStore.sync()` itself threw (network, system, storefront).
    case syncFailed
    /// Sync completed but the entitlement refresh could not be
    /// verified, so the run must NOT be reported as a success or
    /// as "no purchases" — neither is known to be true.
    case verificationFailed

    /// The exact user-facing copy for the outcome.
    var message: String {
        switch self {
        case .restored:
            return "Purchases restored successfully."
        case .restoredInGracePeriod:
            return "Purchases restored successfully. Apple could not collect your last payment and is retrying it — update your payment method in your Apple ID subscription settings to keep your access."
        case .noActivePurchase:
            return "No active purchases were found for this Apple ID."
        case .billingIssue:
            return "Your subscription was found, but Apple has paused it because of a billing problem. Update your payment method in your Apple ID subscription settings, then restore again."
        case .cancelled:
            return "Restore was cancelled."
        case .syncFailed:
            return "Restore did not complete. Please check your connection and try again."
        case .verificationFailed:
            return "Your purchases could not be verified. Please check your connection and try again."
        }
    }

    /// Failures render in the error colour; every other outcome is
    /// informational (success, none found, cancelled, billing).
    var isFailure: Bool {
        self == .syncFailed || self == .verificationFailed
    }
}

/// Pure mapping from a finished restore run's facts to its single
/// terminal outcome — the restore lifecycle's decision core, kept
/// separate from StoreKit so unit tests can drive every branch.
/// Precedence is deliberate: a cancellation is reported as a
/// cancellation even though sync did not succeed; a sync failure
/// is never masked by whatever access state was already on screen;
/// and an unverifiable refresh is never reported as a success or
/// as "no purchases", even if a previous entitlement is still
/// active from an earlier verified read.
enum RestoreOutcomeResolver {
    static func resolve(syncSucceeded: Bool,
                        cancelled: Bool,
                        refreshVerified: Bool,
                        accessState: SubscriptionAccessState) -> RestoreOutcome {
        if cancelled { return .cancelled }
        guard syncSucceeded else { return .syncFailed }
        guard refreshVerified else { return .verificationFailed }
        // Grace period BEFORE plain success: access is active in
        // both, but the grace user must hear that Apple is
        // retrying a failed payment. Premium access itself is
        // unaffected — the policy already resolved it as active.
        if case .active(_, _, _, _, let inGracePeriod) = accessState, inGracePeriod {
            return .restoredInGracePeriod
        }
        if accessState.hasAccess { return .restored }
        if case .inactive(let billingIssue) = accessState, billingIssue {
            return .billingIssue
        }
        return .noActivePurchase
    }
}
