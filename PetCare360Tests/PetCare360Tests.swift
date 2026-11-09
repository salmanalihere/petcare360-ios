import XCTest
@testable import PetCare360

final class PetCare360Tests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // Pet age
    func testAgeYearsAndMonths() {
        let parts = PetAgeCalculator.components(dateOfBirth: date(2023, 1, 15), now: date(2025, 4, 20))
        XCTAssertEqual(parts.years, 2)
        XCTAssertEqual(parts.months, 3)
    }
    func testAgeMonthsOnly() {
        let desc = PetAgeCalculator.describe(dateOfBirth: date(2025, 1, 1), now: date(2025, 4, 1))
        XCTAssertEqual(desc, "3 mo")
    }

    // Medication slots
    func testOnceDailySlot() {
        let med = Medication(name: "Apoquel", dosage: "16mg")
        med.startDate = date(2025, 1, 1)
        med.doseMinutes = [480]
        let slots = MedicationService.slots(for: med, on: date(2025, 6, 10))
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.minutes, 480)
    }
    func testTwiceDailySlotsSorted() {
        let med = Medication(name: "Insulin", dosage: "2u")
        med.startDate = date(2025, 1, 1)
        med.doseMinutes = [1200, 480]
        let slots = MedicationService.slots(for: med, on: date(2025, 6, 10))
        XCTAssertEqual(slots.map { $0.minutes }, [480, 1200])
    }
    func testNoSlotsBeforeStartOrAfterEnd() {
        let med = Medication(name: "Antibiotic", dosage: "250mg")
        med.startDate = date(2025, 6, 1)
        med.endDate = date(2025, 6, 7)
        XCTAssertTrue(MedicationService.slots(for: med, on: date(2025, 5, 31)).isEmpty)
        XCTAssertTrue(MedicationService.slots(for: med, on: date(2025, 6, 8)).isEmpty)
        XCTAssertEqual(MedicationService.slots(for: med, on: date(2025, 6, 7)).count, 1)
    }
    func testWeeklyScheduleRespectsWeekdays() {
        let med = Medication(name: "Weekly", dosage: "1")
        med.startDate = date(2025, 1, 1)
        med.frequencyRaw = MedicationFrequency.weekly.rawValue
        let aDay = date(2025, 6, 10)
        let weekday = Calendar.current.component(.weekday, from: aDay)
        med.weekdays = [weekday]
        XCTAssertEqual(MedicationService.slots(for: med, on: aDay).count, 1)
        med.weekdays = [weekday == 1 ? 2 : 1]
        XCTAssertTrue(MedicationService.slots(for: med, on: aDay).isEmpty)
    }

    // Duplicate prevention
    func testDuplicateGivenIsDetected() {
        let med = Medication(name: "Apoquel", dosage: "16mg")
        let slot = DoseSlot(medicationID: med.id, day: date(2025, 6, 10), minutes: 480)
        let entry = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .given, by: "Alex")
        XCTAssertTrue(MedicationService.isAlreadyGiven(slot: slot, administrations: [entry]))
    }
    func testSkippedDoesNotBlockGiven() {
        let med = Medication(name: "Apoquel", dosage: "16mg")
        let slot = DoseSlot(medicationID: med.id, day: date(2025, 6, 10), minutes: 480)
        let entry = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: slot, status: .skipped, by: "Alex")
        XCTAssertFalse(MedicationService.isAlreadyGiven(slot: slot, administrations: [entry]))
    }
    func testOverdueOnlyWhenUnrecordedAndPast() {
        let med = Medication(name: "Apoquel", dosage: "16mg")
        let past = DoseSlot(medicationID: med.id, day: Calendar.current.startOfDay(for: Date()), minutes: 0)
        XCTAssertTrue(MedicationService.isOverdue(slot: past, administrations: [], now: Date()))
        let entry = MedicationAdministration(medicationID: med.id, medicationName: med.name, slot: past, status: .given, by: "Alex")
        XCTAssertFalse(MedicationService.isOverdue(slot: past, administrations: [entry], now: Date()))
    }

    // Household permissions
    func testOwnerCanDoEverything() {
        for permission in CarePermission.allCases {
            XCTAssertTrue(HouseholdPermissions.can(.owner, do: permission))
        }
    }
    func testDogWalkerCannotGiveMedicationOrManageRecords() {
        XCTAssertFalse(HouseholdPermissions.can(.dogWalker, do: .giveMedication))
        XCTAssertFalse(HouseholdPermissions.can(.dogWalker, do: .manageRecords))
        XCTAssertTrue(HouseholdPermissions.can(.dogWalker, do: .logActivity))
    }
    func testViewerIsReadOnly() {
        XCTAssertEqual(HouseholdPermissions.permissions(for: .viewer), [.viewOnly])
    }
    func testPetSitterCanGiveMedicationButNotManagePets() {
        XCTAssertTrue(HouseholdPermissions.can(.petSitter, do: .giveMedication))
        XCTAssertFalse(HouseholdPermissions.can(.petSitter, do: .managePets))
    }

    // Expenses (Decimal-exact)
    func testExpenseTotalsAreExact() {
        let a = PetExpense(amount: Decimal(string: "10.10")!, category: .food)
        let b = PetExpense(amount: Decimal(string: "0.20")!, category: .food)
        XCTAssertEqual(FinancialCalculationService.total([a, b]), Decimal(string: "10.30"))
    }
    func testExpenseTotalsByCategory() {
        let a = PetExpense(amount: Decimal(5), category: .toys)
        let b = PetExpense(amount: Decimal(7), category: .food)
        let totals = FinancialCalculationService.totalsByCategory([a, b])
        XCTAssertEqual(totals.first?.0, .food)
        XCTAssertEqual(totals.first?.1, Decimal(7))
    }

    // Entitlements
    func testFreePlanPetLimit() {
        XCTAssertTrue(EntitlementPolicy.canAddPet(currentCount: 0, isPremium: false))
        XCTAssertFalse(EntitlementPolicy.canAddPet(currentCount: 1, isPremium: false))
        XCTAssertTrue(EntitlementPolicy.canAddPet(currentCount: 9, isPremium: true))
    }

    // Emergency payload gating
    func testEmergencyPayloadIncludesOnlySharedFields() {
        let pet = Pet(name: "Buddy")
        pet.allergies = "Chicken"
        pet.microchipNumber = "123456789"
        let profile = EmergencyProfile(petID: pet.id, petName: pet.name)
        profile.isEnabled = true
        profile.sharedFieldKeys = ["allergies"]
        let payload = EmergencyService.payload(pet: pet, profile: profile, medications: [])
        XCTAssertTrue(payload.contains("Allergies: Chicken"))
        XCTAssertFalse(payload.contains("Microchip"))
    }
    func testEmergencyPayloadEmptyWhenDisabled() {
        let pet = Pet(name: "Buddy")
        pet.allergies = "Chicken"
        let profile = EmergencyProfile(petID: pet.id, petName: pet.name)
        XCTAssertEqual(EmergencyService.payload(pet: pet, profile: profile, medications: []), "")
    }

    // Backup validation
    func testBackupRoundTripValidates() throws {
        let pet = Pet(name: "Buddy")
        pet.breed = "Labrador"
        let data = try BackupService.exportData(pets: [pet])
        let payload = try BackupService.validate(data: data)
        XCTAssertEqual(payload.pets.count, 1)
        XCTAssertEqual(payload.pets.first?.name, "Buddy")
    }
    func testBackupRejectsGarbage() {
        XCTAssertThrowsError(try BackupService.validate(data: Data("not json".utf8)))
    }

    // Vaccination expiry
    func testVaccinationExpiryFlags() {
        let vax = VaccinationRecord(vaccineName: "Rabies", date: date(2024, 1, 1))
        vax.expirationDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())
        XCTAssertTrue(vax.isExpired)
        vax.expirationDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())
        XCTAssertTrue(vax.expiresWithin30Days)
    }

    // Products match the master prompt
    func testProductIDsAndPrices() {
        XCTAssertEqual(PremiumProduct.monthly, "com.petcare360.premium.monthly")
        XCTAssertEqual(PremiumProduct.yearly, "com.petcare360.premium.yearly")
        XCTAssertEqual(PremiumProduct.targetPrices[PremiumProduct.monthly], "$4.99")
        XCTAssertEqual(PremiumProduct.targetPrices[PremiumProduct.yearly], "$29.99")
    }
}
