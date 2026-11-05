import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var page = 0
    @State private var ownerName = ""
    @State private var errorMessage = "" 

    private let pages: [(String, String, String)] = [
        ("pawprint.fill", "Welcome to PetCare 360", "A healthier life together. Every record, medication and care task for your pets, in one private place."),
        ("pills.fill", "Never miss a medication", "A shared administration log shows who gave each dose and when — so a dose is never given twice."),
        ("folder.fill", "A medical passport for every pet", "Vaccinations, records and documents, organised and ready to share with your veterinarian as a PDF."),
        ("person.3.fill", "Care together", "Household members, sitters and walkers are organised in one place on this device, with structured handoffs after every visit."),
        ("bell.fill", "Gentle, useful reminders", "Medication, feeding, vaccination and refill reminders. We only ask for notification permission when you turn reminders on.")
    ]

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 20) {
                        Image(systemName: item.0)
                            .font(.system(size: 64))
                            .foregroundStyle(PCColor.freshGreen)
                            .accessibilityHidden(true)
                        Text(item.1).font(.title.bold()).foregroundStyle(PCColor.charcoal)
                            .multilineTextAlignment(.center)
                        Text(item.2).font(.body).foregroundStyle(PCColor.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page)
            if page == pages.count - 1 {
                VStack(spacing: 12) {
                    TextField("Your name", text: $ownerName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, 24)
                    PCPrimaryButton(title: "Get Started") { finish() }
                        .padding(.horizontal, 24)
                    if !errorMessage.isEmpty {
                        Text(errorMessage).font(.subheadline).foregroundStyle(PCColor.errorRed)
                            .multilineTextAlignment(.center).padding(.horizontal, 24)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(PCColor.warmIvory)
    }

    private func finish() {
        let profile = UserProfile(displayName: ownerName)
        profile.hasCompletedOnboarding = true
        context.insert(profile)
        let household = Household()
        context.insert(household)
        let owner = HouseholdMember(displayName: ownerName.isEmpty ? "Owner" : ownerName, role: .owner)
        owner.isInvitationPending = false
        owner.household = household
        context.insert(owner)
        profile.memberID = owner.id   // link stable identity at creation (Phase 2)
        do {
            try context.save()
        } catch {
            // Never leave a half-created household/profile behind and
            // never proceed as if onboarding completed (v1.2.6).
            context.rollback()
            errorMessage = "Your profile could not be saved on this device. Nothing was set up — please try again."
        }
    }
}
