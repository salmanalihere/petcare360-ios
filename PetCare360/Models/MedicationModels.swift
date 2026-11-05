import Foundation
import SwiftData

enum MedicationFrequency: String, Codable, CaseIterable {
    case onceDaily, twiceDaily, multipleDaily, weekly, custom, temporary
    var label: String {
        switch self {
        case .onceDaily: return "Once daily"
        case .twiceDaily: return "Twice daily"
        case .multipleDaily: return "Multiple times daily"
        case .weekly: return "Weekly"
        case .custom: return "Custom schedule"
        case .temporary: return "Temporary course"
        }
    }
}

enum AdministrationStatus: String, Codable, CaseIterable {
    case given, skipped, delayed
    var label: String { rawValue.capitalized }
}

@Model
final class Medication {
    var id: UUID = UUID()
    var name: String = ""
    var dosage: String = ""
    var instructions: String = ""
    var frequencyRaw: String = MedicationFrequency.onceDaily.rawValue
    var startDate: Date = Date()
    var endDate: Date? = nil
    /// Minutes from midnight for each scheduled dose, sorted.
    var doseMinutes: [Int] = [480]
    /// Weekdays (1 = Sunday ... 7 = Saturday) for weekly schedules; empty = every day.
    var weekdays: [Int] = []
    var prescribingVet: String = ""
    var remainingSupply: Int = 0
    var refillThreshold: Int = 5
    var isActive: Bool = true
    /// Optional link to a MedicalDocument holding the prescription.
    /// The document itself lives in the pet's document store (no duplicate
    /// storage); this is only its identifier.
    var prescriptionDocumentID: UUID? = nil
    var createdAt: Date = Date()
    var pet: Pet? = nil

    init(name: String, dosage: String = "") {
        self.id = UUID()
        self.name = name
        self.dosage = dosage
        self.createdAt = Date()
        self.startDate = Date()
    }

    var frequency: MedicationFrequency { MedicationFrequency(rawValue: frequencyRaw) ?? .onceDaily }
    var needsRefill: Bool { isActive && remainingSupply <= refillThreshold }
}

/// One scheduled dose slot for a medication on a specific day.
struct DoseSlot: Equatable, Hashable {
    let medicationID: UUID
    let day: Date       // start-of-day in the schedule time zone
    let minutes: Int    // minutes from midnight
    var scheduledDate: Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }
}

@Model
final class MedicationAdministration {
    var id: UUID = UUID()
    var medicationID: UUID = UUID()
    var medicationName: String = ""
    var scheduledDay: Date = Date()   // start-of-day of the scheduled slot
    var scheduledMinutes: Int = 0
    var statusRaw: String = AdministrationStatus.given.rawValue
    var administeredAt: Date = Date()
    var administeredBy: String = ""
    /// Stable member identity of whoever recorded this entry (Phase 2).
    /// `administeredBy` remains the human-readable display name.
    var administeredByMemberID: UUID? = nil
    var note: String = ""
    var pet: Pet? = nil

    init(medicationID: UUID, medicationName: String, slot: DoseSlot, status: AdministrationStatus, by: String) {
        self.id = UUID()
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.scheduledDay = slot.day
        self.scheduledMinutes = slot.minutes
        self.statusRaw = status.rawValue
        self.administeredBy = by
        self.administeredAt = Date()
    }

    var status: AdministrationStatus { AdministrationStatus(rawValue: statusRaw) ?? .given }
    var slot: DoseSlot { DoseSlot(medicationID: medicationID, day: scheduledDay, minutes: scheduledMinutes) }
}

@Model
final class MedicationSchedule {
    var id: UUID = UUID()
    var medicationID: UUID = UUID()
    var reminderEnabled: Bool = true
    var snoozeMinutes: Int = 10
    var createdAt: Date = Date()
    init(medicationID: UUID) {
        self.id = UUID()
        self.medicationID = medicationID
        self.createdAt = Date()
    }
}
