import Foundation

/// When a scheduled item falls, relative to today. Pure calendar
/// maths so it is unit-testable and identical everywhere it is used.
enum ScheduleStatus: String, CaseIterable {
    case overdue, dueToday, tomorrow, thisWeek, later

    static func bucket(for date: Date, now: Date, calendar: Calendar = .current) -> ScheduleStatus {
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case ..<0: return .overdue
        case 0: return .dueToday
        case 1: return .tomorrow
        case 2...7: return .thisWeek
        default: return .later
        }
    }

    var label: String {
        switch self {
        case .overdue: return "Overdue"
        case .dueToday: return "Due today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        case .later: return "Later"
        }
    }
}

/// One row of the Home schedule. Built ONLY from real model data —
/// never sample or hardcoded content — with a stable unique id per
/// source record + day, so the same activity can never appear twice.
struct ScheduleItem: Identifiable, Equatable {
    enum Kind: String {
        case appointment, vaccination, medication, feeding, careTask, insurance, birthday
        var label: String {
            switch self {
            case .appointment: return "Appointment"
            case .vaccination: return "Vaccination"
            case .medication: return "Medication"
            case .feeding: return "Feeding"
            case .careTask: return "Care task"
            case .insurance: return "Insurance renewal"
            case .birthday: return "Birthday"
            }
        }
        var icon: String {
            switch self {
            case .appointment: return "calendar.badge.clock"
            case .vaccination: return "syringe"
            case .medication: return "pills"
            case .feeding: return "fork.knife"
            case .careTask: return "checklist"
            case .insurance: return "shield"
            case .birthday: return "gift"
            }
        }
    }

    let id: String
    let petID: UUID
    let petName: String
    let species: PetSpecies
    let kind: Kind
    let title: String
    let detail: String
    let date: Date
    let status: ScheduleStatus
}

/// The centralized Home schedule (brief 2026-11-06): everything
/// scheduled for the user's pets, from the existing database only.
///
/// - Appointments: from the START of today (an appointment earlier
///   today still shows — the previous exact-instant `date >= now`
///   comparison made same-day appointments vanish), excluding
///   completed and cancelled, out to the horizon.
/// - Vaccinations: by expiration (due) date, overdue included.
/// - Medications: dose slots for tomorrow — plus today's when
///   `includeTodayActionable` is set (the full schedule screen);
///   on the Home card today's doses live in Today's Care instead,
///   so nothing is ever listed twice on one screen.
/// - Feeding: today's and tomorrow's times from active schedules.
/// - Care tasks: incomplete, overdue included.
/// - Insurance renewals and pet birthdays inside the horizon.
enum HomeSchedule {
    static func build(pets: [Pet], tasks: [CareTask], policies: [InsurancePolicy],
                      now: Date = Date(), horizonDays: Int = 30,
                      includeTodayActionable: Bool,
                      calendar: Calendar = .current) -> [ScheduleItem] {
        let today = calendar.startOfDay(for: now)
        guard let horizon = calendar.date(byAdding: .day, value: horizonDays, to: today) else { return [] }
        let activePets = pets.filter { !$0.isArchived }
        let activeIDs = Set(activePets.map { $0.id })
        var items: [ScheduleItem] = []

        func add(_ kind: ScheduleItem.Kind, sourceID: UUID, pet: Pet, title: String, detail: String, date: Date) {
            items.append(ScheduleItem(
                id: "\(kind.rawValue)-\(sourceID.uuidString)-\(Int(date.timeIntervalSince1970))",
                petID: pet.id, petName: pet.name, species: pet.species, kind: kind,
                title: title, detail: detail, date: date,
                status: ScheduleStatus.bucket(for: date, now: now, calendar: calendar)))
        }

        for pet in activePets {
            for appt in pet.appointments where !appt.isCompleted && !appt.isCancelled {
                guard appt.date >= today, appt.date < horizon else { continue }
                let place = [appt.clinic, appt.vetName].filter { !$0.isEmpty }.joined(separator: " • ")
                add(.appointment, sourceID: appt.id, pet: pet, title: appt.title,
                    detail: place, date: appt.date)
            }
            for vax in pet.vaccinations {
                guard let exp = vax.expirationDate, exp < horizon else { continue }
                add(.vaccination, sourceID: vax.id, pet: pet,
                    title: "\(vax.vaccineName) vaccination due",
                    detail: vax.clinic, date: exp)
            }
            // Medication doses: tomorrow always; today only for the
            // full schedule (Home shows today's in Today's Care).
            var doseDays: [Date] = []
            if includeTodayActionable { doseDays.append(today) }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) { doseDays.append(tomorrow) }
            for day in doseDays {
                for med in pet.medications where med.isActive {
                    for slot in MedicationService.slots(for: med, on: day, calendar: calendar) {
                        if calendar.isDateInToday(day), MedicationService.isAlreadyGiven(slot: slot, administrations: pet.administrations) { continue }
                        add(.medication, sourceID: med.id, pet: pet,
                            title: "\(med.name) \(med.dosage)",
                            detail: MedicationService.isOverdue(slot: slot, administrations: pet.administrations) ? "Dose overdue" : "Dose",
                            date: slot.scheduledDate)
                    }
                }
            }
            for schedule in pet.foodSchedules where schedule.isActive {
                for day in [today, calendar.date(byAdding: .day, value: 1, to: today)].compactMap({ $0 }) {
                    let date = day.addingTimeInterval(TimeInterval(schedule.timeMinutes * 60))
                    add(.feeding, sourceID: schedule.id, pet: pet,
                        title: "Feeding: \(schedule.foodBrand.isEmpty ? schedule.foodType : schedule.foodBrand)",
                        detail: schedule.portion, date: date)
                }
            }
            if let dob = pet.dateOfBirth {
                let thisYear = calendar.dateComponents([.year], from: now).year ?? 0
                var comps = calendar.dateComponents([.month, .day], from: dob)
                comps.year = thisYear
                var next = calendar.date(from: comps) ?? dob
                if next < today {
                    comps.year = thisYear + 1
                    next = calendar.date(from: comps) ?? next
                }
                if next < horizon {
                    let age = (comps.year ?? thisYear) - (calendar.dateComponents([.year], from: dob).year ?? thisYear)
                    add(.birthday, sourceID: pet.id, pet: pet,
                        title: "\(pet.name)'s birthday",
                        detail: age > 0 ? "Turns \(age)" : "", date: next)
                }
            }
        }

        for task in tasks where !task.isCompleted {
            guard activeIDs.contains(task.petID), task.scheduledDate < horizon else { continue }
            if !includeTodayActionable, calendar.isDateInToday(task.scheduledDate) { continue }
            guard let pet = activePets.first(where: { $0.id == task.petID }) else { continue }
            add(.careTask, sourceID: task.id, pet: pet, title: task.title,
                detail: task.kind.label, date: task.scheduledDate)
        }

        for policy in policies {
            guard activeIDs.contains(policy.petID), let renewal = policy.renewalDate, renewal < horizon,
                  let pet = activePets.first(where: { $0.id == policy.petID }) else { continue }
            add(.insurance, sourceID: policy.id, pet: pet,
                title: "Insurance renewal: \(policy.provider)", detail: "", date: renewal)
        }

        // Chronological; overdue (past dates) naturally first. The
        // id uniquing is defensive — ids are already unique by
        // construction (kind + record + instant).
        var seen = Set<String>()
        return items.sorted { $0.date < $1.date }.filter { seen.insert($0.id).inserted }
    }
}
