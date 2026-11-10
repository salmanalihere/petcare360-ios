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

    /// True while a Restore Purchases run is in flight (the
    /// `AppStore.sync()` await plus the entitlement refresh that
    /// follows it). Restore buttons disable and show their
    /// restoring state from this flag, and `restorePurchases`
    /// refuses to start a second, overlapping run while it is set.
    @Published private(set) var isRestoring = false

    /// The terminal outcome of the most recent restore run, set
    /// exactly once when the run finishes — success, no purchase,
    /// billing issue, cancellation, sync failure, or unverifiable
    /// refresh. Nil until the first restore completes. Restore
    /// surfaces render this outcome's message; the shared
    /// purchaseError/infoMessage are deliberately NOT used for
    /// restore results, so a restore can never be masked by — or
    /// mask — a purchase message.
    @Published private(set) var restoreOutcome: RestoreOutcome? = nil

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
        // directly. What the app CAN record is the runner-injected
        // environment (below) and what it was served (see
        // loadProducts) — observations to correlate with the
        // runner-side evidence, not proof of the session's source.
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
            // OBSERVED CATALOGUE: these lines record what StoreKit
            // actually served this launch — product IDs, prices,
            // introductory offers, eligibility — for correlation
            // with the workflow's runner-side storekitd evidence.
            // They do NOT prove where the products came from:
            // the local PetCare360.storekit and App Store Connect
            // both configure the same products with the same
            // 7-day free-trial offers, so an observed freeTrial/P7D
            // offer is consistent with either source.
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

    /// Restore Purchases: synchronize with the App Store, then
    /// re-read the verified entitlements and publish exactly one
    /// terminal `RestoreOutcome`. Access is decided ONLY by the
    /// refreshed verified entitlements — a completed sync by
    /// itself never unlocks anything. Overlapping runs are
    /// refused: a second `AppStore.sync()` stacked on the first
    /// would double Apple's authentication prompts and race the
    /// outcome.
    func restorePurchases() async {
        guard !isRestoring else {
            Self.log.error("restore.begin REFUSED: a restore is already in progress")
            return
        }
        isRestoring = true
        restoreOutcome = nil
        defer { isRestoring = false }
        Self.log.info("restore.begin — awaiting AppStore.sync() (Apple authentication prompt may present)")

        var syncSucceeded = false
        var cancelled = false
        do {
            try await AppStore.sync()
            syncSucceeded = true
            Self.log.info("restore.syncCompleted — refreshing verified entitlements")
        } catch {
            cancelled = Self.isSyncCancellation(error)
            Self.log.error("restore.syncFailed cancelled \(cancelled) error \(error.localizedDescription, privacy: .public)")
        }

        // Entitlements are refreshed ONLY after a completed sync.
        // `refreshVerified` distinguishes a refresh that genuinely
        // read Apple's data from one that could not — the latter
        // must surface as verificationFailed, never as a success
        // or as "no purchases".
        var refreshVerified = false
        if syncSucceeded {
            refreshVerified = await refreshEntitlements()
        }

        let outcome = RestoreOutcomeResolver.resolve(
            syncSucceeded: syncSucceeded,
            cancelled: cancelled,
            refreshVerified: refreshVerified,
            accessState: accessState)
        restoreOutcome = outcome
        Self.log.info("restore.finished outcome \(String(describing: outcome), privacy: .public) access \(self.accessDescription, privacy: .public)")
    }

    /// Whether an error thrown by `AppStore.sync()` represents the
    /// user cancelling Apple's authentication prompt rather than a
    /// genuine failure. Cancellation leaves any existing access
    /// untouched and is reported as its own outcome.
    private static func isSyncCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let storeKitError = error as? StoreKitError,
           case .userCancelled = storeKitError { return true }
        let nsError = error as NSError
        return nsError.domain == SKErrorDomain
            && nsError.code == SKError.Code.paymentCancelled.rawValue
    }

    /// Rebuilds the access decision from Apple-verified data only.
    /// Called at launch, on foreground return (ContentView), after
    /// purchases and restores, and for every transaction update
    /// (renewals, trial conversion, expiry, revocation, billing
    /// state changes).
    ///
    /// Returns whether the refreshed picture is VERIFIED. It is
    /// false only when the subscription-status read failed AND no
    /// verified entitlement could be read from
    /// `Transaction.currentEntitlements` either — in that case "no
    /// purchases" and "could not read Apple's data" are
    /// indistinguishable, and a caller reporting an outcome
    /// (Restore Purchases) must claim neither. The access decision
    /// itself is computed exactly as before; other callers may
    /// ignore the result.
    @discardableResult
    func refreshEntitlements() async -> Bool {
        var snapshots: [SubscriptionEntitlementSnapshot] = []
        var seen: Set<String> = []
        var statusReadFailed = false

        // Richest signal first: the subscription group's statuses
        // carry the renewal info (grace period, billing retry,
        // auto-renew) alongside each verified transaction.
        do {
            let statuses = try await Product.SubscriptionInfo.status(for: AppConfig.subscriptionGroupID)
            for status in statuses {
                guard let transaction = try? checkVerified(status.transaction) else { continue }
                snapshots.append(snapshot(for: transaction, status: status))
                seen.insert(transaction.productID)
            }
        } catch {
            statusReadFailed = true
            Self.log.error("entitlements.statusReadFailed error \(error.localizedDescription, privacy: .public) — falling back to currentEntitlements only")
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
        // Verified when the status read succeeded, or when verified
        // entitlements were actually read despite its failure.
        return !statusReadFailed || !snapshots.isEmpty
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
