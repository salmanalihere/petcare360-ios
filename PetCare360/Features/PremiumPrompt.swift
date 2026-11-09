import SwiftUI

/// The one premium-restriction prompt used everywhere (brief
/// 2026-11-06): a clear explanation, a prominent Upgrade action that
/// opens the paywall, and a Not Now action that changes nothing. No
/// premium gate in the app shows an OK-only alert any more.
struct PremiumPrompt {
    let title: String
    let message: String

    static let addPet = PremiumPrompt(
        title: "Unlock More for Your Pets!",
        message: "Your free plan includes one pet profile. Upgrade to PetCare 360 Premium to add more pets and manage your entire furry family.")

    static let restorePet = PremiumPrompt(
        title: "Unlock More for Your Pets!",
        message: "Your free plan includes one active pet profile, and this archived pet would be a second one. Upgrade to PetCare 360 Premium to restore it — your archived pet and its records are kept safe either way.")

    static let householdMembers = PremiumPrompt(
        title: "Care Together with Premium",
        message: "Adding household members is a PetCare 360 Premium feature. Upgrade to organise owners, family, sitters and walkers for your pets.")

    static let documentStorage = PremiumPrompt(
        title: "Document Storage Is a Premium Feature",
        message: "Storing documents with your pets' records is part of PetCare 360 Premium. Upgrade to keep vaccination certificates, lab results and other documents organised with each pet.")

    static let premiumFeature = PremiumPrompt(
        title: "A Premium Feature",
        message: "This is a PetCare 360 Premium feature. Your existing records stay fully visible, editable and deletable on the free plan — upgrading unlocks creating and exporting with this feature.")

    static let savedBrands = PremiumPrompt(
        title: "Recall Tracking Is Premium",
        message: "Saving brands to watch for recalls is a PetCare 360 Premium feature. Upgrade to track the brands your pets eat.")
}

extension View {
    /// Presents the standard premium prompt. `onUpgrade` should open
    /// the paywall (usually by setting the view's paywall sheet state).
    func premiumUpgradePrompt(isPresented: Binding<Bool>, prompt: PremiumPrompt, onUpgrade: @escaping () -> Void) -> some View {
        alert(prompt.title, isPresented: isPresented) {
            Button("Upgrade to Premium") { onUpgrade() }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text(prompt.message)
        }
    }
}
