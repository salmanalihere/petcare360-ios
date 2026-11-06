import Foundation
import StoreKit
import Combine

/// StoreKit 2 subscription manager.
/// Entitlement comes ONLY from verified `Transaction.currentEntitlements`;
/// there is no local flag that can fake a purchase.
@MainActor
final class StoreManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedProductIDs: Set<String> = []
    @Published private(set) var isLoading = false
    /// True once a product load has been attempted at least once, so the
    /// paywall can distinguish "still loading" from "loaded but empty".
    @Published private(set) var hasAttemptedLoad = false
    /// Product-loading failures ONLY (kept separate from purchase
    /// errors so the paywall's states never mix them up).
    @Published private(set) var loadError: String? = nil
    @Published var purchaseError: String? = nil
    @Published var infoMessage: String? = nil

    private var updatesTask: Task<Void, Never>? = nil

    /// The app-managed 7-day free trial (2026-11-07). Its start date
    /// lives in the Keychain, so it survives reinstall on the same
    /// device; see TrialManager for the stated limitations.
    let trial = TrialManager()
    private var trialCancellable: AnyCancellable? = nil

    /// Purchase-only Premium, exactly as verified by StoreKit.
    var isPremium: Bool { !purchasedProductIDs.isEmpty }

    /// What feature gates use: a verified purchase OR an active free
    /// trial. During the trial every Premium feature works and no
    /// upgrade prompt is shown, because every gate reads this.
    var hasPremiumAccess: Bool {
        EntitlementPolicy.hasAccess(isPremium: isPremium, trialActive: trial.isActive)
    }

    init() {
        // The trial starts at first launch (owner brief 2026-11-07):
        // no purchase, no sign-up, no payment method.
        trial.beginIfNeeded()
        trialCancellable = trial.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
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
        } catch {
            loadError = "Subscription plans could not be loaded. Please check your connection and try again."
        }
    }

    /// Returns true only when a verified transaction left the user
    /// with an active Premium entitlement. Premium is NEVER unlocked
    /// by a tap alone, a pending approval, or an unverified result.
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
                infoMessage = "Your purchase is pending approval. Premium unlocks automatically once it is approved."
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
                infoMessage = "No active Premium subscription was found for this Apple ID."
            }
        } catch {
            purchaseError = "Restore did not complete. Please check your connection and try again."
        }
    }

    func refreshEntitlements() async {
        trial.refresh()
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.revocationDate == nil {
                active.insert(transaction.productID)
            }
        }
        purchasedProductIDs = active.intersection(Set(PremiumProduct.all))
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
