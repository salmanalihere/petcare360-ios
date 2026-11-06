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

    /// Storage opening ladder (build 13 recovery design):
    /// 1. CloudKit-backed store (when enabled in AppConfig).
    /// 2. Local store at the same default location.
    /// 3. ONE-TIME automatic recovery per store generation: if both
    ///    opens failed, the local store files are removed and the
    ///    local open is retried exactly once. The attempt is marked
    ///    BEFORE the retry, so a persistent failure can never loop.
    /// 4. Otherwise the error screen, with BOTH underlying errors
    ///    shown (build 12 swallowed the CloudKit error, which made
    ///    the on-device failure undiagnosable).
    /// There is no in-memory fallback at any step.
    private static func openStorage() -> StorageState {
        let schema = appSchema()
        var errors: [String] = []
        if AppConfig.cloudKitSyncEnabled {
            let cloud = ModelConfiguration(
                schema: schema, cloudKitDatabase: .private(AppConfig.iCloudContainerID))
            do {
                return .ready(try ModelContainer(for: schema, configurations: [cloud]))
            } catch {
                errors.append("iCloud store: \(error.localizedDescription)")
            }
        }
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return .ready(try ModelContainer(for: schema, configurations: [local]))
        } catch {
            errors.append("Local store: \(error.localizedDescription)")
        }
        // Step 3 — bounded one-time recovery. Owner confirmed
        // 2026-11-06 that all existing records are demo/test data.
        let generation = StoreRecoveryLedger.currentGeneration()
        if StoreRecoveryPolicy.shouldWipeAndRetry(
            openFailed: true,
            recoveryAttemptedGeneration: StoreRecoveryLedger.recoveryAttemptedGeneration(),
            currentGeneration: generation) {
            StoreRecoveryLedger.markRecoveryAttempted(for: generation)
            StoreFileWiper.wipeStoreFiles(at: local.url)
            do {
                return .ready(try ModelContainer(for: schema, configurations: [local]))
            } catch {
                errors.append("After one-time reset: \(error.localizedDescription)")
                errors.append("A one-time database reset was performed and the store still could not be opened.")
            }
        }
        return .failed(errors.joined(separator: "\n"))
    }

    /// Manual reset from the storage-error screen: starts a new
    /// store generation, removes the local store files, and reopens.
    /// The ONLY way a second wipe can happen — always user-initiated.
    private static func resetAndReopen() -> StorageState {
        StoreRecoveryLedger.beginNewGeneration()
        let local = ModelConfiguration(schema: appSchema(), isStoredInMemoryOnly: false)
        StoreFileWiper.wipeStoreFiles(at: local.url)
        return openStorage()
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
            case .failed(let message):
                StorageErrorView(message: message,
                                 onRetry: { storage = Self.openStorage() },
                                 onReset: { storage = Self.resetAndReopen() })
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
    let onReset: () -> Void
    @State private var confirmingReset = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(PCColor.errorRed)
            Text("PetCare 360 couldn't open its stored data")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("The app couldn't open its database, so saving new information isn't possible right now. Tap Try Again first. If it keeps failing, you can reset the database — that deletes the local copy of your PetCare data on this device and starts fresh. Anything already synced to your iCloud account is not touched by a reset.")
                .font(.subheadline)
                .foregroundStyle(PCColor.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try Again") { onRetry() }
                .buttonStyle(.borderedProminent)
                .tint(PCColor.freshGreen)
            Button("Reset Database", role: .destructive) { confirmingReset = true }
                .buttonStyle(.bordered)
                .confirmationDialog("Reset the database?",
                                    isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    Button("Delete Local Data and Restart Fresh", role: .destructive) { onReset() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes the PetCare database stored on this device. Data in your iCloud account is not deleted.")
                }
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
