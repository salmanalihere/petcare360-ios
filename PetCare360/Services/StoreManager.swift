import Foundation
import StoreKit
import Combine

/// StoreKit 2 subscription manager — Apple-entitlement ONLY.
///
/// As of the subscription-only model (2026-11-08) there is no
/// app-managed trial and no free tier: the app is unlocked solely by
/// a verified Apple subscription entitlement (which includes the
/// introductory 7-day free trial configured in App Store Connect,
/// Apple's billing grace period, and a cancelled-but-unexpired
/// subscription). The decision is computed by
/// `SubscriptionAccessPolicy` from verified data —
/// `Transaction.currentEntitlements` plus
/// `Product.SubscriptionInfo.status` — and re-checked at launch, on
/// every foreground return, and on every `Transaction.updates`
/// event. Nothing is read from UserDefaults, the Keychain, or any
/// local flag to decide access; the retired Keychain trial record
/// is ignored entirely.
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    /// The resolved access decision. Starts `.unknown`: the UI shows
    /// a loading screen until the first verified entitlement read
    /// completes, so the app can never flash unlocked — or locked —
    /// on a guess.
    @Published private(set) var accessState: SubscriptionAccessState = .unknown
    /// Per-product introductory-offer eligibility as reported by
    /// StoreKit for this Apple ID. The subscription screens use it
    /// to offer the 7-day free trial ONLY to users Apple will
    /// actually grant it to.
    @Published private(set) var introOfferEligible: [String: Bool] = [:]
    @Published private(set) var isLoading = false
    /// True once a product load has been attempted at least once, so
    /// the paywall can distinguish "still loading" from "loaded but
    /// empty".
    @Published private(set) var hasAttemptedLoad = false
    /// Product-loading failures ONLY (kept separate from purchase
    /// errors so the paywall's states never mix them up).
    @Published private(set) var loadError: String? = nil
    @Published var purchaseError: String? = nil
    @Published var infoMessage: String? = nil

    private var updatesTask: Task<Void, Never>? = nil

    /// True only while a verified entitlement is active (paid,
    /// free-trial, grace-period, or cancelled-but-unexpired).
    var isPremium: Bool { accessState.hasAccess }

    /// What feature gates use. In the subscription-only model this
    /// is exactly `isPremium`: there is no other way in.
    var hasPremiumAccess: Bool { EntitlementPolicy.hasAccess(isPremium: isPremium) }

    init() {
        updatesTask = listenForTransactions()
        Task { await loadProducts(); await refreshEntitlements() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false; hasAttemptedLoad = true }
        do {
            // NOTE: Product.products(for:) returns an EMPTY array (it
            // does not throw) when none of the requested identifiers
            // are available for this app/Apple ID — e.g. the products
            // do not exist in App Store Connect yet, the Paid Apps
            // agreement is not active, or the build has no StoreKit
            // configuration. The paywall renders that as its own
            // "no plans available" state with a working Retry, never
            // as an endless loading loop.
            products = try await Product.products(for: PremiumProduct.all)
                .sorted { $0.price < $1.price }
            // Introductory-offer eligibility is per Apple ID and is
            // decided by Apple; refresh it with the products so the
            // subscription screens never promise a trial Apple will
            // not grant (e.g. to a returning subscriber).
            var eligibility: [String: Bool] = [:]
            for product in products {
                if let subscription = product.subscription {
                    eligibility[product.id] = await subscription.isEligibleForIntroOffer
                }
            }
            introOfferEligible = eligibility
        } catch {
            loadError = "Subscription plans could not be loaded. Please check your connection and try again."
        }
    }

    /// Whether starting `product` would begin its introductory FREE
    /// trial for this user: the product must carry a free-trial
    /// introductory offer AND Apple must report this Apple ID as
    /// eligible for it.
    func offersFreeTrial(_ product: Product) -> Bool {
        guard let offer = product.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return false }
        return introOfferEligible[product.id] ?? false
    }

    /// Returns true only when a verified transaction left the user
    /// with an active entitlement. Access is NEVER unlocked by a tap
    /// alone, a pending approval, or an unverified result.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        infoMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await refreshEntitlements()
                await transaction.finish()
                return isPremium
            case .userCancelled:
                return false
            case .pending:
                infoMessage = "Your purchase is pending approval. Access unlocks automatically once it is approved."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = "Purchase did not complete. You have not been charged."
            return false
        }
    }

    func restorePurchases() async {
        purchaseError = nil
        infoMessage = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !isPremium {
                infoMessage = "No active subscription was found for this Apple ID."
            }
        } catch {
            purchaseError = "Restore did not complete. Please check your connection and try again."
        }
    }

    /// Rebuilds the access decision from Apple-verified data only.
    /// Called at launch, on foreground return (ContentView), after
    /// purchases and restores, and for every transaction update
    /// (renewals, trial conversion, expiry, revocation, billing
    /// state changes).
    func refreshEntitlements() async {
        var snapshots: [SubscriptionEntitlementSnapshot] = []
        var seen: Set<String> = []

        // Richest signal first: the subscription group's statuses
        // carry the renewal info (grace period, billing retry,
        // auto-renew) alongside each verified transaction.
        if let statuses = try? await Product.SubscriptionInfo.status(for: AppConfig.subscriptionGroupID) {
            for status in statuses {
                guard let transaction = try? checkVerified(status.transaction) else { continue }
                snapshots.append(snapshot(for: transaction, status: status))
                seen.insert(transaction.productID)
            }
        }
        // Any current entitlement the statuses did not cover.
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result),
                  !seen.contains(transaction.productID) else { continue }
            snapshots.append(snapshot(for: transaction, status: nil))
            seen.insert(transaction.productID)
        }

        purchasedProductIDs = Set(snapshots.compactMap { snapshot in
            guard snapshot.revocationDate == nil,
                  snapshot.expirationDate == nil || (snapshot.expirationDate ?? .distantPast) > Date()
                    || snapshot.inGracePeriod else { return nil }
            return snapshot.productID
        }).intersection(Set(PremiumProduct.all))
        accessState = SubscriptionAccessPolicy.resolve(snapshots: snapshots, now: Date())
    }

    private func snapshot(for transaction: Transaction,
                          status: Product.SubscriptionInfo.Status?) -> SubscriptionEntitlementSnapshot {
        var inGracePeriod = false
        var inBillingRetry = false
        var willAutoRenew = false
        if let status {
            switch status.state {
            case .inGracePeriod: inGracePeriod = true
            case .inBillingRetryPeriod: inBillingRetry = true
            default: break
            }
            if let renewalInfo = try? checkVerified(status.renewalInfo) {
                willAutoRenew = renewalInfo.willAutoRenew
            }
        }
        let product = products.first(where: { $0.id == transaction.productID })
        let isFreeTrialOffer = product?.subscription?.introductoryOffer?.paymentMode == .freeTrial
        return SubscriptionEntitlementSnapshot(
            productID: transaction.productID,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isIntroductoryPeriod: transaction.offerType == .introductory,
            isFreeTrialOffer: isFreeTrialOffer,
            inGracePeriod: inGracePeriod,
            inBillingRetry: inBillingRetry,
            willAutoRenew: willAutoRenew)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                if let transaction = try? self.checkVerified(result) {
                    await self.refreshEntitlements()
                    await transaction.finish()
                }
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe): return safe
        }
    }
}
