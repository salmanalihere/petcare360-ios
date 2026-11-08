import XCTest
import SwiftData
@testable import PetCare360

/// v1.2.7 tests: archived-pet insurance reminder eligibility and
/// complete RestoreSummary.skipped accounting. WRITTEN, not executed —
/// no Xcode here (syntax-verified with swiftc -parse only).
@MainActor
final class PetCare360V127Tests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try PetCare360App.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return ModelContext(container)
    }

    // MARK: Insurance reminder eligibility (brief §1)

    func testInsuranceRemindersOnlyForActivePets() {
        let active = Pet(name: "Active")
        let archived = Pet(name: "Archived")
        archived.isArchived = true
        let activePolicy = InsurancePolicy(provider: "A", petID: active.id, petName: active.name)
        let archivedPolicy = InsurancePolicy(provider: "B", petID: archived.id, petName: archived.name)
        let orphanPolicy = InsurancePolicy(provider: "C", petID: UUID(), petName: "Ghost")
        let eligible = NotificationService.eligibleInsurancePolicies(
            policies: [activePolicy, archivedPolicy, orphanPolicy], pets: [active, archived])
        XCTAssertEqual(eligible.map { $0.id }, [activePolicy.id],
                       "Archived pets (and policies whose pet no longer exists) must not get renewal reminders")
    }

    func testRestoredPetRegainsInsuranceEligibility() {
        let pet = Pet(name: "Bruno")
        pet.isArchived = true
        let policy = InsurancePolicy(provider: "A", petID: pet.id, petName: pet.name)
        XCTAssertTrue(NotificationService.eligibleInsurancePolicies(policies: [policy], pets: [pet]).isEmpty)
        pet.isArchived = false   // restored — eligibility is computed fresh every rebuild
        XCTAssertEqual(NotificationService.eligibleInsurancePolicies(policies: [policy], pets: [pet]).map { $0.id },
                       [policy.id])
    }

    // MARK: RestoreSummary.skipped accounting (brief §3)

    func testMergeSkippedCountsEveryRecordType() throws {
        let source = try makeContext()
        let pet = Pet(name: "Bruno")
        source.insert(pet)
        let med = Medication(name: "Apoquel", dosage: "16mg"); med.pet = pet; source.insert(med)
        let slot = DoseSlot(medicationID: med.id, day: Date(), minutes: 480)
        let admin = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .given, by: "Owner")
        admin.pet = pet; source.insert(admin)
        let vax = VaccinationRecord(vaccineName: "Rabies", date: Date()); vax.pet = pet; source.insert(vax)
        let record = MedicalRecord(title: "Checkup", date: Date()); record.pet = pet; source.insert(record)
        let doc = MedicalDocument(title: "Lab"); doc.pet = pet; source.insert(doc)
        let appt = VetAppointment(title: "Visit", date: Date()); appt.pet = pet; source.insert(appt)
        let obs = HealthObservation(kind: .weight, date: Date()); obs.pet = pet; source.insert(obs)
        let expense = PetExpense(amount: 10, category: .food, date: Date()); expense.pet = pet; source.insert(expense)
        let food = FoodSchedule(brand: "Acme"); food.pet = pet; source.insert(food)
        let household = Household(name: "Home"); source.insert(household)
        let member = HouseholdMember(displayName: "Owner", role: .owner); member.household = household; source.insert(member)
        source.insert(CareTask(title: "Walk", petID: pet.id, petName: pet.name, date: Date()))
        source.insert(CareHandoff(petName: pet.name, author: "Owner"))
        source.insert(FeedingLog(petID: pet.id, petName: pet.name, by: "Owner"))
        let policy = InsurancePolicy(provider: "PawProtect", petID: pet.id, petName: pet.name); source.insert(policy)
        let claim = InsuranceClaim(title: "Surgery", amount: 100); claim.policy = policy; source.insert(claim)
        source.insert(EmergencyProfile(petID: pet.id, petName: pet.name))
        source.insert(SavedFoodBrand(brand: "Acme"))
        source.insert(RecallAlert(productName: "Acme Kibble", manufacturer: "Acme", sourceURL: "https://www.fda.gov"))
        source.insert(MedicationSchedule(medicationID: med.id))
        try source.save()

        let backup = BackupService.makeFullBackup(
            pets: [pet], households: [household],
            careTasks: try source.fetch(FetchDescriptor<CareTask>()),
            careHandoffs: try source.fetch(FetchDescriptor<CareHandoff>()),
            feedingLogs: try source.fetch(FetchDescriptor<FeedingLog>()),
            insurancePolicies: [policy],
            emergencyProfiles: try source.fetch(FetchDescriptor<EmergencyProfile>()),
            savedBrands: try source.fetch(FetchDescriptor<SavedFoodBrand>()),
            recallAlerts: try source.fetch(FetchDescriptor<RecallAlert>()),
            medicationSchedules: try source.fetch(FetchDescriptor<MedicationSchedule>()))

        let target = try makeContext()
        let replaced = try BackupService.restore(backup, into: target, strategy: .replace)
        XCTAssertEqual(replaced.skipped, 0, "Replace into an empty store skips nothing")
        // The fixture holds exactly 21 records: 1 pet + 1 household
        // + 1 member + 9 pet children + 1 task + 1 handoff + 1 feeding
        // log + 1 policy + 1 claim + 1 emergency profile + 1 brand
        // + 1 recall + 1 medication schedule (corrected in v1.2.8 to
        // include the parent pet and household records).
        XCTAssertEqual(replaced.inserted, 21)

        let merged = try BackupService.restore(backup, into: target, strategy: .merge)
        XCTAssertEqual(merged.inserted, 0, "Merging identical data inserts nothing")
        // All 21 fixture records already exist — INCLUDING the pet
        // profile and the household (v1.2.8 parent counting).
        XCTAssertEqual(merged.skipped, 21,
                       "Every record, parents included, must be counted as skipped when it already exists")
    }
}
