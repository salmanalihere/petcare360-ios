import Foundation
import SwiftData

enum PetSpecies: String, Codable, CaseIterable {
    // Raw values are STORED identifiers (speciesRaw in the database,
    // backups and CloudKit) — existing cases must never be renamed.
    // reptile/horse added 2026-11-06 with new raw values only.
    case dog, cat, bird, rabbit, reptile, horse, other
    var label: String {
        switch self {
        case .reptile: return "Reptiles"
        case .horse: return "Horses"
        default: return rawValue.capitalized
        }
    }
    var icon: String {
        switch self {
        case .dog: return "dog"
        case .cat: return "cat"
        case .bird: return "bird"
        case .rabbit: return "hare"
        case .reptile: return "lizard"
        case .horse: return "horse"
        case .other: return "pawprint"
        }
    }
}

enum PetGender: String, Codable, CaseIterable {
    case male, female, unknown
    var label: String { rawValue.capitalized }
}

@Model
final class Pet {
    var id: UUID = UUID()
    var name: String = ""
    var speciesRaw: String = PetSpecies.dog.rawValue
    var breed: String = ""
    var dateOfBirth: Date? = nil
    var genderRaw: String = PetGender.unknown.rawValue
    var weightKg: Double = 0
    var colorMarkings: String = ""
    var microchipNumber: String = ""
    var adoptionDate: Date? = nil
    var allergies: String = ""
    var medicalConditions: String = ""
    var vetClinic: String = ""
    var vetPhone: String = ""
    var emergencyContactName: String = ""
    var emergencyContactPhone: String = ""
    var insuranceInfo: String = ""
    var notes: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var photoData: Data? = nil

    @Relationship(deleteRule: .cascade) var medications: [Medication] = []
    @Relationship(deleteRule: .cascade) var administrations: [MedicationAdministration] = []
    @Relationship(deleteRule: .cascade) var vaccinations: [VaccinationRecord] = []
    @Relationship(deleteRule: .cascade) var medicalRecords: [MedicalRecord] = []
    @Relationship(deleteRule: .cascade) var appointments: [VetAppointment] = []
    @Relationship(deleteRule: .cascade) var observations: [HealthObservation] = []
    @Relationship(deleteRule: .cascade) var expenses: [PetExpense] = []
    @Relationship(deleteRule: .cascade) var foodSchedules: [FoodSchedule] = []
    @Relationship(deleteRule: .cascade) var documents: [MedicalDocument] = []

    init(name: String, species: PetSpecies = .dog) {
        self.id = UUID()
        self.name = name
        self.speciesRaw = species.rawValue
        self.createdAt = Date()
    }

    var species: PetSpecies { PetSpecies(rawValue: speciesRaw) ?? .other }
    var gender: PetGender { PetGender(rawValue: genderRaw) ?? .unknown }

    /// Age in whole years and months from date of birth, nil when unknown.
    var ageDescription: String? {
        guard let dob = dateOfBirth else { return nil }
        return PetAgeCalculator.describe(dateOfBirth: dob, now: Date())
    }
}

enum PetAgeCalculator {
    static func components(dateOfBirth: Date, now: Date) -> (years: Int, months: Int) {
        let cal = Calendar.current
        let parts = cal.dateComponents([.year, .month], from: dateOfBirth, to: now)
        return (max(parts.year ?? 0, 0), max(parts.month ?? 0, 0))
    }
    static func describe(dateOfBirth: Date, now: Date) -> String {
        let (y, m) = components(dateOfBirth: dateOfBirth, now: now)
        if y > 0 { return "\(y) yr \(m) mo" }
        if m > 0 { return "\(m) mo" }
        let days = Calendar.current.dateComponents([.day], from: dateOfBirth, to: now).day ?? 0
        return "\(max(days, 0)) days"
    }
}

@Model
final class UserProfile {
    var id: UUID = UUID()
    /// Stable identity used for household role resolution and care
    /// attribution. Never a display name (Phase 2, section G).
    var memberID: UUID = UUID()
    var displayName: String = ""
    var email: String = ""
    /// Reminders are ON by default for new profiles (owner brief
    /// 2026-11-07). This default only affects newly created profiles;
    /// existing profiles keep whatever the user chose. iOS still
    /// decides delivery — permission is requested during onboarding
    /// and an in-app ON never implies iOS permission was granted.
    var remindersEnabled: Bool = true
    var hasCompletedOnboarding: Bool = false
    var createdAt: Date = Date()
    init(displayName: String = "") {
        self.id = UUID()
        self.displayName = displayName
        self.createdAt = Date()
    }
}
