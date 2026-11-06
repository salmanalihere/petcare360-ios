import SwiftUI
import StoreKit

/// What the paywall body should show, derived from the store's real
/// state. Pure and testable: loading (first load in flight), content
/// (products available), empty (load finished, Apple returned NO
/// products for this app/Apple ID — e.g. subscriptions not yet
/// created in App Store Connect), failed (the fetch threw).
enum PaywallDisplayState: Equatable {
    case loading
    case content
    case empty
    case failed(String)

    static func resolve(isLoading: Bool, hasAttemptedLoad: Bool, productCount: Int, loadError: String?) -> PaywallDisplayState {
        if productCount > 0 { return .content }
        if isLoading || !hasAttemptedLoad { return .loading }
        if let loadError { return .failed(loadError) }
        return .empty
    }
}

/// Savings maths over REAL StoreKit prices only. Returns a whole
/// percent (e.g. 50 for "save 50%") or nil when there is no saving
/// to claim — the paywall never invents a discount.
enum PremiumPricing {
    static func yearlySavingsPercent(monthlyPrice: Decimal, yearlyPrice: Decimal) -> Int? {
        guard monthlyPrice > 0, yearlyPrice > 0 else { return nil }
        let twelveMonths = monthlyPrice * 12
        guard yearlyPrice < twelveMonths else { return nil }
        let fraction = 1 - (yearlyPrice / twelveMonths)
        let percent = Int((NSDecimalNumber(decimal: fraction).doubleValue * 100).rounded())
        return percent > 0 ? percent : nil
    }
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
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

    private var yearlySavings: Int? {
        guard let monthly = store.products.first(where: { $0.id == PremiumProduct.monthly }),
              let yearly = store.products.first(where: { $0.id == PremiumProduct.yearly }) else { return nil }
        return PremiumPricing.yearlySavingsPercent(monthlyPrice: monthly.price, yearlyPrice: yearly.price)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if store.trial.isActive {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Free trial — \(store.trial.daysRemaining) day\(store.trial.daysRemaining == 1 ? "" : "s") left", systemImage: "gift.fill")
                                .font(.headline).foregroundStyle(PCColor.deepTeal)
                            Text("You already have full Premium access until \(store.trial.endsAt?.formatted(date: .abbreviated, time: .omitted) ?? ""). Subscribing now starts billing when you confirm — the trial itself never charges you.")
                                .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                        }
                        .pcCard()
                    } else if !store.isPremium, case .expired = store.trial.state {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your 7-day free trial has ended")
                                .font(.headline).foregroundStyle(PCColor.deepTeal)
                            Text("Subscribe to keep the Premium features. Your pets, records and documents are all still here — nothing was deleted, and viewing, editing and exporting what you already have is never locked.")
                                .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                        }
                        .pcCard()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unlock More. Care Better. Love More.")
                            .font(.title.bold()).foregroundStyle(PCColor.charcoal)
                        Text("Give every pet the care they deserve with unlimited possibilities.")
                            .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(PremiumFeature.paywallFeatures, id: \.self) { feature in
                            Label(feature.label, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(PCColor.charcoal)
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline)
                                .accessibilityLabel(feature.label)
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
                        Text("Membership plans are not available right now. This usually means the subscriptions are still being set up for this app, or the store cannot be reached from this device. Nothing has been charged.")
                            .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                        Button("Retry") { Task { await store.loadProducts() } }
                            .font(.subheadline.bold())
                    case .content:
                        ForEach(store.products) { product in
                            productCard(product)
                        }
                        if let selected = selectedProduct {
                            PCPrimaryButton(title: isPurchasing ? "Processing…" : "Go Premium") {
                                Task {
                                    isPurchasing = true
                                    await store.purchase(selected)
                                    isPurchasing = false
                                }
                            }
                            .disabled(isPurchasing)
                            .accessibilityLabel("Go Premium, \(selected.displayName), \(selected.displayPrice) \(periodText(for: selected))")
                            Text("Payment is charged to your Apple ID at confirmation. \(selected.displayName) renews automatically at \(selected.displayPrice) \(periodText(for: selected)) unless cancelled at least 24 hours before the end of the current period. Manage or cancel anytime in your Apple ID subscription settings.")
                                .font(.caption).foregroundStyle(PCColor.secondaryText)
                        }
                    }
                    if let error = store.purchaseError {
                        Text(error).font(.subheadline).foregroundStyle(PCColor.errorRed)
                    }
                    if let info = store.infoMessage {
                        Text(info).font(.subheadline).foregroundStyle(PCColor.secondaryText)
                    }
                    HStack(spacing: 16) {
                        Button("Restore Purchases") { Task { await store.restorePurchases() } }
                        Link("Privacy Policy", destination: AppConfig.privacyPolicyURL)
                        Link("Terms of Use", destination: AppConfig.termsOfUseURL)
                    }
                    .font(.subheadline)
                    Text("Free plan: one pet, basic care reminders, basic medication tracking, basic medical records, limited document storage and the basic health timeline — plus the emergency screen, always free.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                }
                .padding()
            }
            .background(PCColor.warmIvory)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: store.isPremium) { _, premium in
                // A successful purchase (here or finishing elsewhere)
                // returns the user straight to what they were doing;
                // the presenting screen resumes its pending action.
                if premium { dismiss() }
            }
        }
    }

    private func productCard(_ product: Product) -> some View {
        Button { selectedID = product.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(product.displayName).font(.headline).foregroundStyle(PCColor.charcoal)
                        if product.id == PremiumProduct.yearly, let savings = yearlySavings {
                            Text("Save \(savings)%")
                                .font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(PCColor.freshGreen).clipShape(Capsule())
                        }
                    }
                    Text(periodText(for: product).capitalized)
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
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
        case .month: return period.value == 1 ? "per month" : "per \(period.value) months"
        case .year: return period.value == 1 ? "per year" : "per \(period.value) years"
        case .week: return period.value == 1 ? "per week" : "per \(period.value) weeks"
        case .day: return period.value == 1 ? "per day" : "per \(period.value) days"
        @unknown default: return ""
        }
    }
}
