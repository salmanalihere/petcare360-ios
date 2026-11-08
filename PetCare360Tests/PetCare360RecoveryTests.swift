import XCTest
import SwiftData
@testable import PetCare360

/// Build-13 database recovery tests. WRITTEN, not executed.
/// The on-disk container test exercises real file-backed creation,
/// reopening and CRUD; the policy tests pin the no-loop guarantee.
@MainActor
final class PetCare360RecoveryTests: XCTestCase {

    // MARK: Policy — recovery is bounded

    func testPolicyAllowsOneWipePerGeneration() {
        XCTAssertTrue(StoreRecoveryPolicy.shouldWipeAndRetry(
            openFailed: true, recoveryAttemptedGeneration: 0, currentGeneration: 1))
        XCTAssertFalse(StoreRecoveryPolicy.shouldWipeAndRetry(
            openFailed: true, recoveryAttemptedGeneration: 1, currentGeneration: 1))
    }

    func testPolicyNeverWipesOnSuccess() {
        XCTAssertFalse(StoreRecoveryPolicy.shouldWipeAndRetry(
            openFailed: false, recoveryAttemptedGeneration: 0, currentGeneration: 1))
    }

    func testPolicyNewGenerationRearmsExactlyOnce() {
        XCTAssertTrue(StoreRecoveryPolicy.shouldWipeAndRetry(
            openFailed: true, recoveryAttemptedGeneration: 1, currentGeneration: 2))
        XCTAssertFalse(StoreRecoveryPolicy.shouldWipeAndRetry(
            openFailed: true, recoveryAttemptedGeneration: 2, currentGeneration: 2))
    }

    func testLedgerRoundTrip() {
        let defaults = UserDefaults(suiteName: "pc360-recovery-tests-\(UUID().uuidString)")!
        XCTAssertEqual(StoreRecoveryLedger.currentGeneration(defaults: defaults), 1)
        XCTAssertEqual(StoreRecoveryLedger.recoveryAttemptedGeneration(defaults: defaults), 0)
        StoreRecoveryLedger.markRecoveryAttempted(for: 1, defaults: defaults)
        XCTAssertEqual(StoreRecoveryLedger.recoveryAttemptedGeneration(defaults: defaults), 1)
        XCTAssertEqual(StoreRecoveryLedger.beginNewGeneration(defaults: defaults), 2)
        XCTAssertEqual(StoreRecoveryLedger.currentGeneration(defaults: defaults), 2)
    }

    // MARK: Wiper — removes the store, nothing else

    func testWiperRemovesStoreAndSidecarsOnly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pc360-wipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("default.store")
        for suffix in ["", "-wal", "-shm"] {
            try Data("x".utf8).write(to: URL(fileURLWithPath: store.path + suffix))
        }
        let keep = dir.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: keep)
        StoreFileWiper.wipeStoreFiles(at: store)
        for suffix in ["", "-wal", "-shm"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.path + suffix))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path))
    }

    // MARK: File-backed container — create, reopen, CRUD

    func testOnDiskContainerCreatesReopensAndPerformsCRUD() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pc360-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = ModelConfiguration(
            schema: PetCare360App.appSchema(),
            url: dir.appendingPathComponent("test.store"),
            cloudKitDatabase: .none)

        // Creation + insert.
        let first = try PetCare360App.makeContainer(configuration: config)
        let ctx1 = ModelContext(first)
        ctx1.insert(Pet(name: "Recovery", species: .horse))
        try ctx1.save()

        // Reopen the same file — the record must survive, proving
        // reopen of an existing on-disk store works.
        let second = try PetCare360App.makeContainer(configuration: config)
        let ctx2 = ModelContext(second)
        var pets = try ctx2.fetch(FetchDescriptor<Pet>())
        XCTAssertEqual(pets.count, 1)
        XCTAssertEqual(pets.first?.name, "Recovery")
        XCTAssertEqual(pets.first?.species, .horse)

        // Update + delete.
        pets[0].name = "Recovered"
        try ctx2.save()
        ctx2.delete(pets[0])
        try ctx2.save()
        pets = try ctx2.fetch(FetchDescriptor<Pet>())
        XCTAssertTrue(pets.isEmpty)
    }

    // MARK: Regression — full schema on an explicitly local-only store

    /// REGRESSION (2026-11-08): the FULL production schema must
    /// open, save, close, and reopen on an explicitly local-only
    /// configuration (`cloudKitDatabase: .none` written out here,
    /// independently of the production factory, so a drift in
    /// either is caught). The records saved include the very
    /// relationships CloudKit rejects (Household.members, a Pet),
    /// proving local storage is unaffected by the CloudKit schema
    /// limitation. History: when the test builds became ad-hoc
    /// signed (entitled binary), every test configuration that
    /// silently relied on ModelConfiguration's `.automatic`
    /// default began engaging CloudKit and throwing the
    /// relationship-optionality error — including the previous
    /// version of the CRUD test above. This test pins the
    /// explicit-local shape so that class of failure cannot
    /// return unnoticed.
    func testFullSchemaOpensSavesReopensWithExplicitLocalOnlyConfiguration() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pc360-localonly-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = ModelConfiguration(
            schema: PetCare360App.appSchema(),
            url: dir.appendingPathComponent("localonly.store"),
            cloudKitDatabase: .none)

        // Open + save, then FULLY release before reopening.
        var first: ModelContainer? = try PetCare360App.makeContainer(configuration: config)
        let ctx1 = ModelContext(first!)
        let household = Household()
        let member = HouseholdMember(displayName: "Regression", role: .owner)
        member.household = household
        ctx1.insert(household)
        ctx1.insert(member)
        ctx1.insert(Pet(name: "LocalOnly", species: .cat))
        try ctx1.save()
        first = nil

        // Reopen: records AND the relationship must survive.
        let second = try PetCare360App.makeContainer(configuration: config)
        let ctx2 = ModelContext(second)
        XCTAssertEqual(try ctx2.fetchCount(FetchDescriptor<Pet>()), 1)
        let households = try ctx2.fetch(FetchDescriptor<Household>())
        XCTAssertEqual(households.count, 1)
        XCTAssertEqual(households.first?.members.count, 1,
                       "The Household.members relationship must round-trip on the local-only store")
        XCTAssertEqual(households.first?.members.first?.displayName, "Regression")
    }
}
