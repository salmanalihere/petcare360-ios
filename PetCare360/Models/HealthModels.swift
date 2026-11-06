import Foundation
import SwiftData

enum MedicalCategory: String, Codable, CaseIterable {
    case vaccination, appointment, prescription, allergy, condition, surgery, labResult, procedure, weight, dental, insurance, note
    var label: String {
        switch self {
        case .vaccination: return "Vaccination"
        case .appointment: return "Veterinary appointment"
        case .prescription: return "Prescription"
        case .allergy: return "Allergy"
        case .condition: return "Medical condition"
        case .surgery: return "Surgery"
        case .labResult: return "Lab result"
        case .procedure: return "Procedure"
        case .weight: return "Weight"
        case .dental: return "Dental"
        case .insurance: return "Insurance"
        case .note: return "General note"
        }
    }
}

@Model
final class MedicalRecord {
    var id: UUID = UUID()
    var categoryRaw: String = MedicalCategory.note.rawValue
    var title: String = ""
    var details: String = ""
    var date: Date = Date()
    var followUpDate: Date? = nil
    var vetClinic: String = ""
    var editHistory: String = ""   // append-only log of owner corrections
    var createdAt: Date = Date()
    var pet: Pet? = nil
    init(title: String, category: MedicalCategory = .note, date: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.categoryRaw = category.rawValue
        self.date = date
        self.createdAt = Date()
    }
    var category: MedicalCategory { MedicalCategory(rawValue: categoryRaw) ?? .note }
    func recordEdit(note: String, at date: Date = Date()) {
        let stamp = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
        editHistory += editHistory.isEmpty ? "\(stamp): \(note)" : "\n\(stamp): \(note)"
    }
}

@Model
final class VaccinationRecord {
    var id: UUID = UUID()
    var vaccineName: String = ""
    var dateAdministered: Date = Date()
    var expirationDate: Date? = nil
    var clinic: String = ""
    var notes: String = ""
    var pet: Pet? = nil
    init(vaccineName: String, date: Date = Date()) {
        self.id = UUID()
        self.vaccineName = vaccineName
        self.dateAdministered = date
    }
    var isExpired: Bool {
        guard let exp = expirationDate else { return false }
        return exp < Date()
    }
    var expiresWithin30Days: Bool {
        guard let exp = expirationDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 999
        return days >= 0 && days <= 30
    }
}

/// Original uploaded document. The original data is never overwritten;
/// corrections are stored as new records, per the master prompt.
@Model
final class MedicalDocument {
    var id: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = MedicalCategory.note.rawValue
    var createdAt: Date = Date()
    @Attribute(.externalStorage) var originalData: Data? = nil
    var extractedText: String = ""
    var pet: Pet? = nil
    init(title: String) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
    }
    var category: MedicalCategory { MedicalCategory(rawValue: categoryRaw) ?? .note }
}

@Model
final class VetAppointment {
    var id: UUID = UUID()
    var title: String = ""
    var clinic: String = ""
    var vetName: String = ""
    var date: Date = Date()
    var notes: String = ""
    var questions: String = ""        // one question per line
    var followUpDate: Date? = nil
    var isCompleted: Bool = false
    /// Cancellation is a status, not a deletion (2026-11-06):
    /// cancelled appointments stay in the record but never appear
    /// as upcoming and never keep a reminder.
    var isCancelled: Bool = false
    var pet: Pet? = nil
    init(title: String, date: Date) {
        self.id = UUID()
        self.title = title
        self.date = date
    }
    var questionList: [String] {
        questions.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

enum ObservationKind: String, Codable, CaseIterable {
    case weight, appetite, waterIntake, energy, stool, skinCoat, behavior, symptom, activity
    var label: String {
        switch self {
        case .weight: return "Weight"
        case .appetite: return "Appetite"
        case .waterIntake: return "Water intake"
        case .energy: return "Energy"
        case .stool: return "Stool"
        case .skinCoat: return "Skin & coat"
        case .behavior: return "Behavior"
        case .symptom: return "Symptom"
        case .activity: return "Activity"
        }
    }
}

@Model
final class HealthObservation {
    var id: UUID = UUID()
    var kindRaw: String = ObservationKind.behavior.rawValue
    var date: Date = Date()
    var valueText: String = ""
    var weightKg: Double? = nil
    var note: String = ""
    @Attribute(.externalStorage) var photoData: Data? = nil
    var pet: Pet? = nil
    init(kind: ObservationKind, date: Date = Date()) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.date = date
    }
    var kind: ObservationKind { ObservationKind(rawValue: kindRaw) ?? .behavior }
}
