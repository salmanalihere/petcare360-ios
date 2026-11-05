import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: StoreManager
    @State private var selectedID: String = PremiumProduct.yearly

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PetCare 360 Premium").font(.title.bold()).foregroundStyle(PCColor.charcoal)
                        Text(AppConfig.tagline).font(.subheadline).foregroundStyle(PCColor.secondaryText)
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

                    if store.products.isEmpty {
                        if store.isLoading { ProgressView("Loading subscription options…") }
                        else {
                            Text("Subscription options could not be loaded. Please check your connection and try again.")
                                .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                            Button("Try Again") { Task { await store.loadProducts() } }
                        }
                    } else {
                        ForEach(store.products) { product in
                            Button { selectedID = product.id } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(product.displayName).font(.headline).foregroundStyle(PCColor.charcoal)
                                        Text(product.id == PremiumProduct.yearly ? "Per year" : "Per month")
                                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                                    }
                                    Spacer()
                                    Text(product.displayPrice).font(.headline).foregroundStyle(PCColor.deepTeal)
                                    Image(systemName: selectedID == product.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(PCColor.freshGreen)
                                }
                                .pcCard()
                            }
                        }
                        if let selected = store.products.first(where: { $0.id == selectedID }) {
                            PCPrimaryButton(title: "Subscribe — \(selected.displayPrice)") {
                                Task { await store.purchase(selected) }
                            }
                        }
                        Text("Target US prices: \(PremiumProduct.targetPrices[PremiumProduct.monthly] ?? "")/month and \(PremiumProduct.targetPrices[PremiumProduct.yearly] ?? "")/year. The price shown on the button is the live App Store price. Payment is charged to your Apple ID at confirmation. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period, and can be managed in your Apple ID settings.")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                    if let error = store.purchaseError {
                        Text(error).font(.subheadline).foregroundStyle(PCColor.errorRed)
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
        }
    }
}
