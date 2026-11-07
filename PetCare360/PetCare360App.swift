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
        Self.resetAppLocalStateForUITestingIfRequested()
        _storage = State(initialValue: Self.openStorage())
    }

    /// UI-TESTING ONLY state reset (2026-11-08). The UI tests pass
    /// `-uiTesting -uiTestingResetState` on every launch; when —
    /// and only when — BOTH arguments are present, the app's local
    /// state is wiped BEFORE the store is opened: the SwiftData
    /// store files (which carry the UserProfile whose
    /// `hasCompletedOnboarding` flag decides onboarding vs. the
    /// subscription gate at launch) and the app's UserDefaults
    /// domain (sound/notification preferences, recovery ledger).
    ///
    /// Why this exists: UI test methods relaunch the SAME install,
    /// so without a reset one test's completed onboarding leaked
    /// into the next test, which then launched straight into the
    /// subscription gate while its setup waited for onboarding
    /// controls that could never appear. Every UI test now starts
    /// from the true first-launch state.
    ///
    /// Safety: normal launches never carry these arguments, so
    /// production behavior is unchanged. This does NOT touch
    /// subscription enforcement — access still comes only from
    /// verified StoreKit entitlements — and it cannot clear
    /// StoreKit transactions (no app-side API exists); the
    /// Codemagic full-tests workflow additionally uninstalls the
    /// app before every UI test so the local StoreKit environment
    /// starts empty too.
    private static func resetAppLocalStateForUITestingIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-uiTesting"),
              arguments.contains("-uiTestingResetState") else { return }
        StoreFileWiper.wipeStoreFiles(at: localConfiguration(schema: appSchema()).url)
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
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

    /// The explicit LOCAL configuration used by every fallback path.
    ///
    /// `cloudKitDatabase: .none` is load-bearing — do not remove it.
    /// ModelConfiguration's cloudKitDatabase defaults to `.automatic`,
    /// which engages CloudKit mirroring whenever the app binary is
    /// entitled for iCloud. Since build 12 wired the CloudKit
    /// entitlement into the signed app, an `.automatic` "local"
    /// fallback on a real device runs the SAME CloudKit schema
    /// validation as the primary configuration — and fails it
    /// identically ("CloudKit integration requires that all
    /// relationships be optional", Codemagic diagnostic build 4,
    /// test C). That is why BOTH configurations threw
    /// SwiftDataError 1 on device, even on a fresh install, while
    /// the unsigned simulator tests (no entitlement in effect)
    /// passed. `.none` makes this configuration local by
    /// construction, independent of entitlements.
    static func localConfiguration(schema: Schema, url: URL? = nil) -> ModelConfiguration {
        if let url {
            return ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        return ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none)
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
                errors.append(StorageDiagnostics.describe(error, prefix: "iCloud store:"))
            }
        }
        let local = localConfiguration(schema: schema)
        do {
            return .ready(try ModelContainer(for: schema, configurations: [local]))
        } catch {
            errors.append(StorageDiagnostics.describe(error, prefix: "Local store:"))
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
                errors.append(StorageDiagnostics.describe(error, prefix: "After one-time reset:"))
                errors.append("A one-time database reset was performed and the store still could not be opened.")
            }
        }
        return .failed(errors.joined(separator: "\n"))
    }

    /// Manual reset from the storage-error screen: starts a new
    /// store generation, removes the local store files, and reopens.
    /// The ONLY way a second wipe can happen — always user-initiated.
    private static func resetAndReopen() -> StorageState {
        let generation = StoreRecoveryLedger.beginNewGeneration()
        let local = localConfiguration(schema: appSchema())
        StoreFileWiper.wipeStoreFiles(at: local.url)
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        switch openStorage() {
        case .ready(let container):
            return .ready(container)
        case .failed(let message):
            return .failed("Reset ran at \(stamp) (store generation \(generation)): local database files were removed and reopening was retried. It still failed — the problem is not the database files. Full error:\n" + message)
        }
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
    @State private var isWorking = false

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
            if isWorking {
                ProgressView("Working…")
            }
            Button("Try Again") {
                isWorking = true
                Task { await Task.yield(); onRetry() }
            }
            .buttonStyle(.borderedProminent)
            .tint(PCColor.freshGreen)
            .disabled(isWorking)
            Button("Reset Database", role: .destructive) { confirmingReset = true }
                .buttonStyle(.bordered)
                .confirmationDialog("Reset the database?",
                                    isPresented: $confirmingReset,
                                    titleVisibility: .visible) {
                    Button("Delete Local Data and Restart Fresh", role: .destructive) {
                        isWorking = true
                        Task { await Task.yield(); onReset() }
                    }
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
