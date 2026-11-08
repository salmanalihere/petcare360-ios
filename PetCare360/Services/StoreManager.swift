import Foundation
import StoreKit
import Combine
import os

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

    /// Unified log for the StoreKit lifecycle (Console subsystem
    /// "StoreKit", and the Codemagic full-tests workflow extracts
    /// it from the simulator log after a failed UI run). The
    /// purchase path logs its BEGIN, periodic STILL-SUSPENDED
    /// heartbeats while `Product.purchase()` is awaited, and
    /// exactly one terminal line (result / error) — so a hung
    /// purchase is distinguishable from a returned one in the log
    /// alone. Logging only: it never affects access decisions.
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PetCare360",
                                    category: "StoreKit")

    /// True while a `Product.purchase()` call is in flight. A
    /// second purchase started concurrently would stack StoreKit
    /// presentations, so `purchase` refuses to overlap; the flag
    /// is also the heartbeat's suspension signal. If StoreKit
    /// never returns, this stays true and the purchasing UI stays
    /// disabled — deliberate: there is no safe local recovery
    /// from a suspended system purchase (cancelling the awaiting
    /// Task does not cancel StoreKit's presentation), and
    /// re-enabling the button would invite a second, stacked
    /// purchase. Access is never affected by this flag.
    @Published private(set) var purchaseInFlight = false

    private var accessDescription: String {
        switch accessState {
        case .unknown: return "unknown"
        case .active(let productID, _, let isTrial, _, let inGrace):
            return "active(product: \(productID), trial: \(isTrial), grace: \(inGrace))"
        case .inactive(let billingIssue):
            return "inactive(billingIssue: \(billingIssue))"
        }
    }

    /// True only while a verified entitlement is active (paid,
    /// free-trial, grace-period, or cancelled-but-unexpired).
    var isPremium: Bool { accessState.hasAccess }

    /// What feature gates use. In the subscription-only model this
    /// is exactly `isPremium`: there is no other way in.
    var hasPremiumAccess: Bool { EntitlementPolicy.hasAccess(isPremium: isPremium) }

    init() {
        // Which test-environment signals did this process actually
        // receive? The scheme's StoreKit configuration is pushed
        // to the simulator's storekitd by the test RUNNER (not
        // embedded in the app), so the app cannot inspect it
        // directly — but the runner-injected environment and,
        // decisively, the products served (see loadProducts) show
        // whether a local session is active for this launch.
        let environment = ProcessInfo.processInfo.environment
        let injected = environment.keys
            .filter { $0.localizedCaseInsensitiveContains("storekit") || $0.localizedCaseInsensitiveContains("xctest") }
            .sorted()
        Self.log.info("StoreManager init. Runner-injected environment keys: \(injected.joined(separator: ","), privacy: .public)")
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
            // PROVENANCE: a free-trial introductory offer can only
            // come from the LOCAL PetCare360.storekit in this
            // build — the App Store Connect products carry no
            // introductory offers (none have been created there).
            // A "free/P7D" line below therefore proves the local
            // StoreKit configuration served this launch's
            // products; its absence proves the opposite.
            for product in products {
                let offer = product.subscription?.introductoryOffer
                let offerText = offer.map { "\($0.paymentMode == .freeTrial ? "freeTrial" : "other")/value:\($0.period.value)/unit:\(String(describing: $0.period.unit))" } ?? "none"
                Self.log.info("Product loaded: \(product.id, privacy: .public) price \(product.displayPrice, privacy: .public) introOffer \(offerText, privacy: .public) eligible \(eligibility[product.id] ?? false)")
            }
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
        // Never stack purchases: a second call while StoreKit is
        // still presenting would queue behind (or corrupt) the
        // first. The attempt is refused and logged; the in-flight
        // purchase continues to its own outcome.
        guard !purchaseInFlight else {
            Self.log.error("purchase.begin REFUSED: another purchase is already in flight")
            return false
        }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        Self.log.info("purchase.begin product \(product.id, privacy: .public) price \(product.displayPrice, privacy: .public) — awaiting Product.purchase() (system confirmation sheet should present now)")
        // Suspension heartbeat: logs at +10s and +20s ONLY if the
        // await has not returned, so the run log distinguishes
        // "StoreKit never answered" from any returned result.
        // The watchdog never touches state — see purchaseInFlight.
        let heartbeat = Task {
            for elapsed in [10, 20] {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { return }
                Self.log.error("purchase.stillSuspended product \(product.id, privacy: .public) elapsed \(elapsed)s — Product.purchase() has NOT returned; no result, no error (the confirmation sheet was never presented or never answered)")
            }
        }
        defer { heartbeat.cancel() }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                Self.log.info("purchase.result success — verifying transaction")
                let transaction = try checkVerified(verification)
                Self.log.info("purchase.verified transaction \(transaction.id) product \(transaction.productID, privacy: .public) — refreshing entitlements")
                await refreshEntitlements()
                await transaction.finish()
                Self.log.info("purchase.finished — access now \(self.accessDescription, privacy: .public)")
                return isPremium
            case .userCancelled:
                Self.log.info("purchase.result userCancelled")
                return false
            case .pending:
                Self.log.info("purchase.result pending (approval outstanding)")
                infoMessage = "Your purchase is pending approval. Access unlocks automatically once it is approved."
                return false
            @unknown default:
                Self.log.error("purchase.result unknown-default")
                return false
            }
        } catch {
            Self.log.error("purchase.error \(error.localizedDescription, privacy: .public)")
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
        Self.log.info("entitlements.refreshed snapshots \(snapshots.count) purchasedIDs \(self.purchasedProductIDs.sorted().joined(separator: ","), privacy: .public) access \(self.accessDescription, privacy: .public)")
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
