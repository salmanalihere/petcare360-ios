import XCTest
import SwiftData
@testable import PetCare360

/// v1.2.4 correction tests: per-record backup merge, complete pet
/// deletion, notification gates and claim accuracy. These use REAL
/// in-memory SwiftData containers. WRITTEN, not executed — no Xcode here.
@MainActor
final class PetCare360V124Tests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try PetCare360App.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    private func export(from context: ModelContext, pets: [Pet]) throws -> BackupService.FullBackup {
        BackupService.makeFullBackup(
            pets: pets,
            households: try context.fetch(FetchDescriptor<Household>()),
            careTasks: try context.fetch(FetchDescriptor<CareTask>()),
            careHandoffs: try context.fetch(FetchDescriptor<CareHandoff>()),
            feedingLogs: try context.fetch(FetchDescriptor<FeedingLog>()),
            insurancePolicies: try context.fetch(FetchDescriptor<InsurancePolicy>()),
            emergencyProfiles: try context.fetch(FetchDescriptor<EmergencyProfile>()),
            savedBrands: try context.fetch(FetchDescriptor<SavedFoodBrand>()),
            recallAlerts: try context.fetch(FetchDescriptor<RecallAlert>()),
            medicationSchedules: try context.fetch(FetchDescriptor<MedicationSchedule>()))
    }

    // MARK: Backup merge (review §1)

    func testMergeAddsNewRecordsToAnExistingPet() throws {
        // Source: Bruno with one vaccination.
        let source = try makeContext()
        let bruno = Pet(name: "Bruno")
        source.insert(bruno)
        let vax1 = VaccinationRecord(vaccineName: "Rabies", date: Date())
        vax1.pet = bruno
        source.insert(vax1)
        try source.save()
        let backup1 = try export(from: source, pets: [bruno])

        // Target restores backup1.
        let target = try makeContext()
        _ = try BackupService.restore(backup1, into: target, strategy: .replace)
        XCTAssertEqual(try target.fetch(FetchDescriptor<Pet>()).count, 1)
        XCTAssertEqual(try target.fetch(FetchDescriptor<VaccinationRecord>()).count, 1)

        // Source gains a vaccination and a medical record AFTER backup1.
        let vax2 = VaccinationRecord(vaccineName: "DHPP", date: Date())
        vax2.pet = bruno
        source.insert(vax2)
        let record = MedicalRecord(title: "Annual checkup", date: Date())
        record.pet = bruno
        source.insert(record)
        try source.save()
        let backup2 = try export(from: source, pets: [bruno])

        // THE BUG: Merge used to skip the whole pet because Bruno's ID
        // already existed, losing vax2 and the record. Now records merge.
        let summary = try BackupService.restore(backup2, into: target, strategy: .merge)
        XCTAssertEqual(try target.fetch(FetchDescriptor<Pet>()).count, 1, "No duplicate pet may be created")
        XCTAssertEqual(try target.fetch(FetchDescriptor<VaccinationRecord>()).count, 2,
                       "The new vaccination must be imported even though the pet already existed")
        XCTAssertEqual(try target.fetch(FetchDescriptor<MedicalRecord>()).count, 1,
                       "The new medical record must be imported even though the pet already existed")
        XCTAssertGreaterThanOrEqual(summary.inserted, 2)
    }

    func testMergeDoesNotDuplicateExistingRecords() throws {
        let source = try makeContext()
        let pet = Pet(name: "Milo")
        source.insert(pet)
        let vax = VaccinationRecord(vaccineName: "Rabies", date: Date())
        vax.pet = pet
        source.insert(vax)
        try source.save()
        let backup = try export(from: source, pets: [pet])
        let target = try makeContext()
        _ = try BackupService.restore(backup, into: target, strategy: .replace)
        _ = try BackupService.restore(backup, into: target, strategy: .merge)
        XCTAssertEqual(try target.fetch(FetchDescriptor<VaccinationRecord>()).count, 1)
    }

    // MARK: Pet deletion completeness (review §2)

    func testPetDeletionRemovesPetIDLinkedRecords() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno")
        context.insert(pet)
        let med = Medication(name: "Apoquel", dosage: "16mg")
        med.pet = pet
        context.insert(med)
        let schedule = MedicationSchedule(medicationID: med.id)
        context.insert(schedule)
        context.insert(CareTask(title: "Walk", petID: pet.id, petName: pet.name, date: Date()))
        context.insert(FeedingLog(petID: pet.id, petName: pet.name, by: "Owner"))
        context.insert(InsurancePolicy(provider: "PawProtect", petID: pet.id, petName: pet.name))
        context.insert(EmergencyProfile(petID: pet.id, petName: pet.name))
        try context.save()

        let removed = try PetDeletionService.deleteAllData(for: pet, in: context)
        XCTAssertGreaterThanOrEqual(removed, 5)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Pet>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<CareTask>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FeedingLog>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<InsurancePolicy>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<EmergencyProfile>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MedicationSchedule>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Medication>()).count, 0)
    }

    // MARK: Notification gates (review §3)

    func testCompletedAppointmentGetsNoReminder() {
        let done = VetAppointment(title: "Checkup", date: Date().addingTimeInterval(7200))
        done.isCompleted = true
        XCTAssertFalse(NotificationService.shouldScheduleAppointmentReminder(done))
        let past = VetAppointment(title: "Past", date: Date().addingTimeInterval(-7200))
        XCTAssertFalse(NotificationService.shouldScheduleAppointmentReminder(past))
        let future = VetAppointment(title: "Future", date: Date().addingTimeInterval(7200))
        XCTAssertTrue(NotificationService.shouldScheduleAppointmentReminder(future))
    }

    // MARK: Claim accuracy (review §5, §6, §7)

    func testEmergencyFieldsExcludePhoto() {
        XCTAssertFalse(EmergencyProfile.allFields.contains("photo"),
                       "A text QR cannot include a photo; the toggle must not be offered")
    }

    func testPaywallOnlyAdvertisesDifferentiatedBenefits() {
        XCTAssertFalse(PremiumFeature.paywallFeatures.contains(.fullMedicationHistory))
        XCTAssertFalse(PremiumFeature.paywallFeatures.contains(.unlimitedRecords))
        XCTAssertFalse(PremiumFeature.documentStorage.label.contains("AI"))
        XCTAssertFalse(PremiumFeature.recallNotifications.label.contains("notifications"))
    }
}
