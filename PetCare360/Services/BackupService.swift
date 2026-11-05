import Foundation
import SwiftData

/// JSON backup / restore (Phase 2, section E).
///
/// v2 covers EVERY user-data model type, preserving IDs, relationships,
/// dates, Decimal strings and optional fields. Photos and document
/// originals travel as base64 (Foundation's default Data coding).
/// No passwords, tokens or credentials exist in the app, and none are
/// exported. UserProfile (device identity) and SubscriptionEntitlement
/// (StoreKit is the source of truth) are intentionally excluded.
///
/// v1 files (pet profiles only, from 1.0.x) still decode and restore.
enum BackupService {

    // MARK: - v1 (legacy, kept for compatibility)

    struct BackupPayload: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var pets: [PetBackup] = []
    }
    struct PetBackup: Codable {
        var name: String
        var species: String
        var breed: String
        var dateOfBirth: Date?
        var allergies: String
        var medicalConditions: String
        var microchipNumber: String
        var notes: String
    }

    static func exportData(pets: [Pet]) throws -> Data {
        let payload = BackupPayload(pets: pets.map {
            PetBackup(name: $0.name, species: $0.speciesRaw, breed: $0.breed,
                      dateOfBirth: $0.dateOfBirth, allergies: $0.allergies,
                      medicalConditions: $0.medicalConditions,
                      microchipNumber: $0.microchipNumber, notes: $0.notes)
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    static func validate(data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)
        guard payload.version == 1 else {
            throw error("Unsupported backup version \(payload.version).")
        }
        guard payload.pets.allSatisfy({ !$0.name.isEmpty }) else {
            throw error("Every pet in the backup must have a name.")
        }
        return payload
    }

    // MARK: - v2 payload types

    struct FullBackup: Codable {
        var version: Int = 2
        var exportedAt: Date = Date()
        var pets: [PetFull] = []
        var households: [HouseholdFull] = []
        var careTasks: [CareTaskFull] = []
        var careHandoffs: [HandoffFull] = []
        var feedingLogs: [FeedingLogFull] = []
        var insurancePolicies: [PolicyFull] = []
        var emergencyProfiles: [EmergencyFull] = []
        var savedBrands: [BrandFull] = []
        var recallAlerts: [RecallFull] = []
        var medicationSchedules: [ScheduleFull] = []

        var summary: [(String, Int)] {
            [("Pets", pets.count),
             ("Medications", pets.reduce(0) { $0 + $1.medications.count }),
             ("Administrations", pets.reduce(0) { $0 + $1.administrations.count }),
             ("Vaccinations", pets.reduce(0) { $0 + $1.vaccinations.count }),
             ("Medical records", pets.reduce(0) { $0 + $1.medicalRecords.count }),
             ("Documents", pets.reduce(0) { $0 + $1.documents.count }),
             ("Appointments", pets.reduce(0) { $0 + $1.appointments.count }),
             ("Observations", pets.reduce(0) { $0 + $1.observations.count }),
             ("Expenses", pets.reduce(0) { $0 + $1.expenses.count }),
             ("Feeding schedules", pets.reduce(0) { $0 + $1.foodSchedules.count }),
             ("Insurance policies", insurancePolicies.count),
             ("Households", households.count),
             ("Care tasks", careTasks.count),
             ("Care handoffs", careHandoffs.count),
             ("Feeding logs", feedingLogs.count),
             ("Emergency profiles", emergencyProfiles.count),
             ("Saved brands", savedBrands.count)]
            .filter { $0.1 > 0 }
        }
    }

    struct PetFull: Codable {
        var id: UUID; var name: String; var speciesRaw: String; var breed: String
        var dateOfBirth: Date?; var genderRaw: String; var weightKg: Double
        var colorMarkings: String; var microchipNumber: String; var adoptionDate: Date?
        var allergies: String; var medicalConditions: String
        var vetClinic: String; var vetPhone: String
        var emergencyContactName: String; var emergencyContactPhone: String
        var insuranceInfo: String; var notes: String; var isArchived: Bool
        var createdAt: Date; var photoData: Data?
        var medications: [MedicationFull] = []
        var administrations: [AdministrationFull] = []
        var vaccinations: [VaccinationFull] = []
        var medicalRecords: [RecordFull] = []
        var documents: [DocumentFull] = []
        var appointments: [AppointmentFull] = []
        var observations: [ObservationFull] = []
        var expenses: [ExpenseFull] = []
        var foodSchedules: [FoodFull] = []
    }
    struct MedicationFull: Codable {
        var id: UUID; var name: String; var dosage: String; var instructions: String
        var frequencyRaw: String; var startDate: Date; var endDate: Date?
        var doseMinutes: [Int]; var weekdays: [Int]; var prescribingVet: String
        var remainingSupply: Int; var refillThreshold: Int; var isActive: Bool
        var prescriptionDocumentID: UUID?; var createdAt: Date
    }
    struct AdministrationFull: Codable {
        var id: UUID; var medicationID: UUID; var medicationName: String
        var scheduledDay: Date; var scheduledMinutes: Int; var statusRaw: String
        var administeredAt: Date; var administeredBy: String
        var administeredByMemberID: UUID?; var note: String
    }
    struct VaccinationFull: Codable {
        var id: UUID; var vaccineName: String; var dateAdministered: Date
        var expirationDate: Date?; var clinic: String; var notes: String
    }
    struct RecordFull: Codable {
        var id: UUID; var categoryRaw: String; var title: String; var details: String
        var date: Date; var followUpDate: Date?; var vetClinic: String
        var editHistory: String; var createdAt: Date
    }
    struct DocumentFull: Codable {
        var id: UUID; var title: String; var categoryRaw: String
        var createdAt: Date; var originalData: Data?; var extractedText: String
    }
    struct AppointmentFull: Codable {
        var id: UUID; var title: String; var clinic: String; var vetName: String
        var date: Date; var notes: String; var questions: String
        var followUpDate: Date?; var isCompleted: Bool
    }
    struct ObservationFull: Codable {
        var id: UUID; var kindRaw: String; var date: Date; var valueText: String
        var weightKg: Double?; var note: String; var photoData: Data?
    }
    struct ExpenseFull: Codable {
        var id: UUID; var amountString: String; var date: Date
        var categoryRaw: String; var vendor: String; var notes: String
        var receiptData: Data?
    }
    struct FoodFull: Codable {
        var id: UUID; var foodBrand: String; var foodType: String; var portion: String
        var timeMinutes: Int; var frequencyNote: String; var instructions: String
        var transitionNote: String; var isActive: Bool; var packagingPhotoData: Data?
    }
    struct HouseholdFull: Codable {
        var id: UUID; var name: String; var createdAt: Date
        var members: [MemberFull] = []
    }
    struct MemberFull: Codable {
        var id: UUID; var displayName: String; var roleRaw: String
        var invitedEmail: String; var isInvitationPending: Bool
        var accessExpiresAt: Date?; var joinedAt: Date
    }
    struct CareTaskFull: Codable {
        var id: UUID; var petID: UUID; var petName: String; var kindRaw: String
        var title: String; var scheduledDate: Date; var assignedTo: String
        var isCompleted: Bool; var completedBy: String; var completedAt: Date?
        var createdAt: Date
    }
    struct HandoffFull: Codable {
        var id: UUID; var petName: String; var petID: UUID?; var authorName: String
        var authorMemberID: UUID?; var date: Date; var wasFed: Bool
        var medicationGiven: Bool; var walkCompleted: Bool; var appetiteNormal: Bool
        var unusualBehavior: String; var notes: String
    }
    struct FeedingLogFull: Codable {
        var id: UUID; var petID: UUID; var petName: String; var date: Date
        var fedBy: String; var portionGiven: String
    }
    struct PolicyFull: Codable {
        var id: UUID; var petID: UUID; var petName: String; var provider: String
        var policyNumber: String; var coverageDetails: String; var startDate: Date
        var renewalDate: Date?; var deductibleString: String
        var reimbursementPercent: Int
        var claims: [ClaimFull] = []
    }
    struct ClaimFull: Codable {
        var id: UUID; var title: String; var amountString: String
        var statusRaw: String; var date: Date; var notes: String
    }
    struct EmergencyFull: Codable {
        var id: UUID; var petID: UUID; var petName: String
        var sharedFieldKeys: [String]; var isEnabled: Bool; var updatedAt: Date
    }
    struct BrandFull: Codable { var id: UUID; var brand: String; var productName: String; var manufacturer: String }
    struct RecallFull: Codable {
        var id: UUID; var productName: String; var manufacturer: String
        var recallDate: Date; var reason: String; var affectedDetails: String
        var sourceURL: String; var savedBrand: String; var createdAt: Date
    }
    struct ScheduleFull: Codable {
        var id: UUID; var medicationID: UUID; var reminderEnabled: Bool
        var snoozeMinutes: Int; var createdAt: Date
    }

    // MARK: - v2 export

    static func makeFullBackup(pets: [Pet], households: [Household], careTasks: [CareTask],
                               careHandoffs: [CareHandoff], feedingLogs: [FeedingLog],
                               insurancePolicies: [InsurancePolicy], emergencyProfiles: [EmergencyProfile],
                               savedBrands: [SavedFoodBrand], recallAlerts: [RecallAlert],
                               medicationSchedules: [MedicationSchedule]) -> FullBackup {
        var backup = FullBackup()
        backup.pets = pets.map { pet in
            var full = PetFull(
                id: pet.id, name: pet.name, speciesRaw: pet.speciesRaw, breed: pet.breed,
                dateOfBirth: pet.dateOfBirth, genderRaw: pet.genderRaw, weightKg: pet.weightKg,
                colorMarkings: pet.colorMarkings, microchipNumber: pet.microchipNumber,
                adoptionDate: pet.adoptionDate, allergies: pet.allergies,
                medicalConditions: pet.medicalConditions, vetClinic: pet.vetClinic,
                vetPhone: pet.vetPhone, emergencyContactName: pet.emergencyContactName,
                emergencyContactPhone: pet.emergencyContactPhone, insuranceInfo: pet.insuranceInfo,
                notes: pet.notes, isArchived: pet.isArchived, createdAt: pet.createdAt,
                photoData: pet.photoData)
            full.medications = pet.medications.map {
                MedicationFull(id: $0.id, name: $0.name, dosage: $0.dosage, instructions: $0.instructions,
                               frequencyRaw: $0.frequencyRaw, startDate: $0.startDate, endDate: $0.endDate,
                               doseMinutes: $0.doseMinutes, weekdays: $0.weekdays, prescribingVet: $0.prescribingVet,
                               remainingSupply: $0.remainingSupply, refillThreshold: $0.refillThreshold,
                               isActive: $0.isActive, prescriptionDocumentID: $0.prescriptionDocumentID,
                               createdAt: $0.createdAt)
            }
            full.administrations = pet.administrations.map {
                AdministrationFull(id: $0.id, medicationID: $0.medicationID, medicationName: $0.medicationName,
                                   scheduledDay: $0.scheduledDay, scheduledMinutes: $0.scheduledMinutes,
                                   statusRaw: $0.statusRaw, administeredAt: $0.administeredAt,
                                   administeredBy: $0.administeredBy, administeredByMemberID: $0.administeredByMemberID,
                                   note: $0.note)
            }
            full.vaccinations = pet.vaccinations.map {
                VaccinationFull(id: $0.id, vaccineName: $0.vaccineName, dateAdministered: $0.dateAdministered,
                                expirationDate: $0.expirationDate, clinic: $0.clinic, notes: $0.notes)
            }
            full.medicalRecords = pet.medicalRecords.map {
                RecordFull(id: $0.id, categoryRaw: $0.categoryRaw, title: $0.title, details: $0.details,
                           date: $0.date, followUpDate: $0.followUpDate, vetClinic: $0.vetClinic,
                           editHistory: $0.editHistory, createdAt: $0.createdAt)
            }
            full.documents = pet.documents.map {
                DocumentFull(id: $0.id, title: $0.title, categoryRaw: $0.categoryRaw,
                             createdAt: $0.createdAt, originalData: $0.originalData, extractedText: $0.extractedText)
            }
            full.appointments = pet.appointments.map {
                AppointmentFull(id: $0.id, title: $0.title, clinic: $0.clinic, vetName: $0.vetName,
                                date: $0.date, notes: $0.notes, questions: $0.questions,
                                followUpDate: $0.followUpDate, isCompleted: $0.isCompleted)
            }
            full.observations = pet.observations.map {
                ObservationFull(id: $0.id, kindRaw: $0.kindRaw, date: $0.date, valueText: $0.valueText,
                                weightKg: $0.weightKg, note: $0.note, photoData: $0.photoData)
            }
            full.expenses = pet.expenses.map {
                ExpenseFull(id: $0.id, amountString: $0.amountString, date: $0.date,
                            categoryRaw: $0.categoryRaw, vendor: $0.vendor, notes: $0.notes,
                            receiptData: $0.receiptData)
            }
            full.foodSchedules = pet.foodSchedules.map {
                FoodFull(id: $0.id, foodBrand: $0.foodBrand, foodType: $0.foodType, portion: $0.portion,
                         timeMinutes: $0.timeMinutes, frequencyNote: $0.frequencyNote,
                         instructions: $0.instructions, transitionNote: $0.transitionNote,
                         isActive: $0.isActive, packagingPhotoData: $0.packagingPhotoData)
            }
            return full
        }
        backup.households = households.map { household in
            var full = HouseholdFull(id: household.id, name: household.name, createdAt: household.createdAt)
            full.members = household.members.map {
                MemberFull(id: $0.id, displayName: $0.displayName, roleRaw: $0.roleRaw,
                           invitedEmail: $0.invitedEmail, isInvitationPending: $0.isInvitationPending,
                           accessExpiresAt: $0.accessExpiresAt, joinedAt: $0.joinedAt)
            }
            return full
        }
        backup.careTasks = careTasks.map {
            CareTaskFull(id: $0.id, petID: $0.petID, petName: $0.petName, kindRaw: $0.kindRaw,
                         title: $0.title, scheduledDate: $0.scheduledDate, assignedTo: $0.assignedTo,
                         isCompleted: $0.isCompleted, completedBy: $0.completedBy,
                         completedAt: $0.completedAt, createdAt: $0.createdAt)
        }
        backup.careHandoffs = careHandoffs.map {
            HandoffFull(id: $0.id, petName: $0.petName, petID: $0.petID, authorName: $0.authorName,
                        authorMemberID: $0.authorMemberID, date: $0.date, wasFed: $0.wasFed,
                        medicationGiven: $0.medicationGiven, walkCompleted: $0.walkCompleted,
                        appetiteNormal: $0.appetiteNormal, unusualBehavior: $0.unusualBehavior,
                        notes: $0.notes)
        }
        backup.feedingLogs = feedingLogs.map {
            FeedingLogFull(id: $0.id, petID: $0.petID, petName: $0.petName, date: $0.date,
                           fedBy: $0.fedBy, portionGiven: $0.portionGiven)
        }
        backup.insurancePolicies = insurancePolicies.map { policy in
            var full = PolicyFull(id: policy.id, petID: policy.petID, petName: policy.petName,
                                  provider: policy.provider, policyNumber: policy.policyNumber,
                                  coverageDetails: policy.coverageDetails, startDate: policy.startDate,
                                  renewalDate: policy.renewalDate, deductibleString: policy.deductibleString,
                                  reimbursementPercent: policy.reimbursementPercent)
            full.claims = policy.claims.map {
                ClaimFull(id: $0.id, title: $0.title, amountString: $0.amountString,
                          statusRaw: $0.statusRaw, date: $0.date, notes: $0.notes)
            }
            return full
        }
        backup.emergencyProfiles = emergencyProfiles.map {
            EmergencyFull(id: $0.id, petID: $0.petID, petName: $0.petName,
                          sharedFieldKeys: $0.sharedFieldKeys, isEnabled: $0.isEnabled, updatedAt: $0.updatedAt)
        }
        backup.savedBrands = savedBrands.map {
            BrandFull(id: $0.id, brand: $0.brand, productName: $0.productName, manufacturer: $0.manufacturer)
        }
        backup.recallAlerts = recallAlerts.map {
            RecallFull(id: $0.id, productName: $0.productName, manufacturer: $0.manufacturer,
                       recallDate: $0.recallDate, reason: $0.reason, affectedDetails: $0.affectedDetails,
                       sourceURL: $0.sourceURL, savedBrand: $0.savedBrand, createdAt: $0.createdAt)
        }
        backup.medicationSchedules = medicationSchedules.map {
            ScheduleFull(id: $0.id, medicationID: $0.medicationID, reminderEnabled: $0.reminderEnabled,
                         snoozeMinutes: $0.snoozeMinutes, createdAt: $0.createdAt)
        }
        return backup
    }

    static func encode(_ backup: FullBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    // MARK: - v2 validation

    static func decodeFull(data: Data) throws -> FullBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(FullBackup.self, from: data)
        guard backup.version == 2 else {
            throw error("Unsupported backup version \(backup.version).")
        }
        guard backup.pets.allSatisfy({ !$0.name.isEmpty }) else {
            throw error("Every pet in the backup must have a name.")
        }
        // Duplicate-ID detection: restoring the same ID twice would create
        // ambiguous relationships, so the whole file is rejected.
        var seen: Set<UUID> = []
        func check(_ id: UUID, _ kind: String) throws {
            guard seen.insert(id).inserted else {
                throw error("Duplicate \(kind) ID in backup (\(id)). The file was not imported.")
            }
        }
        for pet in backup.pets {
            try check(pet.id, "pet")
            for item in pet.medications { try check(item.id, "medication") }
            for item in pet.administrations { try check(item.id, "administration") }
            for item in pet.vaccinations { try check(item.id, "vaccination") }
            for item in pet.medicalRecords { try check(item.id, "medical record") }
            for item in pet.documents { try check(item.id, "document") }
            for item in pet.appointments { try check(item.id, "appointment") }
            for item in pet.observations { try check(item.id, "observation") }
            for item in pet.expenses { try check(item.id, "expense") }
            for item in pet.foodSchedules { try check(item.id, "feeding schedule") }
        }
        for household in backup.households {
            try check(household.id, "household")
            for member in household.members { try check(member.id, "household member") }
        }
        for policy in backup.insurancePolicies {
            try check(policy.id, "insurance policy")
            for claim in policy.claims { try check(claim.id, "insurance claim") }
        }
        return backup
    }

    enum ImportSource {
        case v2(FullBackup)
        case v1(BackupPayload)
    }

    static func decodeAny(data: Data) throws -> ImportSource {
        if let full = try? decodeFull(data: data) { return .v2(full) }
        return .v1(try validate(data: data))
    }

    // MARK: - v2 restore

    enum RestoreStrategy {
        /// Skip any record whose ID already exists. Nothing is overwritten.
        case merge
        /// Delete all existing user data first, then import everything.
        case replace
    }

    struct RestoreSummary {
        var inserted: Int = 0
        var skipped: Int = 0
    }

    /// Restores a validated v2 backup. Everything is inserted and saved in
    /// one pass; if saving fails the context is rolled back so a failed
    /// import never leaves partial data behind.
    @MainActor
    static func restore(_ backup: FullBackup, into context: ModelContext,
                        strategy: RestoreStrategy) throws -> RestoreSummary {
        var summary = RestoreSummary()
        // EVERYTHING happens inside this do/catch (v1.2.8): if the
        // Replace deletion, any fetch, any import step or the final
        // save fails, the context is rolled back — never a partially
        // deleted or partially imported database.
        do {
        if strategy == .replace {
            try deleteEverything(in: context)
        }
        // Index everything that already exists ONCE (after the Replace
        // deletion above, so its ID sets are correctly empty). Merge
        // works PER RECORD (v1.2.4 correction): an existing pet no
        // longer causes its new records to be skipped — each child
        // record is checked by its own ID, existing records are kept
        // untouched, and only records whose IDs are new are inserted.
        func existingIDs<T: PersistentModel>(_ type: T.Type, keyPath: KeyPath<T, UUID>) throws -> Set<UUID> {
            Set(try context.fetch(FetchDescriptor<T>()).map { $0[keyPath: keyPath] })
        }
        let taskIDs = try existingIDs(CareTask.self, keyPath: \.id)
        let handoffIDs = try existingIDs(CareHandoff.self, keyPath: \.id)
        let logIDs = try existingIDs(FeedingLog.self, keyPath: \.id)
        let emergencyIDs = try existingIDs(EmergencyProfile.self, keyPath: \.id)
        let brandIDs = try existingIDs(SavedFoodBrand.self, keyPath: \.id)
        let alertIDs = try existingIDs(RecallAlert.self, keyPath: \.id)
        let scheduleIDs = try existingIDs(MedicationSchedule.self, keyPath: \.id)
        var petsByID: [UUID: Pet] = [:]
        for pet in try context.fetch(FetchDescriptor<Pet>()) { petsByID[pet.id] = pet }
        var householdsByID: [UUID: Household] = [:]
        for household in try context.fetch(FetchDescriptor<Household>()) { householdsByID[household.id] = household }
        var policiesByID: [UUID: InsurancePolicy] = [:]
        for policy in try context.fetch(FetchDescriptor<InsurancePolicy>()) { policiesByID[policy.id] = policy }

            // Households: merge members per record.
            for householdFull in backup.households {
                let household: Household
                if let existing = householdsByID[householdFull.id] {
                    household = existing
                    summary.skipped += 1   // the household record itself already existed (v1.2.8)
                } else {
                    household = Household(name: householdFull.name)
                    household.id = householdFull.id
                    household.createdAt = householdFull.createdAt
                    context.insert(household)
                    householdsByID[household.id] = household
                    summary.inserted += 1
                }
                let memberIDs = Set(household.members.map { $0.id })
                summary.skipped += householdFull.members.count - householdFull.members.filter { !memberIDs.contains($0.id) }.count
                for memberFull in householdFull.members where !memberIDs.contains(memberFull.id) {
                    let member = HouseholdMember(displayName: memberFull.displayName,
                                                 role: HouseholdRole(rawValue: memberFull.roleRaw) ?? .viewer)
                    member.id = memberFull.id
                    member.invitedEmail = memberFull.invitedEmail
                    member.isInvitationPending = memberFull.isInvitationPending
                    member.accessExpiresAt = memberFull.accessExpiresAt
                    member.joinedAt = memberFull.joinedAt
                    member.household = household
                    context.insert(member)
                    summary.inserted += 1
                }
            }
            // Pets: merge every child collection per record.
            for petFull in backup.pets {
                let pet: Pet
                if let existing = petsByID[petFull.id] {
                    pet = existing   // profile kept as-is; only records merge
                    summary.skipped += 1   // the pet profile itself already existed (v1.2.8)
                } else {
                    pet = Pet(name: petFull.name, species: PetSpecies(rawValue: petFull.speciesRaw) ?? .other)
                    pet.id = petFull.id
                    pet.breed = petFull.breed; pet.dateOfBirth = petFull.dateOfBirth
                    pet.genderRaw = petFull.genderRaw; pet.weightKg = petFull.weightKg
                    pet.colorMarkings = petFull.colorMarkings; pet.microchipNumber = petFull.microchipNumber
                    pet.adoptionDate = petFull.adoptionDate; pet.allergies = petFull.allergies
                    pet.medicalConditions = petFull.medicalConditions; pet.vetClinic = petFull.vetClinic
                    pet.vetPhone = petFull.vetPhone; pet.emergencyContactName = petFull.emergencyContactName
                    pet.emergencyContactPhone = petFull.emergencyContactPhone; pet.insuranceInfo = petFull.insuranceInfo
                    pet.notes = petFull.notes; pet.isArchived = petFull.isArchived
                    pet.createdAt = petFull.createdAt; pet.photoData = petFull.photoData
                    context.insert(pet)
                    petsByID[pet.id] = pet
                    summary.inserted += 1
                }
                let medIDs = Set(pet.medications.map { $0.id })
                for item in petFull.medications where !medIDs.contains(item.id) {
                    let med = Medication(name: item.name, dosage: item.dosage)
                    med.id = item.id; med.instructions = item.instructions
                    med.frequencyRaw = item.frequencyRaw; med.startDate = item.startDate
                    med.endDate = item.endDate; med.doseMinutes = item.doseMinutes
                    med.weekdays = item.weekdays; med.prescribingVet = item.prescribingVet
                    med.remainingSupply = item.remainingSupply; med.refillThreshold = item.refillThreshold
                    med.isActive = item.isActive; med.prescriptionDocumentID = item.prescriptionDocumentID
                    med.createdAt = item.createdAt; med.pet = pet
                    context.insert(med); summary.inserted += 1
                }
                let adminIDs = Set(pet.administrations.map { $0.id })
                for item in petFull.administrations where !adminIDs.contains(item.id) {
                    let slot = DoseSlot(medicationID: item.medicationID, day: item.scheduledDay, minutes: item.scheduledMinutes)
                    let entry = MedicationAdministration(medicationID: item.medicationID, medicationName: item.medicationName,
                                                         slot: slot, status: AdministrationStatus(rawValue: item.statusRaw) ?? .given,
                                                         by: item.administeredBy)
                    entry.id = item.id; entry.administeredAt = item.administeredAt
                    entry.administeredByMemberID = item.administeredByMemberID; entry.note = item.note
                    entry.pet = pet
                    context.insert(entry); summary.inserted += 1
                }
                let vaxIDs = Set(pet.vaccinations.map { $0.id })
                for item in petFull.vaccinations where !vaxIDs.contains(item.id) {
                    let vax = VaccinationRecord(vaccineName: item.vaccineName, date: item.dateAdministered)
                    vax.id = item.id; vax.expirationDate = item.expirationDate
                    vax.clinic = item.clinic; vax.notes = item.notes; vax.pet = pet
                    context.insert(vax); summary.inserted += 1
                }
                let recordIDs = Set(pet.medicalRecords.map { $0.id })
                for item in petFull.medicalRecords where !recordIDs.contains(item.id) {
                    let record = MedicalRecord(title: item.title,
                                               category: MedicalCategory(rawValue: item.categoryRaw) ?? .note,
                                               date: item.date)
                    record.id = item.id; record.details = item.details
                    record.followUpDate = item.followUpDate; record.vetClinic = item.vetClinic
                    record.editHistory = item.editHistory; record.createdAt = item.createdAt
                    record.pet = pet
                    context.insert(record); summary.inserted += 1
                }
                let documentIDs = Set(pet.documents.map { $0.id })
                for item in petFull.documents where !documentIDs.contains(item.id) {
                    let doc = MedicalDocument(title: item.title)
                    doc.id = item.id; doc.categoryRaw = item.categoryRaw
                    doc.createdAt = item.createdAt; doc.originalData = item.originalData
                    doc.extractedText = item.extractedText; doc.pet = pet
                    context.insert(doc); summary.inserted += 1
                }
                let appointmentIDs = Set(pet.appointments.map { $0.id })
                for item in petFull.appointments where !appointmentIDs.contains(item.id) {
                    let appt = VetAppointment(title: item.title, date: item.date)
                    appt.id = item.id; appt.clinic = item.clinic; appt.vetName = item.vetName
                    appt.notes = item.notes; appt.questions = item.questions
                    appt.followUpDate = item.followUpDate; appt.isCompleted = item.isCompleted
                    appt.pet = pet
                    context.insert(appt); summary.inserted += 1
                }
                let observationIDs = Set(pet.observations.map { $0.id })
                for item in petFull.observations where !observationIDs.contains(item.id) {
                    let obs = HealthObservation(kind: ObservationKind(rawValue: item.kindRaw) ?? .behavior, date: item.date)
                    obs.id = item.id; obs.valueText = item.valueText; obs.weightKg = item.weightKg
                    obs.note = item.note; obs.photoData = item.photoData; obs.pet = pet
                    context.insert(obs); summary.inserted += 1
                }
                let expenseIDs = Set(pet.expenses.map { $0.id })
                for item in petFull.expenses where !expenseIDs.contains(item.id) {
                    let expense = PetExpense(amount: Decimal(string: item.amountString) ?? 0,
                                             category: ExpenseCategory(rawValue: item.categoryRaw) ?? .other,
                                             date: item.date)
                    expense.id = item.id; expense.vendor = item.vendor
                    expense.notes = item.notes; expense.receiptData = item.receiptData
                    expense.pet = pet
                    context.insert(expense); summary.inserted += 1
                }
                let foodIDs = Set(pet.foodSchedules.map { $0.id })
                for item in petFull.foodSchedules where !foodIDs.contains(item.id) {
                    let food = FoodSchedule(brand: item.foodBrand)
                    food.id = item.id; food.foodType = item.foodType; food.portion = item.portion
                    food.timeMinutes = item.timeMinutes; food.frequencyNote = item.frequencyNote
                    food.instructions = item.instructions; food.transitionNote = item.transitionNote
                    food.isActive = item.isActive; food.packagingPhotoData = item.packagingPhotoData
                    food.pet = pet
                    context.insert(food); summary.inserted += 1
                }
                // Count records that existed already as kept/skipped.
                summary.skipped += petFull.medications.count - petFull.medications.filter { !medIDs.contains($0.id) }.count
                summary.skipped += petFull.administrations.count - petFull.administrations.filter { !adminIDs.contains($0.id) }.count
                summary.skipped += petFull.vaccinations.count - petFull.vaccinations.filter { !vaxIDs.contains($0.id) }.count
                summary.skipped += petFull.medicalRecords.count - petFull.medicalRecords.filter { !recordIDs.contains($0.id) }.count
                summary.skipped += petFull.documents.count - petFull.documents.filter { !documentIDs.contains($0.id) }.count
                summary.skipped += petFull.appointments.count - petFull.appointments.filter { !appointmentIDs.contains($0.id) }.count
                summary.skipped += petFull.observations.count - petFull.observations.filter { !observationIDs.contains($0.id) }.count
                summary.skipped += petFull.expenses.count - petFull.expenses.filter { !expenseIDs.contains($0.id) }.count
                summary.skipped += petFull.foodSchedules.count - petFull.foodSchedules.filter { !foodIDs.contains($0.id) }.count
            }
            summary.skipped += backup.careTasks.count - backup.careTasks.filter { !taskIDs.contains($0.id) }.count
            for item in backup.careTasks where !taskIDs.contains(item.id) {
                let task = CareTask(title: item.title, petID: item.petID, petName: item.petName,
                                    kind: CareTaskKind(rawValue: item.kindRaw) ?? .other, date: item.scheduledDate)
                task.id = item.id; task.assignedTo = item.assignedTo
                task.isCompleted = item.isCompleted; task.completedBy = item.completedBy
                task.completedAt = item.completedAt; task.createdAt = item.createdAt
                context.insert(task); summary.inserted += 1
            }
            summary.skipped += backup.careHandoffs.count - backup.careHandoffs.filter { !handoffIDs.contains($0.id) }.count
            for item in backup.careHandoffs where !handoffIDs.contains(item.id) {
                let handoff = CareHandoff(petName: item.petName, author: item.authorName)
                handoff.id = item.id; handoff.petID = item.petID
                handoff.authorMemberID = item.authorMemberID
                handoff.date = item.date; handoff.wasFed = item.wasFed
                handoff.medicationGiven = item.medicationGiven; handoff.walkCompleted = item.walkCompleted
                handoff.appetiteNormal = item.appetiteNormal; handoff.unusualBehavior = item.unusualBehavior
                handoff.notes = item.notes
                context.insert(handoff); summary.inserted += 1
            }
            summary.skipped += backup.feedingLogs.count - backup.feedingLogs.filter { !logIDs.contains($0.id) }.count
            for item in backup.feedingLogs where !logIDs.contains(item.id) {
                let log = FeedingLog(petID: item.petID, petName: item.petName, by: item.fedBy)
                log.id = item.id; log.date = item.date; log.portionGiven = item.portionGiven
                context.insert(log); summary.inserted += 1
            }
            // Insurance: merge claims per record into existing policies.
            for item in backup.insurancePolicies {
                let policy: InsurancePolicy
                if let existing = policiesByID[item.id] {
                    policy = existing
                    summary.skipped += 1   // the policy record itself already existed
                } else {
                    policy = InsurancePolicy(provider: item.provider, petID: item.petID, petName: item.petName)
                    policy.id = item.id; policy.policyNumber = item.policyNumber
                    policy.coverageDetails = item.coverageDetails; policy.startDate = item.startDate
                    policy.renewalDate = item.renewalDate; policy.deductibleString = item.deductibleString
                    policy.reimbursementPercent = item.reimbursementPercent
                    context.insert(policy); summary.inserted += 1
                    policiesByID[policy.id] = policy
                }
                let claimIDs = Set(policy.claims.map { $0.id })
                summary.skipped += item.claims.count - item.claims.filter { !claimIDs.contains($0.id) }.count
                for claimFull in item.claims where !claimIDs.contains(claimFull.id) {
                    let claim = InsuranceClaim(title: claimFull.title, amount: Decimal(string: claimFull.amountString) ?? 0)
                    claim.id = claimFull.id; claim.statusRaw = claimFull.statusRaw
                    claim.date = claimFull.date; claim.notes = claimFull.notes
                    claim.policy = policy
                    context.insert(claim); summary.inserted += 1
                }
            }
            summary.skipped += backup.emergencyProfiles.count - backup.emergencyProfiles.filter { !emergencyIDs.contains($0.id) }.count
            for item in backup.emergencyProfiles where !emergencyIDs.contains(item.id) {
                let profile = EmergencyProfile(petID: item.petID, petName: item.petName)
                profile.id = item.id; profile.sharedFieldKeys = item.sharedFieldKeys
                profile.isEnabled = item.isEnabled; profile.updatedAt = item.updatedAt
                context.insert(profile); summary.inserted += 1
            }
            summary.skipped += backup.savedBrands.count - backup.savedBrands.filter { !brandIDs.contains($0.id) }.count
            for item in backup.savedBrands where !brandIDs.contains(item.id) {
                let brand = SavedFoodBrand(brand: item.brand)
                brand.id = item.id; brand.productName = item.productName; brand.manufacturer = item.manufacturer
                context.insert(brand); summary.inserted += 1
            }
            summary.skipped += backup.recallAlerts.count - backup.recallAlerts.filter { !alertIDs.contains($0.id) }.count
            for item in backup.recallAlerts where !alertIDs.contains(item.id) {
                let alert = RecallAlert(productName: item.productName, manufacturer: item.manufacturer, sourceURL: item.sourceURL)
                alert.id = item.id; alert.recallDate = item.recallDate; alert.reason = item.reason
                alert.affectedDetails = item.affectedDetails; alert.savedBrand = item.savedBrand
                alert.createdAt = item.createdAt
                context.insert(alert); summary.inserted += 1
            }
            summary.skipped += backup.medicationSchedules.count - backup.medicationSchedules.filter { !scheduleIDs.contains($0.id) }.count
            for item in backup.medicationSchedules where !scheduleIDs.contains(item.id) {
                let schedule = MedicationSchedule(medicationID: item.medicationID)
                schedule.id = item.id; schedule.reminderEnabled = item.reminderEnabled
                schedule.snoozeMinutes = item.snoozeMinutes; schedule.createdAt = item.createdAt
                context.insert(schedule); summary.inserted += 1
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return summary
    }

    /// Deletes every user-data model type (used by Replace restores).
    /// UserProfile is kept so the device identity survives a restore.
    @MainActor
    static func deleteEverything(in context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<Pet>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Household>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<CareTask>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<CareHandoff>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<FeedingLog>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<InsurancePolicy>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<EmergencyProfile>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<SavedFoodBrand>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<RecallAlert>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<MedicationSchedule>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<SubscriptionEntitlement>()) { context.delete(item) }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "PetCare360.Backup", code: 10,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
