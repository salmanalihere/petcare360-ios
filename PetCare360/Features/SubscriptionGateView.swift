import SwiftUI
import StoreKit

/// Shown briefly at cold start while StoreManager reads the
/// verified entitlements. Neither the app nor the subscription
/// gate is shown on an unresolved state.
struct SubscriptionCheckingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(PCColor.deepTeal)
            Text("PetCare 360")
                .font(.title2.bold()).foregroundStyle(PCColor.charcoal)
            ProgressView()
            Text("Checking your subscription…")
                .font(.subheadline).foregroundStyle(PCColor.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PCColor.warmIvory)
    }
}

/// The mandatory subscription screen of the subscription-only
/// model (2026-11-08). ContentView shows it INSTEAD of the whole
/// app whenever there is no active Apple subscription entitlement
/// — there is no close button and no way around it. Starting a
/// plan goes through Apple's own purchase confirmation sheet,
/// which applies the introductory 7-day free trial automatically
/// when App Store Connect offers one and this Apple ID is
/// eligible. Restore Purchases, subscription management, and the
/// legal links stay available here, as required while locked.
struct SubscriptionGateView: View {
    @EnvironmentObject private var store: StoreManager
    @State private var selectedID: String = PremiumProduct.yearly
    @State private var isPurchasing = false

    private var displayState: PaywallDisplayState {
        PaywallDisplayState.resolve(isLoading: store.isLoading,
                                    hasAttemptedLoad: store.hasAttemptedLoad,
                                    productCount: store.products.count,
                                    loadError: store.loadError)
    }

    private var selectedProduct: Product? {
        store.products.first(where: { $0.id == selectedID }) ?? store.products.first
    }

    private var selectedOffersTrial: Bool {
        guard let selectedProduct else { return false }
        return store.offersFreeTrial(selectedProduct)
    }

    private var hasBillingIssue: Bool {
        if case .inactive(let billingIssue) = store.accessState { return billingIssue }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "pawprint.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(PCColor.deepTeal)
                    Text("PetCare 360 is subscription-only")
                        .font(.title.bold()).foregroundStyle(PCColor.charcoal)
                    Text("An active subscription unlocks the complete app — every pet, record, reminder and family feature. There is no free plan.")
                        .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                }

                if hasBillingIssue {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Billing problem with your subscription", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline).foregroundStyle(PCColor.errorRed)
                        Text("Apple could not collect payment, so your subscription is paused. Update your payment method in your Apple ID subscription settings to restore access — your data is untouched.")
                            .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                    }
                    .pcCard()
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(PremiumFeature.paywallFeatures, id: \.self) { feature in
                        Label(feature.label, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(PCColor.charcoal)
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                    }
                }
                .pcCard()

                switch displayState {
                case .loading:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading membership plans…")
                            .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                    }
                    .accessibilityLabel("Loading membership plans")
                case .failed(let message):
                    Text(message)
                        .font(.subheadline).foregroundStyle(PCColor.errorRed)
                    Button("Retry") { Task { await store.loadProducts() } }
                        .font(.subheadline.bold())
                case .empty:
                    Text("Membership plans are not available right now. This usually means the store cannot be reached from this device. Nothing has been charged.")
                        .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                    Button("Retry") { Task { await store.loadProducts() } }
                        .font(.subheadline.bold())
                case .content:
                    ForEach(store.products) { product in
                        productCard(product)
                    }
                    if let selected = selectedProduct {
                        PCPrimaryButton(title: isPurchasing ? "Processing…" : (selectedOffersTrial ? "Start 7-Day Free Trial" : "Subscribe")) {
                            Task {
                                isPurchasing = true
                                await store.purchase(selected)
                                isPurchasing = false
                            }
                        }
                        .disabled(isPurchasing)
                        .accessibilityLabel("\(selectedOffersTrial ? "Start 7-day free trial" : "Subscribe"), \(selected.displayName), \(selected.displayPrice) \(periodText(for: selected))")
                        if selectedOffersTrial {
                            Text("Free for 7 days, then \(selected.displayPrice) \(periodText(for: selected)), charged to your Apple ID unless you cancel before the trial ends. The subscription renews automatically; cancel anytime in your Apple ID subscription settings and you keep access until the end of the paid period.")
                                .font(.caption).foregroundStyle(PCColor.secondaryText)
                        } else {
                            Text("\(selected.displayPrice) \(periodText(for: selected)), charged to your Apple ID at confirmation. The subscription renews automatically unless cancelled at least 24 hours before the end of the current period. Cancel anytime in your Apple ID subscription settings and you keep access until the end of the paid period.")
                                .font(.caption).foregroundStyle(PCColor.secondaryText)
                        }
                    }
                }

                if let error = store.purchaseError {
                    Text(error).font(.subheadline).foregroundStyle(PCColor.errorRed)
                }
                if let info = store.infoMessage {
                    Text(info).font(.subheadline).foregroundStyle(PCColor.secondaryText)
                }
                if let outcome = store.restoreOutcome {
                    Text(outcome.message).font(.subheadline)
                        .foregroundStyle(outcome.isFailure ? PCColor.errorRed : PCColor.secondaryText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Button { Task { await store.restorePurchases() } } label: {
                        HStack(spacing: 6) {
                            if store.isRestoring { ProgressView().controlSize(.small) }
                            Text(store.isRestoring ? "Restoring..." : "Restore Purchases")
                        }
                    }
                    .disabled(store.isRestoring)
                        .font(.subheadline.bold())
                    Link("Manage Subscription", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
                        .font(.subheadline)
                    HStack(spacing: 16) {
                        Link("Privacy Policy", destination: AppConfig.privacyPolicyURL)
                        Link("Terms of Use", destination: AppConfig.termsOfUseURL)
                    }
                    .font(.subheadline)
                }

                Text("Your pets, records and settings are stored safely on this device and will be exactly as you left them when your subscription is active. Nothing is deleted while the app is locked.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
            .padding()
        }
        .background(PCColor.warmIvory)
    }

    private func productCard(_ product: Product) -> some View {
        Button { selectedID = product.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.headline).foregroundStyle(PCColor.charcoal)
                    if store.offersFreeTrial(product) {
                        Text("7-day free trial, then \(product.displayPrice) \(periodText(for: product))")
                            .font(.caption).foregroundStyle(PCColor.freshGreen)
                    } else {
                        Text(periodText(for: product).capitalized)
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                }
                Spacer()
                Text(product.displayPrice).font(.headline).foregroundStyle(PCColor.deepTeal)
                Image(systemName: selectedID == product.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(PCColor.freshGreen)
            }
            .pcCard()
        }
        .accessibilityLabel("\(product.displayName), \(product.displayPrice) \(periodText(for: product))")
    }

    /// Billing period from the product's REAL subscription data,
    /// never from a hardcoded string.
    private func periodText(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return period.value == 1 ? "per day" : "every \(period.value) days"
        case .week: return period.value == 1 ? "per week" : "every \(period.value) weeks"
        case .month: return period.value == 1 ? "per month" : "every \(period.value) months"
        case .year: return period.value == 1 ? "per year" : "every \(period.value) years"
        @unknown default: return ""
        }
    }
}
