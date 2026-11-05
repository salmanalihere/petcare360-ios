import XCTest
import PDFKit
@testable import PetCare360

/// Phase 2 tests. Like the original suite, these are WRITTEN but have not
/// been executed in the Linux build environment (no Xcode). See
/// docs/TEST_REPORT.md.
final class PetCare360Phase2Tests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: Medication editor logic

    func testNormalizeDoseMinutesDedupesSortsAndFilters() {
        XCTAssertEqual(MedicationService.normalizeDoseMinutes([1200, 480, 480, 60]), [60, 480, 1200])
        XCTAssertEqual(MedicationService.normalizeDoseMinutes([1440, -5, 700]), [700])
        XCTAssertTrue(MedicationService.normalizeDoseMinutes([]).isEmpty)
    }

    func testMultipleDoseTimesGenerateMultipleSlots() {
        let med = Medication(name: "Insulin", dosage: "2u")
        med.startDate = date(2025, 1, 1)
        med.doseMinutes = MedicationService.normalizeDoseMinutes([480, 720, 1200, 1200])
        let slots = MedicationService.slots(for: med, on: date(2025, 6, 10))
        XCTAssertEqual(slots.map { $0.minutes }, [480, 720, 1200])
    }

    func testWeeklyMedicationMultipleWeekdays() {
        let med = Medication(name: "Weekly", dosage: "1")
        med.startDate = date(2025, 1, 1)
        med.frequencyRaw = MedicationFrequency.weekly.rawValue
        let day = date(2025, 6, 10)
        let weekday = Calendar.current.component(.weekday, from: day)
        med.weekdays = [weekday, (weekday % 7) + 1]
        XCTAssertEqual(MedicationService.slots(for: med, on: day).count, 1)
        let other = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let otherWeekday = Calendar.current.component(.weekday, from: other)
        if otherWeekday == (weekday % 7) + 1 {
            XCTAssertEqual(MedicationService.slots(for: med, on: other).count, 1)
        } else {
            XCTAssertTrue(MedicationService.slots(for: med, on: other).isEmpty)
        }
    }

    func testMedicationEditingUpdatesFieldsAndKeepsHistory() {
        let pet = Pet(name: "Buddy")
        let med = Medication(name: "Old Name", dosage: "5mg")
        med.pet = pet
        pet.medications.append(med)
        let slot = DoseSlot(medicationID: med.id, day: date(2025, 6, 10), minutes: 480)
        let entry = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .given, by: "Alex")
        entry.pet = pet
        pet.administrations.append(entry)
        // Simulate an edit exactly as the editor saves it.
        med.name = "New Name"
        med.dosage = "10mg"
        med.doseMinutes = [480, 1200]
        med.weekdays = [2, 4]
        med.endDate = date(2025, 12, 31)
        XCTAssertEqual(pet.medications.first?.name, "New Name")
        XCTAssertEqual(pet.administrations.count, 1, "Editing a medication must never erase administration history")
        XCTAssertTrue(MedicationService.isAlreadyGiven(slot: slot, administrations: pet.administrations))
    }

    func testMedicationDeletionLeavesAdministrationHistory() {
        let pet = Pet(name: "Buddy")
        let med = Medication(name: "Apoquel", dosage: "16mg")
        let slot = DoseSlot(medicationID: med.id, day: date(2025, 6, 10), minutes: 480)
        let entry = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .given, by: "Alex")
        entry.pet = pet
        pet.administrations.append(entry)
        pet.medications.removeAll { $0.id == med.id }   // what context.delete achieves for the relationship
        XCTAssertTrue(pet.medications.isEmpty)
        XCTAssertEqual(pet.administrations.count, 1, "History rows belong to the pet, not the medication")
        XCTAssertEqual(pet.administrations.first?.medicationName, "Apoquel")
    }

    func testPrescriptionDocumentLinkIsStored() {
        let med = Medication(name: "Apoquel", dosage: "16mg")
        let docID = UUID()
        med.prescriptionDocumentID = docID
        XCTAssertEqual(med.prescriptionDocumentID, docID)
    }

    // MARK: Administration safety

    func testEffectiveStatusGivenWinsOverEarlierSkip() {
        let med = Medication(name: "Apoquel", dosage: "16mg")
        let slot = DoseSlot(medicationID: med.id, day: date(2025, 6, 10), minutes: 480)
        let skipped = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .skipped, by: "Alex")
        skipped.administeredAt = date(2025, 6, 10).addingTimeInterval(3600)
        let given = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .given, by: "Sam")
        given.administeredAt = date(2025, 6, 10).addingTimeInterval(7200)
        XCTAssertEqual(MedicationService.effectiveStatus(for: slot, administrations: [skipped, given]), .given)
        XCTAssertTrue(MedicationService.isAlreadyGiven(slot: slot, administrations: [skipped, given]),
                      "A slot with any Given entry can never be given twice")
    }

    func testEffectiveStatusFallsBackToMostRecentEntry() {
        let med = Medication(name: "Apoquel", dosage: "16mg")
        let slot = DoseSlot(medicationID: med.id, day: date(2025, 6, 10), minutes: 480)
        let delayed = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .delayed, by: "Alex")
        delayed.administeredAt = date(2025, 6, 10).addingTimeInterval(3600)
        let skipped = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .skipped, by: "Alex")
        skipped.administeredAt = date(2025, 6, 10).addingTimeInterval(7200)
        XCTAssertEqual(MedicationService.effectiveStatus(for: slot, administrations: [delayed, skipped]), .skipped)
    }

    func testAdministrationCarriesStableMemberID() {
        let med = Medication(name: "Apoquel", dosage: "16mg")
        let slot = DoseSlot(medicationID: med.id, day: date(2025, 6, 10), minutes: 480)
        let entry = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .given, by: "Alex")
        let memberID = UUID()
        entry.administeredByMemberID = memberID
        XCTAssertEqual(entry.administeredByMemberID, memberID)
        XCTAssertEqual(entry.administeredBy, "Alex", "Display name remains for the UI")
    }

    // MARK: Record editing

    func testMedicalRecordEditAppendsHistory() {
        let record = MedicalRecord(title: "Checkup", category: .appointment, date: date(2025, 1, 1))
        XCTAssertTrue(record.editHistory.isEmpty)
        record.recordEdit(note: "Edited: details updated in the app.")
        record.title = "Annual checkup"
        XCTAssertFalse(record.editHistory.isEmpty, "Corrections must be auditable, not silent")
        XCTAssertEqual(record.title, "Annual checkup")
    }

    // MARK: Backup v2

    private func samplePet() -> Pet {
        let pet = Pet(name: "Buddy")
        pet.breed = "Labrador"
        let med = Medication(name: "Apoquel", dosage: "16mg")
        med.pet = pet
        pet.medications.append(med)
        let slot = DoseSlot(medicationID: med.id, day: date(2025, 6, 10), minutes: 480)
        let admin = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .given, by: "Alex")
        admin.pet = pet
        pet.administrations.append(admin)
        let vax = VaccinationRecord(vaccineName: "Rabies", date: date(2025, 1, 1))
        vax.pet = pet
        pet.vaccinations.append(vax)
        let expense = PetExpense(amount: Decimal(string: "42.50")!, category: .food, date: date(2025, 2, 2))
        expense.pet = pet
        pet.expenses.append(expense)
        return pet
    }

    func testBackupV2CoversRelatedRecords() throws {
        let pet = samplePet()
        let household = Household(name: "Home")
        household.members.append(HouseholdMember(displayName: "Alex", role: .owner))
        let policy = InsurancePolicy(provider: "Healthy Paws", petID: pet.id, petName: pet.name)
        policy.claims.append(InsuranceClaim(title: "X-ray", amount: Decimal(120)))
        let backup = BackupService.makeFullBackup(
            pets: [pet], households: [household], careTasks: [], careHandoffs: [],
            feedingLogs: [], insurancePolicies: [policy], emergencyProfiles: [],
            savedBrands: [], recallAlerts: [], medicationSchedules: [])
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decodeFull(data: data)
        XCTAssertEqual(decoded.version, 2)
        XCTAssertEqual(decoded.pets.first?.medications.first?.name, "Apoquel")
        XCTAssertEqual(decoded.pets.first?.administrations.count, 1)
        XCTAssertEqual(decoded.pets.first?.vaccinations.count, 1)
        XCTAssertEqual(decoded.pets.first?.expenses.first?.amountString, "42.5")
        XCTAssertEqual(decoded.households.first?.members.first?.roleRaw, HouseholdRole.owner.rawValue)
        XCTAssertEqual(decoded.insurancePolicies.first?.claims.first?.title, "X-ray")
        XCTAssertEqual(decoded.insurancePolicies.first?.petID, pet.id, "Relationships survive via preserved IDs")
    }

    func testBackupV2RejectsDuplicateIDs() throws {
        let first = samplePet()
        var backup = BackupService.makeFullBackup(
            pets: [first], households: [], careTasks: [], careHandoffs: [],
            feedingLogs: [], insurancePolicies: [], emergencyProfiles: [],
            savedBrands: [], recallAlerts: [], medicationSchedules: [])
        var duplicate = backup.pets[0]
        duplicate.name = "Copy"
        backup.pets.append(duplicate)   // same pet ID twice
        let data = try BackupService.encode(backup)
        XCTAssertThrowsError(try BackupService.decodeFull(data: data), "Duplicate IDs must reject the whole file")
    }

    func testBackupV1StillDecodes() throws {
        let pet = Pet(name: "Legacy")
        let data = try BackupService.exportData(pets: [pet])
        guard case .v1(let payload) = try BackupService.decodeAny(data: data) else {
            return XCTFail("A v1 backup must still be restorable")
        }
        XCTAssertEqual(payload.pets.first?.name, "Legacy")
    }

    // MARK: PDF layout

    func testPDFWrapsLongNotesAcrossPages() {
        let pet = Pet(name: "Buddy")
        let longNote = String(repeating: "The veterinarian observed that the patient responded well to treatment and should continue the current plan with regular monitoring at home. ", count: 40)
        let record = MedicalRecord(title: "Long note", category: .note, date: Date())
        record.details = longNote
        record.pet = pet
        pet.medicalRecords.append(record)
        let data = PDFService.medicalPassport(pet: pet, include: Set(MedicalCategory.allCases))
        XCTAssertTrue(data.starts(with: [0x25, 0x50, 0x44, 0x46]), "Output must be a real PDF")
        let document = PDFDocument(data: data)
        XCTAssertGreaterThanOrEqual(document?.pageCount ?? 0, 2, "Long content must paginate, not overflow")
    }

    func testPDFHandlesVeryLongSingleWord() {
        let pet = Pet(name: "Buddy")
        pet.medicalConditions = String(repeating: "x", count: 600)
        let data = PDFService.medicalPassport(pet: pet, include: Set(MedicalCategory.allCases))
        XCTAssertNotNil(PDFDocument(data: data))
    }

    // MARK: Entitlements & downgrade policy

    func testPremiumCreationGates() {
        XCTAssertFalse(EntitlementPolicy.canCreate(.expenseTracking, isPremium: false))
        XCTAssertFalse(EntitlementPolicy.canCreate(.insuranceOrganizer, isPremium: false))
        XCTAssertFalse(EntitlementPolicy.canCreate(.advancedCharts, isPremium: false))
        XCTAssertTrue(EntitlementPolicy.canCreate(.expenseTracking, isPremium: true))
    }

    func testHouseholdIdentityResolvesByIDNotName() {
        let alex = HouseholdMember(displayName: "Alex", role: .owner)
        let sam = HouseholdMember(displayName: "Alex", role: .viewer)   // same display name on purpose
        let members = [alex, sam]
        XCTAssertEqual(HouseholdIdentity.resolveRole(memberID: sam.id, members: members), .viewer,
                       "Identity must come from the stable ID, never the display name")
        XCTAssertEqual(HouseholdIdentity.resolveRole(memberID: alex.id, members: members), .owner)
    }

    func testHouseholdIdentityFallbacks() {
        let owner = HouseholdMember(displayName: "Owner", role: .owner)
        XCTAssertEqual(HouseholdIdentity.resolveRole(memberID: UUID(), members: [owner]), .owner,
                       "Single-device fallback: the sole owner is this device's user")
        let secondOwner = HouseholdMember(displayName: "Other", role: .owner)
        XCTAssertNil(HouseholdIdentity.resolveRole(memberID: UUID(), members: [owner, secondOwner]),
                     "Ambiguous ownership must resolve to no role, not guessed access")
    }

    func testEmergencyQRSelectionStillRespected() {
        let pet = Pet(name: "Buddy")
        pet.allergies = "Chicken"
        let profile = EmergencyProfile(petID: pet.id, petName: pet.name)
        profile.isEnabled = true
        profile.sharedFieldKeys = []
        let payload = EmergencyService.payload(pet: pet, profile: profile, medications: [])
        XCTAssertFalse(payload.contains("Chicken"), "No field may be shared unless the owner selected it")
    }
}
