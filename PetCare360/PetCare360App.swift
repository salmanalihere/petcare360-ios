import SwiftUI
import SwiftData

@main
struct PetCare360App: App {
    /// Storage opening result. There is deliberately NO silent in-memory
    /// fallback (v1.2.2 audit correction): if the persistent store cannot
    /// be opened, the user sees a clear, recoverable error screen and the
    /// existing database file is left completely untouched.
    private enum StorageState {
        case ready(ModelContainer)
        case failed(String)
    }

    @State private var storage: StorageState

    init() {
        _storage = State(initialValue: Self.openStorage())
    }

    static func appSchema() -> Schema {
        Schema([
            UserProfile.self, Household.self, HouseholdMember.self,
            Pet.self, Medication.self, MedicationSchedule.self, MedicationAdministration.self,
            CareTask.self, CareHandoff.self,
            VaccinationRecord.self, MedicalRecord.self, MedicalDocument.self,
            VetAppointment.self, HealthObservation.self,
            PetExpense.self, InsurancePolicy.self, InsuranceClaim.self,
            FoodSchedule.self, FeedingLog.self, RecallAlert.self, SavedFoodBrand.self,
            EmergencyProfile.self, SubscriptionEntitlement.self
        ])
    }

    /// Builds a container for an explicit configuration. Exposed so tests
    /// can exercise the success path without touching the real store.
    static func makeContainer(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: appSchema(), configurations: [configuration])
    }

    private static func openStorage() -> StorageState {
        let schema = appSchema()
        // CloudKit is attempted ONLY when the owner has completed the
        // Developer setup AND flipped AppConfig.cloudKitSyncEnabled.
        // It is never activated automatically (v1.2.2 audit rule).
        if AppConfig.cloudKitSyncEnabled {
            let cloud = ModelConfiguration(
                schema: schema, cloudKitDatabase: .private(AppConfig.iCloudContainerID))
            if let container = try? ModelContainer(for: schema, configurations: [cloud]) {
                return .ready(container)
            }
        }
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return .ready(try ModelContainer(for: schema, configurations: [local]))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
            case .failed(let message):
                StorageErrorView(message: message) {
                    storage = Self.openStorage()
                }
            }
        }
    }
}

/// Shown when the persistent store cannot be opened. Explains the
/// situation honestly — existing data is preserved but new data cannot
/// be saved — and offers a retry instead of crashing or silently
/// dropping the user into a throwaway in-memory database.
struct StorageErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(PCColor.errorRed)
            Text("PetCare 360 couldn't open its stored data")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Your existing data has NOT been deleted — the app just couldn't open its database this time. Saving new information isn't possible until storage opens again.\n\nTap Try Again, and if it keeps failing, restart your device. If the problem continues, contact support.")
                .font(.subheadline)
                .foregroundStyle(PCColor.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try Again") { onRetry() }
                .buttonStyle(.borderedProminent)
                .tint(PCColor.freshGreen)
            Text(message)
                .font(.caption2)
                .foregroundStyle(PCColor.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PCColor.warmIvory)
    }
}
