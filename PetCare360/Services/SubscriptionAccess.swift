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
