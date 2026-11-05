import SwiftUI
import SwiftData

struct CareView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    @Query private var profiles: [UserProfile]
    @Query private var tasks: [CareTask]
    @State private var showMedicationEditor = false
    @State private var showTaskEditor = false
    @State private var showHandoffEditor = false
    @State private var showFeedingEditor = false
    @State private var notice = ""

    private var myName: String { profiles.first?.displayName ?? "Me" }

    var body: some View {
        NavigationStack {
            List {
                if !notice.isEmpty {
                    Text(notice).font(.subheadline).foregroundStyle(PCColor.errorRed)
                }
                medicationSection
                feedingSection
                taskSection
                Section {
                    Button { showHandoffEditor = true } label: {
                        Label("Leave a Care Handoff", systemImage: "note.text")
                    }
                }
            }
            .navigationTitle("Care")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add medication") { showMedicationEditor = true }
                        Button("Add care task") { showTaskEditor = true }
                        Button("Add feeding schedule") { showFeedingEditor = true }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showMedicationEditor) { MedicationEditorView() }
            .sheet(isPresented: $showTaskEditor) { CareTaskEditorView() }
            .sheet(isPresented: $showHandoffEditor) { HandoffEditorView() }
            .sheet(isPresented: $showFeedingEditor) { FoodScheduleEditorView() }
        }
    }

    private var medicationSection: some View {
        Section("Today's Medication") {
            if pets.isEmpty {
                Text("Add a pet first.").foregroundStyle(PCColor.secondaryText)
            }
            ForEach(pets) { pet in
                let slots = MedicationService.slotsToday(for: pet.medications)
                if slots.isEmpty {
                    Text("\(pet.name): no medication scheduled today.").foregroundStyle(PCColor.secondaryText)
                }
                ForEach(slots, id: \.1) { med, slot in
                    MedicationSlotRow(pet: pet, medication: med, slot: slot, myName: myName) { message in
                        notice = message
                    }
                }
                ForEach(pet.medications.filter { $0.needsRefill }) { med in
                    Label("\(pet.name): \(med.name) refill soon — \(med.remainingSupply) left",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(PCColor.warningAmber)
                }
            }
            NavigationLink("Medication history") { MedicationHistoryView() }
            NavigationLink("Manage medications") { MedicationsListView() }
        }
    }

    private var feedingSection: some View {
        Section("Feeding") {
            ForEach(pets) { pet in
                ForEach(pet.foodSchedules.filter { $0.isActive }) { food in
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(pet.name): \(food.foodBrand)").foregroundStyle(PCColor.charcoal)
                            Text("\(food.portion) • \(food.timeMinutes / 60, specifier: "%02d"):\(food.timeMinutes % 60, specifier: "%02d")")
                                .font(.caption).foregroundStyle(PCColor.secondaryText)
                        }
                        Spacer()
                        Button("Fed") {
                            let log = FeedingLog(petID: pet.id, petName: pet.name, by: myName)
                            log.portionGiven = food.portion
                            context.insert(log)
                            do { try context.save() } catch {
                                context.rollback()
                                notice = "That feeding could not be saved on this device — please try again."
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            if pets.allSatisfy({ $0.foodSchedules.isEmpty }) {
                Text("No feeding schedules yet.").foregroundStyle(PCColor.secondaryText)
            }
            NavigationLink("Manage feeding schedules") { FeedingListView() }
        }
    }

    private var taskSection: some View {
        Section("Care Tasks") {
            let upcoming = tasks.sorted { $0.scheduledDate < $1.scheduledDate }
            if upcoming.isEmpty { Text("No care tasks.").foregroundStyle(PCColor.secondaryText) }
            ForEach(upcoming) { task in
                HStack {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.isCompleted ? PCColor.freshGreen : PCColor.secondaryText)
                    VStack(alignment: .leading) {
                        Text(task.title).foregroundStyle(PCColor.charcoal)
                        Text("\(task.petName) • \(task.scheduledDate.formatted(date: .abbreviated, time: .shortened))\(task.assignedTo.isEmpty ? "" : " • \(task.assignedTo)")\(task.isCompleted ? " • done by \(task.completedBy)" : "")")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    task.isCompleted.toggle()
                    task.completedBy = task.isCompleted ? myName : ""
                    task.completedAt = task.isCompleted ? Date() : nil
                    do { try context.save() } catch {
                        context.rollback()
                        notice = "That task update could not be saved on this device — please try again."
                    }
                }
            }
            NavigationLink("Manage care tasks") { CareTasksListView() }
        }
    }
}

struct MedicationSlotRow: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    let pet: Pet
    let medication: Medication
    let slot: DoseSlot
    let myName: String
    let onNotice: (String) -> Void

    private var existing: MedicationAdministration? {
        MedicationService.administration(for: slot, in: pet.administrations)
    }
    /// Effective status: a later Given supersedes an earlier Skip/Delay in
    /// the display, while every entry stays in the audit trail.
    private var effectiveStatus: AdministrationStatus? {
        MedicationService.effectiveStatus(for: slot, administrations: pet.administrations)
    }
    private var isGiven: Bool {
        MedicationService.isAlreadyGiven(slot: slot, administrations: pet.administrations)
    }
    private var isOverdue: Bool {
        MedicationService.isOverdue(slot: slot, administrations: pet.administrations)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(pet.name): \(medication.name) \(medication.dosage)").foregroundStyle(PCColor.charcoal)
                    Text(slot.scheduledDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(isOverdue ? PCColor.errorRed : PCColor.secondaryText)
                }
                Spacer()
                if isGiven {
                    Label("Given", systemImage: "checkmark.circle.fill").foregroundStyle(PCColor.freshGreen).font(.subheadline)
                } else if let effectiveStatus {
                    Text(effectiveStatus.label).font(.subheadline).foregroundStyle(PCColor.warningAmber)
                } else if isOverdue {
                    Text("Overdue").font(.subheadline.bold()).foregroundStyle(PCColor.errorRed)
                }
            }
            if !isGiven {
                HStack(spacing: 8) {
                    Button("Given") { record(.given) }.buttonStyle(.borderedProminent).tint(PCColor.freshGreen)
                    Button("Skipped") { record(.skipped) }.buttonStyle(.bordered)
                    Button("Delayed") { record(.delayed) }.buttonStyle(.bordered)
                }
                .font(.caption)
            } else if let existing {
                Text("Given by \(existing.administeredBy) at \(existing.administeredAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
        }
    }

    /// Records an administration. A `given` entry for the same slot is
    /// refused — this is the duplicate-administration guard, shared with
    /// every caregiver through the same administration log.
    private func record(_ status: AdministrationStatus) {
        if status == .given && isGiven {
            onNotice("\(medication.name) was already recorded as given for this time. Duplicate prevented.")
            return
        }
        let entry = MedicationAdministration(medicationID: medication.id, medicationName: medication.name,
                                             slot: slot, status: status, by: myName)
        entry.pet = pet
        entry.administeredByMemberID = profiles.first?.memberID
        context.insert(entry)
        if status == .given && medication.remainingSupply > 0 {
            medication.remainingSupply -= 1
            if medication.needsRefill && (profiles.first?.remindersEnabled ?? false) {
                NotificationService.shared.scheduleRefillReminder(medication: medication, petName: pet.name)
            }
        }
        do { try context.save() } catch {
            onNotice("That dose could not be saved on this device — please try again.")
            return
        }
    }
}

struct MedicationHistoryView: View {
    @Query(sort: \MedicationAdministration.administeredAt, order: .reverse) private var entries: [MedicationAdministration]
    var body: some View {
        List {
            if entries.isEmpty { Text("No administrations recorded yet.").foregroundStyle(PCColor.secondaryText) }
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.pet?.name ?? "Pet"): \(entry.medicationName) — \(entry.status.label)")
                        .foregroundStyle(PCColor.charcoal)
                    Text("By \(entry.administeredBy) • \(entry.administeredAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                    if !entry.note.isEmpty { Text(entry.note).font(.caption) }
                }
            }
        }
        .navigationTitle("Medication History")
    }
}


struct MedicationsListView: View {
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    @State private var medicationToEdit: Medication? = nil
    var body: some View {
        List {
            if pets.isEmpty { Text("Add a pet first.").foregroundStyle(PCColor.secondaryText) }
            ForEach(pets) { pet in
                Section(pet.name) {
                    if pet.medications.isEmpty {
                        Text("No medications.").foregroundStyle(PCColor.secondaryText)
                    }
                    ForEach(pet.medications.sorted { $0.name < $1.name }) { med in
                        Button { medicationToEdit = med } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(med.name) \(med.dosage)").foregroundStyle(PCColor.charcoal)
                                Text("\(med.frequency.label)\(med.isActive ? "" : " • Inactive") • \(med.doseMinutes.count) dose time(s) daily")
                                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                            }
                        }
                        .accessibilityLabel("Edit \(med.name)")
                    }
                }
            }
        }
        .navigationTitle("All Medications")
        .sheet(item: $medicationToEdit) { med in MedicationEditorView(existing: med) }
    }
}

struct CareTasksListView: View {
    @Query(sort: \CareTask.scheduledDate) private var tasks: [CareTask]
    @State private var taskToEdit: CareTask? = nil
    var body: some View {
        List {
            if tasks.isEmpty { Text("No care tasks.").foregroundStyle(PCColor.secondaryText) }
            ForEach(tasks) { task in
                Button { taskToEdit = task } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).foregroundStyle(PCColor.charcoal)
                        Text("\(task.petName) • \(task.scheduledDate.formatted(date: .abbreviated, time: .shortened))\(task.isCompleted ? " • Completed" : "")")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                }
                .accessibilityLabel("Edit task \(task.title)")
            }
        }
        .navigationTitle("All Care Tasks")
        .sheet(item: $taskToEdit) { task in CareTaskEditorView(existing: task) }
    }
}

struct FeedingListView: View {
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    @State private var foodToEdit: FoodSchedule? = nil
    var body: some View {
        List {
            ForEach(pets) { pet in
                Section(pet.name) {
                    if pet.foodSchedules.isEmpty {
                        Text("No feeding schedules.").foregroundStyle(PCColor.secondaryText)
                    }
                    ForEach(pet.foodSchedules) { food in
                        Button { foodToEdit = food } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.foodBrand).foregroundStyle(PCColor.charcoal)
                                Text("\(food.portion) • \(food.isActive ? "Active" : "Inactive")")
                                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                            }
                        }
                        .accessibilityLabel("Edit feeding schedule \(food.foodBrand)")
                    }
                }
            }
        }
        .navigationTitle("Feeding Schedules")
        .sheet(item: $foodToEdit) { food in FoodScheduleEditorView(existing: food) }
    }
}

struct MedicationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    @Query private var profiles: [UserProfile]
    @Query private var allSchedules: [MedicationSchedule]
    let existing: Medication?
    init(existing: Medication? = nil) { self.existing = existing }

    @State private var petID: UUID? = nil
    @State private var name = ""
    @State private var dosage = ""
    @State private var instructions = ""
    @State private var frequency: MedicationFrequency = .onceDaily
    @State private var doseTimes: [Date] = [MedicationEditorView.defaultDoseTime]
    @State private var selectedWeekdays: Set<Int> = []
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var supply = ""
    @State private var threshold = "5"
    @State private var vet = ""
    @State private var isActive = true
    @State private var enableReminder = true
    @State private var prescriptionDocumentID: UUID? = nil
    @State private var errorMessage = ""
    @State private var confirmDelete = false
    @State private var loaded = false

    private static var defaultDoseTime: Date {
        Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
    }
    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private var resolvedPet: Pet? {
        if let existing, let pet = existing.pet { return pet }
        return pets.first { $0.id == petID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !errorMessage.isEmpty {
                    Text(errorMessage).font(.subheadline).foregroundStyle(PCColor.errorRed)
                }
                if existing == nil {
                    Picker("Pet", selection: $petID) {
                        Text("Select").tag(UUID?.none)
                        ForEach(pets) { pet in Text(pet.name).tag(Optional(pet.id)) }
                    }
                } else if let pet = resolvedPet {
                    LabeledContent("Pet", value: pet.name)
                }
                Section("Medication") {
                    TextField("Medication name", text: $name)
                    TextField("Dosage (as prescribed)", text: $dosage)
                    TextField("Instructions", text: $instructions, axis: .vertical)
                    TextField("Prescribing veterinarian", text: $vet)
                    Toggle("Active", isOn: $isActive)
                }
                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(MedicationFrequency.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    if frequency == .weekly {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weekdays").font(.subheadline)
                            HStack(spacing: 6) {
                                ForEach(1...7, id: \.self) { day in
                                    let weekdayName = weekdayNames[day - 1]
                                    let isSelected = selectedWeekdays.contains(day)
                                    Button(weekdayName) {
                                        if isSelected { selectedWeekdays.remove(day) }
                                        else { selectedWeekdays.insert(day) }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(isSelected ? PCColor.freshGreen : PCColor.secondaryText)
                                    .accessibilityLabel(isSelected ? "\(weekdayName), selected" : weekdayName)
                                }
                            }
                            if selectedWeekdays.isEmpty {
                                Text("Select at least one weekday.").font(.caption).foregroundStyle(PCColor.errorRed)
                            }
                        }
                    }
                    ForEach(Array(doseTimes.enumerated()), id: \.offset) { index, _ in
                        HStack {
                            DatePicker("Dose \(index + 1)", selection: $doseTimes[index], displayedComponents: .hourAndMinute)
                            if doseTimes.count > 1 {
                                Button(role: .destructive) { doseTimes.remove(at: index) } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .accessibilityLabel("Remove dose time \(index + 1)")
                            }
                        }
                    }
                    Button("Add dose time") {
                        let base = doseTimes.last ?? MedicationEditorView.defaultDoseTime
                        doseTimes.append(Calendar.current.date(byAdding: .hour, value: 2, to: base) ?? base)
                    }
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    Toggle("Course has an end date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End date", selection: $endDate, displayedComponents: .date)
                    }
                }
                Section("Supply") {
                    TextField("Remaining supply (doses)", text: $supply).keyboardType(.numberPad)
                    TextField("Refill reminder at (doses)", text: $threshold).keyboardType(.numberPad)
                }
                if let pet = resolvedPet, !pet.documents.isEmpty {
                    Section("Prescription") {
                        Picker("Prescription document", selection: $prescriptionDocumentID) {
                            Text("None").tag(UUID?.none)
                            ForEach(pet.documents) { doc in Text(doc.title).tag(Optional(doc.id)) }
                        }
                    }
                }
                Section {
                    Toggle("Medication reminder", isOn: $enableReminder)
                    Text("Editing a medication never changes its recorded administration history. Never change a prescribed dosage or instruction in the app — always follow your veterinarian's prescription.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                }
                if existing != nil {
                    Section {
                        Button("Delete Medication", role: .destructive) { confirmDelete = true }
                        Text("Deleting a medication keeps its recorded administration history on the pet.")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Medication" : "Edit Medication")
            .alert("Couldn't save", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) { Button("OK", role: .cancel) {} } message: { Text(errorMessage) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .alert("Delete this medication?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteMedication() }
            } message: {
                Text("The medication schedule will be removed. Recorded administrations stay in the pet's history.")
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let med = existing else { return }
        petID = med.pet?.id
        name = med.name; dosage = med.dosage; instructions = med.instructions
        frequency = med.frequency
        doseTimes = med.doseMinutes.map { minutes in
            Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? MedicationEditorView.defaultDoseTime
        }
        if doseTimes.isEmpty { doseTimes = [MedicationEditorView.defaultDoseTime] }
        selectedWeekdays = Set(med.weekdays)
        startDate = med.startDate
        if let end = med.endDate { hasEndDate = true; endDate = end }
        supply = String(med.remainingSupply)
        threshold = String(med.refillThreshold)
        vet = med.prescribingVet
        isActive = med.isActive
        prescriptionDocumentID = med.prescriptionDocumentID
        // Load THIS medication's own reminder preference (v1.2.3) — it is
        // separate from the global Reminders setting in Settings.
        enableReminder = NotificationService.isReminderEnabled(medicationID: med.id, schedules: allSchedules)
    }

    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 8) * 60 + (c.minute ?? 0)
    }

    private func save() {
        guard let pet = resolvedPet else { errorMessage = "Choose a pet first."; return }
        let normalized = MedicationService.normalizeDoseMinutes(doseTimes.map { minutes($0) })
        guard !normalized.isEmpty else { errorMessage = "Add at least one dose time."; return }
        if normalized.count != doseTimes.count {
            errorMessage = "Duplicate dose times were merged into one."
            doseTimes = normalized.map {
                Calendar.current.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: Date()) ?? MedicationEditorView.defaultDoseTime
            }
            return
        }
        if frequency == .weekly && selectedWeekdays.isEmpty {
            errorMessage = "Select at least one weekday for a weekly medication."
            return
        }
        if hasEndDate && Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: startDate) {
            errorMessage = "The end date cannot be earlier than the start date."
            return
        }
        let med = existing ?? Medication(name: name, dosage: dosage)
        if existing == nil { context.insert(med); med.pet = pet }
        med.name = name; med.dosage = dosage; med.instructions = instructions
        med.frequencyRaw = frequency.rawValue
        med.doseMinutes = normalized
        med.weekdays = frequency == .weekly ? selectedWeekdays.sorted() : []
        med.startDate = startDate
        med.endDate = hasEndDate ? endDate : nil
        med.remainingSupply = Int(supply) ?? 0
        med.refillThreshold = Int(threshold) ?? 5
        med.prescribingVet = vet
        med.isActive = isActive
        med.prescriptionDocumentID = prescriptionDocumentID
        // Create-or-update the schedule record with the preference (v1.2.3).
        if let schedule = allSchedules.first(where: { $0.medicationID == med.id }) {
            schedule.reminderEnabled = enableReminder
        } else {
            let schedule = MedicationSchedule(medicationID: med.id)
            schedule.reminderEnabled = enableReminder
            context.insert(schedule)
        }
        do { try context.save() } catch {
            errorMessage = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        // Cancel FIRST and schedule only from the cancellation's
        // completion, so a late removal snapshot can never delete the
        // reminders this save just created (v1.2.4 race fix).
        let shouldSchedule = enableReminder && isActive && (profiles.first?.remindersEnabled ?? false)
        NotificationService.shared.cancelDoseReminders(medicationID: med.id) {
            if shouldSchedule {
                NotificationService.shared.scheduleMedicationReminder(medication: med, petName: pet.name)
            }
        }
        dismiss()
    }

    private func deleteMedication() {
        guard let med = existing else { return }
        let medicationID = med.id
        context.delete(med)
        do {
            try context.save()
            NotificationService.shared.cancelMedicationReminders(medicationID: medicationID)
            dismiss()
        } catch {
            context.rollback()
            errorMessage = "This medication could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
        }
    }
}

struct CareTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    let existing: CareTask?
    init(existing: CareTask? = nil) { self.existing = existing }
    @State private var petID: UUID? = nil
    @State private var title = ""
    @State private var kind: CareTaskKind = .other
    @State private var date = Date()
    @State private var assignedTo = ""
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Picker("Pet", selection: $petID) {
                        Text("Select").tag(UUID?.none)
                        ForEach(pets) { pet in Text(pet.name).tag(Optional(pet.id)) }
                    }
                } else if let existing {
                    LabeledContent("Pet", value: existing.petName)
                }
                TextField("Task", text: $title)
                Picker("Type", selection: $kind) {
                    ForEach(CareTaskKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                DatePicker("When", selection: $date)
                TextField("Assigned to (optional)", text: $assignedTo)
                if existing != nil {
                    Section {
                        Button("Delete Task", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Care Task" : "Edit Care Task")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.isEmpty || (existing == nil && petID == nil))
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    title = existing.title; kind = existing.kind
                    date = existing.scheduledDate; assignedTo = existing.assignedTo
                }
            }
            .alert("Delete this task?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let existing {
                        context.delete(existing)
                        do { try context.save(); dismiss() } catch {
                            context.rollback()
                            saveError = "This task could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                        }
                    }
                }
            }
        }
    }
    private func save() {
        if let existing {
            existing.title = title; existing.kindRaw = kind.rawValue
            existing.scheduledDate = date; existing.assignedTo = assignedTo
        } else {
            guard let petID, let pet = pets.first(where: { $0.id == petID }) else { return }
            let task = CareTask(title: title, petID: pet.id, petName: pet.name, kind: kind, date: date)
            task.assignedTo = assignedTo
            context.insert(task)
        }
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        dismiss()
    }
}

struct FoodScheduleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    @Query private var profiles: [UserProfile]
    let existing: FoodSchedule?
    init(existing: FoodSchedule? = nil) { self.existing = existing }
    @State private var petID: UUID? = nil
    @State private var brand = ""
    @State private var type = ""
    @State private var portion = ""
    @State private var time = Date()
    @State private var instructions = ""
    @State private var transition = ""
    @State private var isActive = true
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                if existing == nil {
                    Picker("Pet", selection: $petID) {
                        Text("Select").tag(UUID?.none)
                        ForEach(pets) { pet in Text(pet.name).tag(Optional(pet.id)) }
                    }
                } else if let petName = existing?.pet?.name {
                    LabeledContent("Pet", value: petName)
                }
                TextField("Food brand", text: $brand)
                TextField("Food type", text: $type)
                TextField("Portion size", text: $portion)
                DatePicker("Feeding time", selection: $time, displayedComponents: .hourAndMinute)
                Toggle("Active", isOn: $isActive)
                TextField("Special instructions", text: $instructions, axis: .vertical)
                TextField("Food transition notes", text: $transition, axis: .vertical)
                Text("PetCare 360 records the feeding plan you and your veterinarian choose; it does not prescribe diets.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                if existing != nil {
                    Section {
                        Button("Delete Schedule", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Feeding Schedule" : "Edit Feeding Schedule")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(brand.isEmpty || (existing == nil && petID == nil))
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    brand = existing.foodBrand; type = existing.foodType; portion = existing.portion
                    instructions = existing.instructions; transition = existing.transitionNote
                    isActive = existing.isActive
                    time = Calendar.current.date(bySettingHour: existing.timeMinutes / 60, minute: existing.timeMinutes % 60, second: 0, of: Date()) ?? Date()
                }
            }
            .alert("Delete this feeding schedule?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let existing {
                        let foodID = existing.id
                        context.delete(existing)
                        do {
                            try context.save()
                            NotificationService.shared.cancel(ids: ["feed-\(foodID.uuidString)"])
                            dismiss()
                        } catch {
                            context.rollback()
                            saveError = "This feeding schedule could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                        }
                    }
                }
            }
        }
    }
    private func save() {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minutes = (c.hour ?? 8) * 60 + (c.minute ?? 0)
        if let existing {
            existing.foodBrand = brand; existing.foodType = type; existing.portion = portion
            existing.timeMinutes = minutes; existing.instructions = instructions
            existing.transitionNote = transition; existing.isActive = isActive
            do { try context.save() } catch {
                saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
                return
            }
            if isActive, profiles.first?.remindersEnabled ?? false, let petName = existing.pet?.name {
                NotificationService.shared.scheduleFeedingReminder(schedule: existing, petName: petName)
            } else {
                // Deactivated: its daily notification must not survive.
                NotificationService.shared.cancel(ids: ["feed-\(existing.id.uuidString)"])
            }
            dismiss()
            return
        }
        guard let petID, let pet = pets.first(where: { $0.id == petID }) else { return }
        let food = FoodSchedule(brand: brand)
        food.foodType = type; food.portion = portion
        food.timeMinutes = minutes
        food.instructions = instructions; food.transitionNote = transition
        food.isActive = isActive
        food.pet = pet
        context.insert(food)
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        if isActive && (profiles.first?.remindersEnabled ?? false) {
            NotificationService.shared.scheduleFeedingReminder(schedule: food, petName: pet.name)
        }
        dismiss()
    }
}

struct HandoffEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    @Query private var profiles: [UserProfile]
    @State private var petName = ""
    @State private var fed = false
    @State private var medication = false
    @State private var walk = false
    @State private var appetiteNormal = true
    @State private var unusual = ""
    @State private var notes = ""
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("Pet", selection: $petName) {
                    Text("Select").tag("")
                    ForEach(pets) { pet in Text(pet.name).tag(pet.name) }
                }
                Toggle("Pet was fed", isOn: $fed)
                Toggle("Medication was given", isOn: $medication)
                Toggle("Walk completed", isOn: $walk)
                Toggle("Appetite was normal", isOn: $appetiteNormal)
                TextField("Unusual behavior observed", text: $unusual, axis: .vertical)
                TextField("Additional notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("Care Handoff")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let handoff = CareHandoff(petName: petName, author: profiles.first?.displayName ?? "Caregiver")
                        handoff.petID = pets.first { $0.name == petName }?.id
                        handoff.authorMemberID = profiles.first?.memberID
                        handoff.wasFed = fed; handoff.medicationGiven = medication
                        handoff.walkCompleted = walk; handoff.appetiteNormal = appetiteNormal
                        handoff.unusualBehavior = unusual; handoff.notes = notes
                        context.insert(handoff)
                        do { try context.save() } catch {
                            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
                            return
                        }
                        dismiss()
                    }.disabled(petName.isEmpty)
                }
            }
        }
    }
}
