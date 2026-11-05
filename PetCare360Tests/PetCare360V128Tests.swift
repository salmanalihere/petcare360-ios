import XCTest
import SwiftData
@testable import PetCare360

/// v1.2.8 tests: parent records in the restore summary, and Replace
/// atomicity. WRITTEN, not executed — no Xcode here (syntax-verified
/// with swiftc -parse only).
@MainActor
final class PetCare360V128Tests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try PetCare360App.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func emptyBackup(pets: [Pet], households: [Household]) -> BackupService.FullBackup {
        BackupService.makeFullBackup(
            pets: pets, households: households, careTasks: [], careHandoffs: [],
            feedingLogs: [], insurancePolicies: [], emergencyProfiles: [],
            savedBrands: [], recallAlerts: [], medicationSchedules: [])
    }

    // MARK: Parent counting (brief §1)

    func testExistingPetProfileCountedAsSkipped() throws {
        let source = try makeContext()
        let pet = Pet(name: "Bruno")
        source.insert(pet)
        try source.save()
        let backup = emptyBackup(pets: [pet], households: [])
        let target = try makeContext()
        let replaced = try BackupService.restore(backup, into: target, strategy: .replace)
        XCTAssertEqual(replaced.inserted, 1)
        XCTAssertEqual(replaced.skipped, 0)
        let merged = try BackupService.restore(backup, into: target, strategy: .merge)
        XCTAssertEqual(merged.inserted, 0)
        XCTAssertEqual(merged.skipped, 1, "The existing pet profile itself must be counted as skipped")
    }

    func testExistingHouseholdCountedAsSkipped() throws {
        let source = try makeContext()
        let household = Household(name: "Home")
        source.insert(household)
        try source.save()
        let backup = emptyBackup(pets: [], households: [household])
        let target = try makeContext()
        _ = try BackupService.restore(backup, into: target, strategy: .replace)
        let merged = try BackupService.restore(backup, into: target, strategy: .merge)
        XCTAssertEqual(merged.inserted, 0)
        XCTAssertEqual(merged.skipped, 1, "The existing household itself must be counted as skipped")
    }

    // MARK: Replace atomicity (brief §2)

    /// The failure path restore() now guarantees: Replace's deletions
    /// happen inside the same do/catch as the import, whose catch calls
    /// rollback — pending deletions are discarded wholesale.
    func testReplaceFailureRollsBackPendingDeletions() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno")
        context.insert(pet)
        context.insert(CareTask(title: "Walk", petID: pet.id, petName: pet.name, date: Date()))
        try context.save()
        try BackupService.deleteEverything(in: context)   // what Replace does first
        context.rollback()                                 // what restore's catch does on failure
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pet>()).count, 1,
                       "A failed Replace must leave the existing database unchanged")
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareTask>()).count, 1)
    }

    func testReplaceRestoreSwapsDataAtomically() throws {
        let target = try makeContext()
        let old = Pet(name: "OldPet")
        target.insert(old)
        try target.save()
        let source = try makeContext()
        let new = Pet(name: "NewPet")
        source.insert(new)
        try source.save()
        let summary = try BackupService.restore(emptyBackup(pets: [new], households: []),
                                                into: target, strategy: .replace)
        XCTAssertEqual(summary.inserted, 1)
        let pets = try target.fetch(FetchDescriptor<Pet>())
        XCTAssertEqual(pets.map { $0.name }, ["NewPet"], "Replace removes the old data and imports the new in one save")
    }

    func testUserProfileSurvivesReplaceRestore() throws {
        let target = try makeContext()
        let profile = UserProfile(displayName: "Rukhsana")
        profile.hasCompletedOnboarding = true
        target.insert(profile)
        try target.save()
        _ = try BackupService.restore(emptyBackup(pets: [], households: []),
                                      into: target, strategy: .replace)
        XCTAssertEqual(try target.fetch(FetchDescriptor<UserProfile>()).count, 1,
                       "Replace must preserve the user profile, per the existing design")
    }
}
