import SwiftUI
import SwiftData

struct ContentView: View {
    @Query private var profiles: [UserProfile]
    @Query private var allPets: [Pet]
    @Query private var allSchedules: [MedicationSchedule]
    @Query private var allPolicies: [InsurancePolicy]
    @State private var didInitialReminderSync = false
    @State private var showTrialExpiredPaywall = false
    @State private var didPresentTrialExpired = false
    @StateObject private var store = StoreManager()
    @Environment(\.scenePhase) private var scenePhase

    private var hasOnboarded: Bool { profiles.first?.hasCompletedOnboarding ?? false }

    var body: some View {
        Group {
            if hasOnboarded {
                TabView {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "house") }
                    PetsView()
                        .tabItem { Label("Pets", systemImage: "pawprint") }
                    CareView()
                        .tabItem { Label("Care", systemImage: "heart.text.square") }
                    RecordsView()
                        .tabItem { Label("Records", systemImage: "folder") }
                    FamilyView()
                        .tabItem { Label("Family", systemImage: "person.3") }
                }
                .tint(PCColor.deepTeal)
            } else {
                OnboardingView()
            }
        }
        .environmentObject(store)
        .background(PCColor.warmIvory)
        .sheet(isPresented: $showTrialExpiredPaywall) { PaywallView().environmentObject(store) }
        .onAppear {
            // Trial expired (2026-11-07): show the subscription
            // screen ONCE per launch. It is dismissible and locks
            // nothing — the free plan keeps working underneath.
            if hasOnboarded, !didPresentTrialExpired,
               case .expired = store.trial.state, !store.isPremium {
                didPresentTrialExpired = true
                showTrialExpiredPaywall = true
            }
        }
        .onAppear {
            // Initial-launch replenishment (v1.2.3): scenePhase changes
            // cover foreground returns, but the first launch is handled
            // explicitly here. The pass is idempotent (stale requests are
            // removed, identifiers are deterministic), and the flag stops
            // the launch-time scenePhase event from running it twice.
            guard !didInitialReminderSync else { return }
            didInitialReminderSync = true
            syncReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            // Subscription state can change while the app is away (renewal,
            // expiry, revocation, restore on another device). Re-read the
            // verified StoreKit entitlements whenever we come back.
            if phase == .active {
                Task { await store.refreshEntitlements() }
                // Rolling reminder replenishment: rebuild the next 7 days
                // of medication reminders every time the app comes to the
                // foreground (v1.2.2 — no editor visit required).
                syncReminders()
            }
        }
    }

    /// One idempotent reminder-sync entry point used by initial launch
    /// and every foreground return: rebuilds the next 7 days of dose
    /// reminders for eligible medications (global setting + each
    /// medication's own preference both respected).
    private func syncReminders() {
        // Centralized, serialized synchronization (v1.2.5): launch and
        // foreground passes can never interleave.
        NotificationService.shared.synchronizeReminders(
            pets: allPets, schedules: allSchedules, policies: allPolicies,
            remindersEnabled: profiles.first?.remindersEnabled ?? false)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct PDFShareButton: View {
    let title: String
    let makePDF: () -> Data
    @State private var showShare = false
    @State private var pdfData: Data? = nil
    var body: some View {
        Button(title) {
            pdfData = makePDF()
            showShare = true
        }
        .sheet(isPresented: $showShare) {
            if let pdfData { ShareSheet(items: [pdfData]) }
        }
    }
}

struct PetAvatar: View {
    let pet: Pet
    var size: CGFloat = 56
    var body: some View {
        Group {
            if let data = pet.photoData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(PCColor.freshGreen.opacity(0.15))
                    Image(systemName: pet.species.icon)
                        .foregroundStyle(PCColor.deepTeal)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("\(pet.name), \(pet.species.label)")
    }
}

import PDFKit

/// Read-only PDF preview used before sharing an export.
struct PDFKitView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = PDFDocument(data: data)
        view.autoScales = true
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.dataRepresentation() != data {
            view.document = PDFDocument(data: data)
        }
    }
}
