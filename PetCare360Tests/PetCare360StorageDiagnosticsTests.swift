import XCTest
import SwiftData
@testable import PetCare360

/// Build-13 storage-failure DIAGNOSTICS (not regression tests).
/// Purpose: bisect WHY ModelContainer creation throws
/// SwiftDataError 1 on the owner's iPhone (iOS 26.5.2) even on a
/// fresh install, for BOTH CloudKit and local configurations.
///
/// Container discipline: every create/save step runs in its own
/// scope and the container reference is explicitly released
/// BEFORE the same store is reopened, so the reopen genuinely
/// exercises on-disk persistence (no two live containers ever
/// share one store file in these tests).
///
/// HOW TO READ THE RESULTS (real iPhone or Mac/simulator):
/// - A fails  -> environmental (OS/toolchain/store location).
/// - A passes, B fails -> app model/schema defect; D groups bisect.
/// - A + B pass -> configuration/default-location difference;
///   test E compares exactly that, and C's chain covers CloudKit.
/// NOTHING here touches the app's real store except test E's
/// default-location probe, which cleans up after itself and is
/// intended for the disposable simulator/test environment only.
@Model
final class DiagnosticPet {
    var id: UUID = UUID()
    var name: String = ""
    init(name: String = "") { self.id = UUID(); self.name = name }
}

@MainActor
final class PetCare360StorageDiagnosticsTests: XCTestCase {

    private func tempStoreURL(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pc360-diag-\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.appendingPathComponent("store.sqlite")
    }

    private func describeChain(_ error: Error) -> String {
        StorageDiagnostics.describe(error, prefix: "DIAGNOSTIC")
    }

    /// Create a container, run `work`, then FULLY release the
    /// container (and its context) before returning — the caller
    /// may then reopen the same store safely.
    private func createAndRelease(schema: Schema, config: ModelConfiguration,
                                  work: (ModelContext) throws -> Void = { _ in }) throws {
        var container: ModelContainer? = try ModelContainer(for: schema, configurations: [config])
        do {
            let context = ModelContext(container!)
            try work(context)
        }
        container = nil
    }

    private func reopen(schema: Schema, config: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: A — minimal schema, local

    func testA_MinimalSchemaLocalCreateSaveReopen() throws {
        let url = try tempStoreURL("A")
        let schema = Schema([DiagnosticPet.self])
        let config = ModelConfiguration(schema: schema, url: url)
        do {
            try createAndRelease(schema: schema, config: config) { ctx in
                ctx.insert(DiagnosticPet(name: "diag"))
                try ctx.save()
            }
        } catch {
            XCTFail("A failed — environmental failure, not app models:\n\(describeChain(error))")
            return
        }
        let reopened = try reopen(schema: schema, config: config)
        let count = try ModelContext(reopened).fetchCount(FetchDescriptor<DiagnosticPet>())
        XCTAssertEqual(count, 1)
    }

    // MARK: B — full PetCare360 schema, local only

    func testB_FullSchemaLocalCreateSaveReopen() throws {
        let url = try tempStoreURL("B")
        let schema = PetCare360App.appSchema()
        let config = ModelConfiguration(schema: schema, url: url)
        do {
            try createAndRelease(schema: schema, config: config) { ctx in
                ctx.insert(Pet(name: "Diag", species: .dog))
                try ctx.save()
            }
        } catch {
            XCTFail("B failed — a PetCare360 model/schema defect:\n\(describeChain(error))")
            return
        }
        let reopened = try reopen(schema: schema, config: config)
        let count = try ModelContext(reopened).fetchCount(FetchDescriptor<Pet>())
        XCTAssertEqual(count, 1)
    }

    // MARK: C — full schema, CloudKit private database (record-only)

    func testC_FullSchemaCloudKitAttempt_RecordOnly() {
        let schema = PetCare360App.appSchema()
        let config = ModelConfiguration(
            schema: schema, cloudKitDatabase: .private(AppConfig.iCloudContainerID))
        do {
            var container: ModelContainer? = try ModelContainer(for: schema, configurations: [config])
            container = nil
            print("DIAGNOSTIC C: CloudKit container creation SUCCEEDED")
        } catch {
            print("DIAGNOSTIC C: CloudKit container creation failed:\n\(describeChain(error))")
        }
    }

    // MARK: D — relationship-closed groups, local

    private func exerciseGroup(_ label: String, _ types: [any PersistentModel.Type],
                               file: StaticString = #filePath, line: UInt = #line) {
        do {
            let url = try tempStoreURL(label)
            let schema = Schema(types)
            let config = ModelConfiguration(schema: schema, url: url)
            try createAndRelease(schema: schema, config: config)
            _ = try reopen(schema: schema, config: config)
        } catch {
            XCTFail("Group \(label) failed:\n\(describeChain(error))", file: file, line: line)
        }
    }

    func testD1_PetCoreGroup() {
        exerciseGroup("petcore", [Pet.self, Medication.self, MedicationAdministration.self,
                                  VaccinationRecord.self, MedicalRecord.self, MedicalDocument.self,
                                  VetAppointment.self, HealthObservation.self, PetExpense.self,
                                  FoodSchedule.self])
    }

    func testD2_InsuranceGroup() {
        exerciseGroup("insurance", [InsurancePolicy.self, InsuranceClaim.self])
    }

    func testD3_HouseholdGroup() {
        exerciseGroup("household", [Household.self, HouseholdMember.self])
    }

    func testD4_StandaloneGroup() {
        exerciseGroup("standalone", [UserProfile.self, MedicationSchedule.self, CareTask.self,
                                     CareHandoff.self, FeedingLog.self, RecallAlert.self,
                                     SavedFoodBrand.self, EmergencyProfile.self,
                                     SubscriptionEntitlement.self])
    }

    // MARK: F — production fallback configuration (explicit .none)

    /// Exercises PetCare360App.localConfiguration — the EXACT
    /// configuration the app's fallback path builds (explicit
    /// cloudKitDatabase: .none), pointed at a temp URL for
    /// isolation. Codemagic build 4 proved the schema opens
    /// locally; this proves the production fallback SHAPE opens,
    /// saves and reopens it. On an entitled device build this is
    /// the configuration that must survive when the CloudKit
    /// configuration fails validation.
    func testF_ExplicitLocalFallbackOpensSavesReopens() throws {
        let url = try tempStoreURL("F")
        let schema = PetCare360App.appSchema()
        let config = PetCare360App.localConfiguration(schema: schema, url: url)
        do {
            try createAndRelease(schema: schema, config: config) { ctx in
                ctx.insert(Pet(name: "Fallback", species: .reptile))
                try ctx.save()
            }
        } catch {
            XCTFail("F failed — the explicit local fallback does not open:\n\(describeChain(error))")
            return
        }
        let reopened = try reopen(schema: schema, config: config)
        let pets = try ModelContext(reopened).fetch(FetchDescriptor<Pet>())
        XCTAssertEqual(pets.count, 1)
        XCTAssertEqual(pets.first?.species, .reptile)
    }

    // MARK: E — default store location vs explicit URL (record-only)

    /// The app configures its local store WITHOUT an explicit URL
    /// (SwiftData's default location inside the app sandbox), while
    /// tests A/B/D use explicit temporary URLs. If A/B/D pass but
    /// the app still fails, this comparison isolates the default
    /// location itself. Record-only: it prints BOTH outcomes with
    /// full chains; the default-location store files it creates
    /// are removed again at the end. SIMULATOR/TEST USE ONLY.
    func testE_DefaultVsExplicitStoreLocation_RecordOnly() throws {
        let schema = PetCare360App.appSchema()

        let url = try tempStoreURL("E")
        let explicit = ModelConfiguration(schema: schema, url: url)
        do {
            try createAndRelease(schema: schema, config: explicit)
            print("DIAGNOSTIC E: explicit temp URL (\(url.path)) — OPENED")
        } catch {
            print("DIAGNOSTIC E: explicit temp URL — FAILED:\n\(describeChain(error))")
        }

        let defaultConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        print("DIAGNOSTIC E: default store URL = \(defaultConfig.url.path)")
        do {
            try createAndRelease(schema: schema, config: defaultConfig)
            print("DIAGNOSTIC E: default location — OPENED")
        } catch {
            print("DIAGNOSTIC E: default location — FAILED:\n\(describeChain(error))")
        }
        StoreFileWiper.wipeStoreFiles(at: defaultConfig.url)
    }
}
