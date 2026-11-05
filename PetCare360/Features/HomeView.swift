import SwiftUI
import SwiftData

struct HomeView: View {
    @EnvironmentObject private var store: StoreManager
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    @Query private var profiles: [UserProfile]
    @Query private var tasks: [CareTask]
    @Query private var handoffs: [CareHandoff]
    @State private var emergencyPet: Pet? = nil

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    private var todaysSlots: [(Medication, DoseSlot, Pet)] {
        pets.flatMap { pet in
            MedicationService.slotsToday(for: pet.medications).map { ($0.0, $0.1, pet) }
        }
    }

    private var todaysTasks: [CareTask] {
        tasks.filter { Calendar.current.isDateInToday($0.scheduledDate) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var completedCount: Int {
        let given = todaysSlots.filter { slot in
            MedicationService.isAlreadyGiven(slot: slot.1, administrations: slot.2.administrations)
        }.count
        return given + todaysTasks.filter { $0.isCompleted }.count
    }

    private var totalToday: Int { todaysSlots.count + todaysTasks.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if pets.isEmpty {
                        PCEmptyState(icon: "pawprint", title: "Add your first pet",
                                     message: "Create a profile to start tracking care, medication and health records.")
                    } else {
                        careProgress
                        upcomingMedications
                        nextAppointment
                        upcomingVaccinations
                        recentObservations
                        recentHandoffs
                    }
                }
                .padding()
            }
            .background(PCColor.warmIvory)
            .navigationTitle("Home")
            .sheet(item: $emergencyPet) { pet in EmergencyView(pet: pet) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greeting)\(profiles.first.map { $0.displayName.isEmpty ? "" : ", \($0.displayName)" } ?? "")")
                .font(.title2.bold()).foregroundStyle(PCColor.charcoal)
            Text(AppConfig.tagline).font(.subheadline).foregroundStyle(PCColor.secondaryText)
            if !pets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(pets) { pet in
                            VStack(spacing: 4) {
                                PetAvatar(pet: pet, size: 52)
                                Text(pet.name).font(.caption).foregroundStyle(PCColor.charcoal)
                            }
                            .accessibilityLabel("Emergency profile for \(pet.name)")
                            .onTapGesture { emergencyPet = pet }
                        }
                    }
                }
                Text("Tap a pet for its emergency profile.").font(.caption2).foregroundStyle(PCColor.secondaryText)
            }
        }
    }

    private var careProgress: some View {
        VStack(alignment: .leading, spacing: 10) {
            PCSectionHeader(title: "Today's Care")
            if totalToday == 0 {
                Text("Nothing scheduled for today.").font(.subheadline).foregroundStyle(PCColor.secondaryText)
            } else {
                ProgressView(value: Double(completedCount), total: Double(totalToday))
                    .tint(PCColor.freshGreen)
                Text("\(completedCount) of \(totalToday) completed")
                    .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                ForEach(todaysTasks) { task in
                    HStack {
                        Button {
                            task.isCompleted.toggle()
                            if task.isCompleted {
                                task.completedAt = Date()
                                task.completedBy = profiles.first?.displayName ?? "Me"
                            }
                        } label: {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(task.isCompleted ? PCColor.freshGreen : PCColor.secondaryText)
                        }
                        .accessibilityLabel(task.isCompleted ? "Mark \(task.title) not done" : "Complete \(task.title)")
                        VStack(alignment: .leading) {
                            Text(task.title).font(.body).foregroundStyle(PCColor.charcoal)
                            Text("\(task.petName) • \(task.kind.label)").font(.caption).foregroundStyle(PCColor.secondaryText)
                        }
                    }
                }
            }
        }
        .pcCard()
    }

    private var upcomingMedications: some View {
        VStack(alignment: .leading, spacing: 10) {
            PCSectionHeader(title: "Upcoming Medication")
            if todaysSlots.isEmpty {
                Text("No medication scheduled today.").font(.subheadline).foregroundStyle(PCColor.secondaryText)
            } else {
                ForEach(todaysSlots, id: \.1) { med, slot, pet in
                    let given = MedicationService.isAlreadyGiven(slot: slot, administrations: pet.administrations)
                    let overdue = MedicationService.isOverdue(slot: slot, administrations: pet.administrations)
                    HStack {
                        Image(systemName: given ? "checkmark.circle.fill" : (overdue ? "exclamationmark.circle.fill" : "pills"))
                            .foregroundStyle(given ? PCColor.freshGreen : (overdue ? PCColor.errorRed : PCColor.softPeach))
                        VStack(alignment: .leading) {
                            Text("\(med.name) \(med.dosage)").font(.body).foregroundStyle(PCColor.charcoal)
                            Text("\(pet.name) • \(slot.scheduledDate.formatted(date: .omitted, time: .shortened))\(overdue ? " • Overdue" : "")\(given ? " • Given" : "")")
                                .font(.caption).foregroundStyle(overdue ? PCColor.errorRed : PCColor.secondaryText)
                        }
                    }
                }
            }
        }
        .pcCard()
    }

    private var nextAppointment: some View {
        let upcoming = pets.flatMap { $0.appointments }
            .filter { $0.date >= Date() && !$0.isCompleted }
            .sorted { $0.date < $1.date }
        return VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "Next Veterinary Appointment")
            if let first = upcoming.first {
                Text(first.title).font(.body).foregroundStyle(PCColor.charcoal)
                Text("\(first.date.formatted(date: .abbreviated, time: .shortened)) • \(first.clinic)")
                    .font(.subheadline).foregroundStyle(PCColor.secondaryText)
            } else {
                Text("No upcoming appointments.").font(.subheadline).foregroundStyle(PCColor.secondaryText)
            }
        }
        .pcCard()
    }

    private var upcomingVaccinations: some View {
        let due = pets.flatMap { pet in pet.vaccinations.map { (pet, $0) } }
            .filter { $0.1.expiresWithin30Days || $0.1.isExpired }
        return Group {
            if !due.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    PCSectionHeader(title: "Upcoming Vaccinations")
                    ForEach(due, id: \.1.id) { pet, vax in
                        Text("\(pet.name): \(vax.vaccineName)\(vax.isExpired ? " — expired" : " — due soon")")
                            .font(.subheadline).foregroundStyle(vax.isExpired ? PCColor.errorRed : PCColor.charcoal)
                    }
                }
                .pcCard()
            }
        }
    }

    private var recentObservations: some View {
        let recent = pets.flatMap { $0.observations }.sorted { $0.date > $1.date }.prefix(3)
        return Group {
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    PCSectionHeader(title: "Recent Health Observations")
                    ForEach(Array(recent)) { obs in
                        Text("\(obs.date.formatted(date: .abbreviated, time: .omitted)) — \(obs.kind.label): \(obs.valueText)")
                            .font(.subheadline).foregroundStyle(PCColor.charcoal)
                    }
                    Text("Tracking and record-keeping only — not a veterinary diagnosis.")
                        .font(.caption2).foregroundStyle(PCColor.secondaryText)
                }
                .pcCard()
            }
        }
    }

    private var recentHandoffs: some View {
        Group {
            if let latest = handoffs.sorted(by: { $0.date > $1.date }).first {
                VStack(alignment: .leading, spacing: 8) {
                    PCSectionHeader(title: "Latest Care Handoff")
                    Text("\(latest.petName) — by \(latest.authorName), \(latest.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline).foregroundStyle(PCColor.charcoal)
                    Text([latest.wasFed ? "Fed" : nil, latest.medicationGiven ? "Medication given" : nil,
                          latest.walkCompleted ? "Walked" : nil].compactMap { $0 }.joined(separator: " • "))
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                    if !latest.notes.isEmpty { Text(latest.notes).font(.subheadline) }
                }
                .pcCard()
            }
        }
    }
}
