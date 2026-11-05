import Foundation

/// Pure scheduling and duplicate-prevention logic for medications.
/// Kept free of SwiftData so it can be unit-tested directly.
enum MedicationService {

    /// All dose slots for a medication on a given day (empty when the
    /// medication is not scheduled that day).
    static func slots(for medication: Medication, on day: Date, calendar: Calendar = .current) -> [DoseSlot] {
        let startOfDay = calendar.startOfDay(for: day)
        let firstDay = calendar.startOfDay(for: medication.startDate)
        guard startOfDay >= firstDay else { return [] }
        if let end = medication.endDate, startOfDay > calendar.startOfDay(for: end) { return [] }
        let weekday = calendar.component(.weekday, from: startOfDay)
        switch medication.frequency {
        case .weekly:
            guard medication.weekdays.isEmpty || medication.weekdays.contains(weekday) else { return [] }
        default:
            break
        }
        return medication.doseMinutes.sorted().map {
            DoseSlot(medicationID: medication.id, day: startOfDay, minutes: $0)
        }
    }

    static func slotsToday(for medications: [Medication], now: Date = Date()) -> [(Medication, DoseSlot)] {
        medications.filter { $0.isActive }
            .flatMap { med in slots(for: med, on: now).map { (med, $0) } }
            .sorted { $0.1.scheduledDate < $1.1.scheduledDate }
    }

    /// Duplicate prevention: a slot counts as already administered when an
    /// administration with status `given` exists for the same medication,
    /// same day and same scheduled minutes. Skipped/delayed entries do NOT
    /// block a later `given` entry.
    static func isAlreadyGiven(slot: DoseSlot, administrations: [MedicationAdministration]) -> Bool {
        administrations.contains {
            $0.medicationID == slot.medicationID
                && Calendar.current.isDate($0.scheduledDay, inSameDayAs: slot.day)
                && $0.scheduledMinutes == slot.minutes
                && $0.status == .given
        }
    }

    static func administration(for slot: DoseSlot, in administrations: [MedicationAdministration]) -> MedicationAdministration? {
        administrations.first {
            $0.medicationID == slot.medicationID
                && Calendar.current.isDate($0.scheduledDay, inSameDayAs: slot.day)
                && $0.scheduledMinutes == slot.minutes
        }
    }

    static func isOverdue(slot: DoseSlot, administrations: [MedicationAdministration], now: Date = Date()) -> Bool {
        slot.scheduledDate < now && administration(for: slot, in: administrations) == nil
    }

    /// Normalizes editor input for dose times: valid minutes only,
    /// duplicates removed, sorted chronologically.
    static func normalizeDoseMinutes(_ minutes: [Int]) -> [Int] {
        Array(Set(minutes.filter { (0..<1440).contains($0) })).sorted()
    }

    /// The current effective status of a slot: `given` wins permanently
    /// (a dose can only be given once); otherwise the most recent entry.
    /// Earlier skipped/delayed entries remain in the audit trail.
    static func effectiveStatus(for slot: DoseSlot, administrations: [MedicationAdministration]) -> AdministrationStatus? {
        let entries = administrations.filter {
            $0.medicationID == slot.medicationID
                && Calendar.current.isDate($0.scheduledDay, inSameDayAs: slot.day)
                && $0.scheduledMinutes == slot.minutes
        }
        if entries.contains(where: { $0.status == .given }) { return .given }
        return entries.sorted { $0.administeredAt < $1.administeredAt }.last?.status
    }
}
