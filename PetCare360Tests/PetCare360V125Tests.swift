import XCTest
import SwiftData
@testable import PetCare360

/// v1.2.5 tests: shared restore limit, deletion failure contract,
/// handoff petID association + legacy compatibility, and serialized
/// notification synchronization. WRITTEN, not executed — no Xcode here.
@MainActor
final class PetCare360V125Tests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try PetCare360App.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    // MARK: Archived restore limit (brief §1)

    func testArchivedRestoreBlockedAtFreeLimit() throws {
        let context = try makeContext()
        let active = Pet(name: "Active")
        let archived = Pet(name: "Archived")
        archived.isArchived = true
        context.insert(active); context.insert(archived)
        try context.save()
        let outcome = PetArchiveService.restore(pet: archived, activeCount: 1, isPremium: false, in: context)
        XCTAssertEqual(outcome, .limitReached)
        XCTAssertTrue(archived.isArchived, "A blocked restore must leave the pet archived")
    }

    func testArchivedRestoreAllowedForPremium() throws {
        let context = try makeContext()
        let active = Pet(name: "Active")
        let archived = Pet(name: "Archived")
        archived.isArchived = true
        context.insert(active); context.insert(archived)
        try context.save()
        let outcome = PetArchiveService.restore(pet: archived, activeCount: 1, isPremium: true, in: context)
        XCTAssertEqual(outcome, .done)
        XCTAssertFalse(archived.isArchived)
    }

    func testArchivedRestoreAllowedForFreeUserWithNoActivePets() throws {
        let context = try makeContext()
        let archived = Pet(name: "Archived")
        archived.isArchived = true
        context.insert(archived)
        try context.save()
        XCTAssertEqual(PetArchiveService.restore(pet: archived, activeCount: 0, isPremium: false, in: context), .done)
    }

    // MARK: Deletion failure contract (brief §2)

    /// The failure path the UI relies on: a failed save is discarded via
    /// rollback, so partially-deleted data is never left behind. (A
    /// healthy in-memory store cannot be forced to fail a save; the
    /// view-level contract — rollback, stay open, show error — is built
    /// on exactly this mechanism.)
    func testRollbackRestoresPendingDeletions() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno")
        context.insert(pet)
        let doc = MedicalDocument(title: "Lab result")
        doc.pet = pet
        context.insert(doc)
        try context.save()
        context.delete(pet)
        context.delete(doc)
        context.rollback()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pet>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MedicalDocument>()).count, 1)
    }

    // MARK: Handoff association (brief §3)

    func testHandoffDeletionMatchesByIDNeverByName() throws {
        let context = try makeContext()
        let bruno = Pet(name: "Bruno")
        let otherBruno = Pet(name: "Bruno")   // same name, different pet
        context.insert(bruno); context.insert(otherBruno)
        let matched = CareHandoff(petName: "Bruno", author: "Owner")
        matched.petID = bruno.id
        let legacy = CareHandoff(petName: "Bruno", author: "Sitter")
        // legacy.petID stays nil — created before the association existed
        let otherPets = CareHandoff(petName: "Bruno", author: "Walker")
        otherPets.petID = otherBruno.id
        context.insert(matched); context.insert(legacy); context.insert(otherPets)
        try context.save()

        _ = try PetDeletionService.deleteAllData(for: bruno, in: context)
        let remaining = try context.fetch(FetchDescriptor<CareHandoff>())
        XCTAssertEqual(remaining.count, 2, "Only the ID-matched handoff may be deleted")
        XCTAssertTrue(remaining.contains { $0.id == legacy.id }, "Legacy handoffs are preserved")
        XCTAssertTrue(remaining.contains { $0.id == otherPets.id }, "A same-named pet's handoffs are preserved")
    }

    func testOldBackupHandoffWithoutPetIDStillDecodes() throws {
        // A v1.2.4-era backup file: the handoff object has NO petID key.
        let json = """
        {"id":"\(UUID().uuidString)","petName":"Bruno","authorName":"Owner",
         "authorMemberID":null,"date":770000000,"wasFed":true,"medicationGiven":false,
         "walkCompleted":true,"appetiteNormal":true,"unusualBehavior":"","notes":""}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let dto = try decoder.decode(BackupService.HandoffFull.self, from: Data(json.utf8))
        XCTAssertNil(dto.petID, "Old backups must decode with petID == nil, never fail or guess")
        XCTAssertEqual(dto.petName, "Bruno")
    }

    func testHandoffPetIDSurvivesBackupRoundTrip() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno")
        context.insert(pet)
        let handoff = CareHandoff(petName: "Bruno", author: "Owner")
        handoff.petID = pet.id
        context.insert(handoff)
        try context.save()
        let backup = BackupService.makeFullBackup(
            pets: [pet], households: [], careTasks: [], careHandoffs: [handoff],
            feedingLogs: [], insurancePolicies: [], emergencyProfiles: [],
            savedBrands: [], recallAlerts: [], medicationSchedules: [])
        XCTAssertEqual(backup.careHandoffs.first?.petID, pet.id)
        let target = try makeContext()
        _ = try BackupService.restore(backup, into: target, strategy: .replace)
        XCTAssertEqual(try target.fetch(FetchDescriptor<CareHandoff>()).first?.petID, pet.id)
    }

    // MARK: Serialized synchronization (brief §5)
}

final class PetCare360V125SyncTests: XCTestCase {
    func testSyncCoordinatorSerializesAndCoalesces() {
        let coordinator = SyncCoordinator()
        let lock = NSLock()
        var order: [String] = []
        var inFlight = 0
        var maxInFlight = 0
        let finished = expectation(description: "coalesced passes finish")

        func record(_ name: String) {
            lock.lock()
            inFlight += 1
            maxInFlight = max(maxInFlight, inFlight)
            order.append(name)
            lock.unlock()
        }
        func complete() { lock.lock(); inFlight -= 1; lock.unlock() }

        coordinator.submit { done in
            record("A")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { complete(); done() }
        }
        coordinator.submit { done in record("B"); complete(); done() }  // queued…
        coordinator.submit { done in                                     // …then replaced by C
            record("C"); complete(); done()
            finished.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertEqual(order, ["A", "C"], "Passes must serialize; a queued pass is coalesced to the latest")
        XCTAssertEqual(maxInFlight, 1, "Two passes must never run concurrently")
    }
}
