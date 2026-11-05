import SwiftUI
import SwiftData
import Charts
import UIKit

struct RecordsView: View {
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    @State private var selectedPetID: UUID? = nil

    private var selectedPet: Pet? {
        pets.first { $0.id == selectedPetID } ?? pets.first
    }

    var body: some View {
        NavigationStack {
            List {
                if pets.isEmpty {
                    PCEmptyState(icon: "folder", title: "No pets yet", message: "Records appear here once you add a pet.")
                } else {
                    Picker("Pet", selection: $selectedPetID) {
                        ForEach(pets) { pet in Text(pet.name).tag(Optional(pet.id)) }
                    }
                    if let pet = selectedPet {
                        Section("Medical Passport") {
                            NavigationLink("Records & timeline") { MedicalTimelineView(pet: pet) }
                            NavigationLink("Vaccinations") { VaccinationsView(pet: pet) }
                            NavigationLink("Documents & scanner") { DocumentsView(pet: pet) }
                            NavigationLink("Appointments & visit prep") { AppointmentsView(pet: pet) }
                        }
                        Section("Health") {
                            NavigationLink("Health timeline & charts") { HealthChartsView(pet: pet) }
                        }
                        Section("Money") {
                            NavigationLink("Expenses") { ExpensesView(pet: pet) }
                            NavigationLink("Insurance") { InsuranceView(pet: pet) }
                        }
                        Section("Safety") {
                            NavigationLink("Recall tracking (FDA)") { RecallsView() }
                            NavigationLink("Lost pet profile") { LostPetView(pet: pet) }
                        }
                    }
                }
            }
            .navigationTitle("Records")
        }
    }
}

struct MedicalTimelineView: View {
    @Environment(\.modelContext) private var context
    @Bindable var pet: Pet
    @State private var showEditor = false
    @State private var recordToEdit: MedicalRecord? = nil
    @State private var showPassportExport = false
    private var timeline: [MedicalRecord] { pet.medicalRecords.sorted { $0.date > $1.date } }
    var body: some View {
        List {
            if timeline.isEmpty { Text("No medical records yet.").foregroundStyle(PCColor.secondaryText) }
            ForEach(timeline) { record in
                Button { recordToEdit = record } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.title).font(.headline).foregroundStyle(PCColor.charcoal)
                        Text("\(record.category.label) • \(record.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                        if !record.details.isEmpty { Text(record.details).font(.subheadline) }
                        if let follow = record.followUpDate {
                            Text("Follow-up: \(follow.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                        }
                        if !record.editHistory.isEmpty {
                            Text("Edited — history kept").font(.caption2).foregroundStyle(PCColor.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit record \(record.title)")
            }
            Section {
                Button("Export Medical Passport…") { showPassportExport = true }
            }
        }
        .navigationTitle("Medical Timeline")
        .toolbar { Button { showEditor = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showEditor) { MedicalRecordEditorView(pet: pet) }
        .sheet(item: $recordToEdit) { record in MedicalRecordEditorView(pet: pet, existing: record) }
        .sheet(isPresented: $showPassportExport) { PassportExportView(pet: pet) }
    }
}

/// Medical Passport export with owner-selected categories and a PDF
/// preview before sharing (Phase 2, section H). Only the selected
/// categories are included; the pet's identity and generation date are
/// printed on the document itself.
struct PassportExportView: View {
    @Environment(\.dismiss) private var dismiss
    let pet: Pet
    @State private var selected: Set<MedicalCategory> = Set(MedicalCategory.allCases)
    @State private var pdfData: Data? = nil
    @State private var showPreview = false
    @State private var showShare = false

    private var selectedRecordCount: Int {
        pet.medicalRecords.filter { selected.contains($0.category) }.count
            + (selected.contains(.vaccination) ? pet.vaccinations.count : 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pet") {
                    LabeledContent("Passport for", value: pet.name)
                    Text("The PDF shows the pet's identity and the generation date on every page.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                }
                Section("Include categories") {
                    ForEach(MedicalCategory.allCases, id: \.self) { category in
                        Toggle(category.label, isOn: Binding(
                            get: { selected.contains(category) },
                            set: { if $0 { selected.insert(category) } else { selected.remove(category) } }
                        ))
                    }
                }
                Section {
                    if selectedRecordCount == 0 {
                        Text("No records in the selected categories yet — the passport will contain the pet profile, medications and veterinary contact only.")
                            .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                    }
                    Button("Preview PDF") {
                        pdfData = PDFService.medicalPassport(pet: pet, include: selected)
                        showPreview = true
                    }
                    Button("Share PDF") {
                        pdfData = PDFService.medicalPassport(pet: pet, include: selected)
                        showShare = true
                    }
                }
            }
            .navigationTitle("Medical Passport")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(isPresented: $showPreview) {
                if let pdfData { PDFKitView(data: pdfData) }
            }
            .sheet(isPresented: $showShare) {
                if let pdfData { ShareSheet(items: [pdfData]) }
            }
        }
    }
}

struct MedicalRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let pet: Pet
    let existing: MedicalRecord?
    init(pet: Pet, existing: MedicalRecord? = nil) { self.pet = pet; self.existing = existing }
    @State private var title = ""
    @State private var category: MedicalCategory = .note
    @State private var details = ""
    @State private var date = Date()
    @State private var clinic = ""
    @State private var hasFollowUp = false
    @State private var followUp = Date()
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                Picker("Category", selection: $category) {
                    ForEach(MedicalCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Details", text: $details, axis: .vertical)
                TextField("Veterinary clinic", text: $clinic)
                Toggle("Follow-up date", isOn: $hasFollowUp)
                if hasFollowUp { DatePicker("Follow-up", selection: $followUp, displayedComponents: .date) }
                if let existing, !existing.editHistory.isEmpty {
                    Section("Edit history") {
                        Text(existing.editHistory).font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                }
                if existing != nil {
                    Section {
                        Button("Delete Record", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Record" : "Edit Record")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    title = existing.title; category = existing.category; details = existing.details
                    date = existing.date; clinic = existing.vetClinic
                    if let follow = existing.followUpDate { hasFollowUp = true; followUp = follow }
                }
            }
            .alert("Delete this record?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let existing {
                        context.delete(existing)
                        do { try context.save(); dismiss() } catch {
                            context.rollback()
                            saveError = "This record could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                        }
                    }
                }
            } message: { Text("This medical record will be permanently deleted.") }
        }
    }
    private func save() {
        if let existing {
            // Corrections are auditable: append to editHistory instead of
            // silently overwriting (master prompt, section 8).
            existing.recordEdit(note: "Edited: title, category, details or dates updated in the app.")
            existing.title = title; existing.categoryRaw = category.rawValue
            existing.details = details; existing.date = date; existing.vetClinic = clinic
            existing.followUpDate = hasFollowUp ? followUp : nil
        } else {
            let record = MedicalRecord(title: title, category: category, date: date)
            record.details = details; record.vetClinic = clinic; record.pet = pet
            record.followUpDate = hasFollowUp ? followUp : nil
            context.insert(record)
        }
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        dismiss()
    }
}


struct VaccinationsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var pet: Pet
    @State private var showEditor = false
    @State private var vaxToEdit: VaccinationRecord? = nil
    var body: some View {
        List {
            if pet.vaccinations.isEmpty { Text("No vaccinations recorded.").foregroundStyle(PCColor.secondaryText) }
            ForEach(pet.vaccinations.sorted { $0.dateAdministered > $1.dateAdministered }) { vax in
                Button { vaxToEdit = vax } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vax.vaccineName).font(.headline).foregroundStyle(PCColor.charcoal)
                        Text("Given \(vax.dateAdministered.formatted(date: .abbreviated, time: .omitted))\(vax.expirationDate.map { " • Expires \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")")
                            .font(.caption).foregroundStyle(vax.isExpired ? PCColor.errorRed : PCColor.secondaryText)
                        if !vax.clinic.isEmpty { Text(vax.clinic).font(.caption).foregroundStyle(PCColor.secondaryText) }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit vaccination \(vax.vaccineName)")
            }
        }
        .navigationTitle("Vaccinations")
        .toolbar { Button { showEditor = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showEditor) { VaccinationEditorView(pet: pet) }
        .sheet(item: $vaxToEdit) { vax in VaccinationEditorView(pet: pet, existing: vax) }
    }
}

struct VaccinationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    let pet: Pet
    let existing: VaccinationRecord?
    init(pet: Pet, existing: VaccinationRecord? = nil) { self.pet = pet; self.existing = existing }
    @State private var name = ""
    @State private var date = Date()
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var clinic = ""
    @State private var notes = ""
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Vaccine name", text: $name)
                DatePicker("Date administered", selection: $date, displayedComponents: .date)
                Toggle("Has expiration date", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Expiration", selection: $expiry, displayedComponents: .date) }
                TextField("Clinic", text: $clinic)
                TextField("Notes", text: $notes, axis: .vertical)
                if existing != nil {
                    Section { Button("Delete Vaccination", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(existing == nil ? "Add Vaccination" : "Edit Vaccination")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    name = existing.vaccineName; date = existing.dateAdministered
                    clinic = existing.clinic; notes = existing.notes
                    if let exp = existing.expirationDate { hasExpiry = true; expiry = exp }
                }
            }
            .alert("Delete this vaccination?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let existing {
                        let vaxID = existing.id
                        context.delete(existing)
                        do {
                            try context.save()
                            NotificationService.shared.cancel(ids: ["vax-\(vaxID.uuidString)"])
                            dismiss()
                        } catch {
                            context.rollback()
                            saveError = "This vaccination could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                        }
                    }
                }
            }
        }
    }
    private func save() {
        let vax: VaccinationRecord
        if let existing { vax = existing } else {
            vax = VaccinationRecord(vaccineName: name, date: date)
            vax.pet = pet
            context.insert(vax)
        }
        vax.vaccineName = name; vax.dateAdministered = date
        vax.expirationDate = hasExpiry ? expiry : nil
        vax.clinic = clinic; vax.notes = notes
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        NotificationService.shared.cancel(ids: ["vax-\(vax.id.uuidString)"])
        if profiles.first?.remindersEnabled ?? false {
            NotificationService.shared.scheduleVaccinationReminder(vax, petName: pet.name)
        }
        dismiss()
    }
}


struct DocumentsView: View {
    @EnvironmentObject private var store: StoreManager
    @Bindable var pet: Pet
    @State private var showScanner = false
    @State private var showPremiumAlert = false
    var body: some View {
        List {
            if pet.documents.isEmpty { Text("No documents stored.").foregroundStyle(PCColor.secondaryText) }
            ForEach(pet.documents.sorted { $0.createdAt > $1.createdAt }) { doc in
                NavigationLink {
                    DocumentDetailView(document: doc)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(doc.title).font(.headline).foregroundStyle(PCColor.charcoal)
                        Text("\(doc.category.label) • \(doc.createdAt.formatted(date: .abbreviated, time: .omitted)) • original preserved — tap to view")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                }
            }
            Section {
                Button {
                    if EntitlementPolicy.canUse(.documentScanning, isPremium: store.isPremium) {
                        showScanner = true
                    } else { showPremiumAlert = true }
                } label: { Label("Scan a document", systemImage: "doc.viewfinder") }
                Text("Scanning uses on-device Vision OCR. Extracted details are shown for your review and are never saved automatically.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
        }
        .navigationTitle("Documents")
        .sheet(isPresented: $showScanner) { DocumentScannerView(pet: pet) }
        .alert("Premium", isPresented: $showPremiumAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text("Document scanning is a PetCare 360 Premium feature.") }
    }
}

/// Full document management (v1.2.4): view the preserved original, read
/// this page's own extracted text, share/export it, or delete it.
struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var document: MedicalDocument
    @State private var confirmDelete = false
    @State private var showShare = false
    @State private var deleteError = "" 

    var body: some View {
        List {
            Section("Original document") {
                if let data = document.originalData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if let data = document.originalData, data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
                    PDFKitView(data: data).frame(height: 420)
                } else if document.originalData != nil {
                    Text("The original file is preserved and can be shared or exported below. This format has no in-app preview.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                } else {
                    Text("No original file is stored for this document.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                }
                Text("\(document.category.label) • Saved \(document.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
            Section("Extracted text (this page)") {
                if document.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No text was extracted from this page.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                } else {
                    Text(document.extractedText).font(.subheadline).textSelection(.enabled)
                }
            }
            Section {
                Button { showShare = true } label: { Label("Share / export document", systemImage: "square.and.arrow.up") }
                    .disabled(document.originalData == nil)
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete document", systemImage: "trash")
                }
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare) {
            if let data = document.originalData { ShareSheet(items: [data]) }
        }
        .alert("Delete this document?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                context.delete(document)
                do { try context.save(); dismiss() } catch {
                    context.rollback()
                    deleteError = "This document could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                }
            }
        } message: {
            Text("The preserved original and its extracted text will be permanently deleted. This cannot be undone.")
        }
        .alert("Delete failed", isPresented: Binding(get: { !deleteError.isEmpty }, set: { if !$0 { deleteError = "" } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(deleteError) }
    }
}

struct AppointmentsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var pet: Pet
    @State private var showEditor = false
    @State private var apptToEdit: VetAppointment? = nil
    @State private var showPremiumAlert = false
    @EnvironmentObject private var store: StoreManager
    var body: some View {
        List {
            if pet.appointments.isEmpty { Text("No appointments.").foregroundStyle(PCColor.secondaryText) }
            ForEach(pet.appointments.sorted { $0.date < $1.date }) { appt in
                VStack(alignment: .leading, spacing: 3) {
                    Text(appt.title).font(.headline).foregroundStyle(PCColor.charcoal)
                    Text("\(appt.date.formatted(date: .abbreviated, time: .shortened)) • \(appt.clinic)")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                    if !appt.questionList.isEmpty {
                        Text("Questions: \(appt.questionList.joined(separator: "; "))").font(.caption)
                    }
                    HStack(spacing: 16) {
                        if store.isPremium {
                            PDFShareButton(title: "Visit Preparation PDF") {
                                PDFService.visitPreparation(pet: pet, appointment: appt)
                            }
                        } else {
                            Button("Visit Preparation PDF") { showPremiumAlert = true }
                        }
                        Button("Edit") { apptToEdit = appt }
                    }
                    .font(.caption)
                }
            }
        }
        .navigationTitle("Appointments")
        .toolbar { Button { showEditor = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showEditor) { AppointmentEditorView(pet: pet) }
        .sheet(item: $apptToEdit) { appt in AppointmentEditorView(pet: pet, existing: appt) }
        .alert("Premium", isPresented: $showPremiumAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text("This is a PetCare 360 Premium feature. Your existing records stay fully visible, editable, exportable and deletable on the free plan.") }
    }
}

struct AppointmentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    let pet: Pet
    let existing: VetAppointment?
    init(pet: Pet, existing: VetAppointment? = nil) { self.pet = pet; self.existing = existing }
    @State private var title = ""
    @State private var clinic = ""
    @State private var vet = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var questions = ""
    @State private var isCompleted = false
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Appointment title", text: $title)
                TextField("Clinic", text: $clinic)
                TextField("Veterinarian", text: $vet)
                DatePicker("Date & time", selection: $date)
                TextField("Notes", text: $notes, axis: .vertical)
                TextField("Questions to ask (one per line)", text: $questions, axis: .vertical)
                if existing != nil { Toggle("Completed", isOn: $isCompleted) }
                Text("PetCare 360 organises your visit; it does not book appointments with clinics.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                if existing != nil {
                    Section { Button("Delete Appointment", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(existing == nil ? "Add Appointment" : "Edit Appointment")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    title = existing.title; clinic = existing.clinic; vet = existing.vetName
                    date = existing.date; notes = existing.notes; questions = existing.questions
                    isCompleted = existing.isCompleted
                }
            }
            .alert("Delete this appointment?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let existing {
                        let apptID = existing.id
                        context.delete(existing)
                        do {
                            try context.save()
                            NotificationService.shared.cancel(ids: ["appt-\(apptID.uuidString)"])
                            dismiss()
                        } catch {
                            context.rollback()
                            saveError = "This appointment could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                        }
                    }
                }
            }
        }
    }
    private func save() {
        let appt: VetAppointment
        if let existing { appt = existing } else {
            appt = VetAppointment(title: title, date: date)
            appt.pet = pet
            context.insert(appt)
        }
        appt.title = title; appt.clinic = clinic; appt.vetName = vet
        appt.date = date; appt.notes = notes; appt.questions = questions
        appt.isCompleted = isCompleted
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        NotificationService.shared.cancel(ids: ["appt-\(appt.id.uuidString)"])
        if (profiles.first?.remindersEnabled ?? false)
            && NotificationService.shouldScheduleAppointmentReminder(appt) {
            NotificationService.shared.scheduleOneOff(
                id: "appt-\(appt.id.uuidString)", title: "Vet appointment: \(pet.name)",
                body: title, fireDate: appt.date.addingTimeInterval(-3600))
        }
        dismiss()
    }
}


struct HealthChartsView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.modelContext) private var context
    @Bindable var pet: Pet
    @State private var showEditor = false
    @State private var range: String = "All"
    private let ranges = ["Month", "Year", "All"]

    private var weightPoints: [HealthObservation] {
        let weights = pet.observations.filter { $0.kind == .weight && $0.weightKg != nil }
            .sorted { $0.date < $1.date }
        switch range {
        case "Month":
            guard let cutoff = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return weights }
            return weights.filter { $0.date > cutoff }
        case "Year":
            guard let cutoff = Calendar.current.date(byAdding: .year, value: -1, to: Date()) else { return weights }
            return weights.filter { $0.date > cutoff }
        default: return weights
        }
    }

    var body: some View {
        List {
            Section("Weight History") {
                if !store.isPremium {
                    Label("Advanced health charts are a Premium feature. Your weight history below stays fully available on the free plan.", systemImage: "lock")
                        .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                } else if weightPoints.count < 2 {
                    Text("Add at least two weight observations to see the chart.").foregroundStyle(PCColor.secondaryText)
                } else {
                    Chart(weightPoints) { point in
                        LineMark(x: .value("Date", point.date), y: .value("kg", point.weightKg ?? 0))
                            .foregroundStyle(PCColor.freshGreen)
                        PointMark(x: .value("Date", point.date), y: .value("kg", point.weightKg ?? 0))
                            .foregroundStyle(PCColor.deepTeal)
                    }
                    .frame(height: 180)
                    .accessibilityLabel("Weight history chart for \(pet.name)")
                }
                Picker("Range", selection: $range) {
                    ForEach(ranges, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                ForEach(weightPoints) { point in
                    Text("\(point.date.formatted(date: .abbreviated, time: .omitted)): \(point.weightKg ?? 0, specifier: "%.1f") kg")
                        .font(.subheadline)
                }
            }
            Section("Timeline") {
                ForEach(pet.observations.sorted { $0.date > $1.date }) { obs in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(obs.kind.label): \(obs.valueText)").font(.subheadline).foregroundStyle(PCColor.charcoal)
                        Text(obs.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(PCColor.secondaryText)
                        if !obs.note.isEmpty { Text(obs.note).font(.caption) }
                    }
                }
                if pet.observations.isEmpty { Text("No observations yet.").foregroundStyle(PCColor.secondaryText) }
            }
            Section {
                Text("Health tracking is record-keeping only. PetCare 360 never declares a pet healthy or sick and does not diagnose.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
        }
        .navigationTitle("Health — \(pet.name)")
        .toolbar { Button { showEditor = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showEditor) { ObservationEditorView(pet: pet) }
    }
}

struct ObservationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let pet: Pet
    @State private var kind: ObservationKind = .weight
    @State private var value = ""
    @State private var weight = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(ObservationKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                if kind == .weight {
                    TextField("Weight (kg)", text: $weight).keyboardType(.decimalPad)
                } else {
                    TextField("Observation", text: $value)
                }
                TextField("Note", text: $note, axis: .vertical)
            }
            .navigationTitle("Add Observation")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let obs = HealthObservation(kind: kind, date: date)
                        if kind == .weight {
                            obs.weightKg = Double(weight)
                            obs.valueText = "\(weight) kg"
                            if let w = obs.weightKg { pet.weightKg = w }
                        } else { obs.valueText = value }
                        obs.note = note; obs.pet = pet
                        context.insert(obs)
                        do { try context.save() } catch {
                            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
                            return
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExpensesView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.modelContext) private var context
    @Bindable var pet: Pet
    @State private var showEditor = false
    @State private var expenseToEdit: PetExpense? = nil
    @State private var showPremiumAlert = false
    private var expenses: [PetExpense] { pet.expenses.sorted { $0.date > $1.date } }
    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("This month", value: FinancialCalculationService.format(FinancialCalculationService.total(expenses, inMonthOf: Date())))
                LabeledContent("This year", value: FinancialCalculationService.format(FinancialCalculationService.total(expenses, inYearOf: Date())))
                LabeledContent("All time", value: FinancialCalculationService.format(FinancialCalculationService.total(expenses)))
                ForEach(FinancialCalculationService.totalsByCategory(expenses), id: \.0) { category, sum in
                    LabeledContent(category.label, value: FinancialCalculationService.format(sum))
                }
            }
            Section("Entries") {
                if expenses.isEmpty { Text("No expenses yet.").foregroundStyle(PCColor.secondaryText) }
                ForEach(expenses) { expense in
                    Button { expenseToEdit = expense } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(expense.category.label).foregroundStyle(PCColor.charcoal)
                                Text("\(expense.date.formatted(date: .abbreviated, time: .omitted))\(expense.vendor.isEmpty ? "" : " • \(expense.vendor)")")
                                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                            }
                            Spacer()
                            Text(FinancialCalculationService.format(expense.amount))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit expense \(expense.category.label)")
                }
            }
            Section {
                if store.isPremium {
                    PDFShareButton(title: "Export Expense Report PDF") {
                        PDFService.expenseReport(petName: pet.name, expenses: expenses)
                    }
                } else {
                    Button("Export Expense Report PDF") { showPremiumAlert = true }
                }
            }
        }
        .navigationTitle("Expenses — \(pet.name)")
        .toolbar { Button { if store.isPremium { showEditor = true } else { showPremiumAlert = true } } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showEditor) { ExpenseEditorView(pet: pet) }
        .sheet(item: $expenseToEdit) { expense in ExpenseEditorView(pet: pet, existing: expense) }
        .alert("Premium", isPresented: $showPremiumAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text("This is a PetCare 360 Premium feature. Your existing records stay fully visible, editable, exportable and deletable on the free plan.") }
    }
}

struct ExpenseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let pet: Pet
    let existing: PetExpense?
    init(pet: Pet, existing: PetExpense? = nil) { self.pet = pet; self.existing = existing }
    @State private var amount = ""
    @State private var category: ExpenseCategory = .other
    @State private var vendor = ""
    @State private var notes = ""
    @State private var date = Date()
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Amount (USD)", text: $amount).keyboardType(.decimalPad)
                Picker("Category", selection: $category) {
                    ForEach(ExpenseCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Vendor", text: $vendor)
                TextField("Notes", text: $notes, axis: .vertical)
                if existing != nil {
                    Section { Button("Delete Expense", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(existing == nil ? "Add Expense" : "Edit Expense")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(Decimal(string: amount) == nil)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    amount = existing.amountString; category = existing.category
                    vendor = existing.vendor; notes = existing.notes; date = existing.date
                }
            }
            .alert("Delete this expense?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let existing {
                        context.delete(existing)
                        do { try context.save(); dismiss() } catch {
                            context.rollback()
                            saveError = "This expense could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                        }
                    }
                }
            }
        }
    }
    private func save() {
        guard let value = Decimal(string: amount), value > 0 else { return }
        if let existing {
            existing.amountString = NSDecimalNumber(decimal: value).stringValue
            existing.categoryRaw = category.rawValue
            existing.vendor = vendor; existing.notes = notes; existing.date = date
        } else {
            let expense = PetExpense(amount: value, category: category, date: date)
            expense.vendor = vendor; expense.notes = notes; expense.pet = pet
            context.insert(expense)
        }
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        dismiss()
    }
}


struct InsuranceView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.modelContext) private var context
    @Bindable var pet: Pet
    @Query private var policies: [InsurancePolicy]
    @State private var showEditor = false
    @State private var policyToEdit: InsurancePolicy? = nil
    @State private var claimToEdit: InsuranceClaim? = nil
    @State private var showPremiumAlert = false
    @State private var claimPolicy: InsurancePolicy? = nil
    private var myPolicies: [InsurancePolicy] { policies.filter { $0.petID == pet.id } }
    var body: some View {
        List {
            if myPolicies.isEmpty {
                Text("No insurance policies saved. PetCare 360 stores the details you enter; it does not connect to insurance providers.")
                    .foregroundStyle(PCColor.secondaryText)
            }
            ForEach(myPolicies) { policy in
                Section(policy.provider) {
                    LabeledContent("Policy number", value: policy.policyNumber)
                    LabeledContent("Deductible", value: FinancialCalculationService.format(policy.deductible))
                    LabeledContent("Reimbursement", value: "\(policy.reimbursementPercent)%")
                    if let renewal = policy.renewalDate {
                        LabeledContent("Renewal", value: renewal.formatted(date: .abbreviated, time: .omitted))
                    }
                    ForEach(policy.claims.sorted { $0.date > $1.date }) { claim in
                        Button { claimToEdit = claim } label: {
                            HStack {
                                Text("\(claim.title) — \(claim.status.label)").font(.subheadline)
                                Spacer()
                                Text(FinancialCalculationService.format(claim.amount)).font(.subheadline)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Edit claim \(claim.title)")
                    }
                    HStack(spacing: 16) {
                        Button("Add claim") {
                            if store.isPremium { claimPolicy = policy } else { showPremiumAlert = true }
                        }
                        Button("Edit policy") { policyToEdit = policy }
                    }
                }
            }
        }
        .navigationTitle("Insurance — \(pet.name)")
        .toolbar { Button { if store.isPremium { showEditor = true } else { showPremiumAlert = true } } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showEditor) { InsuranceEditorView(pet: pet) }
        .sheet(item: $policyToEdit) { policy in InsuranceEditorView(pet: pet, existing: policy) }
        .sheet(item: $claimToEdit) { claim in ClaimEditorView(policy: claim.policy, existing: claim) }
        .sheet(item: $claimPolicy) { policy in
            NavigationStack { ClaimEditorView(policy: policy) }
        }
        .alert("Premium", isPresented: $showPremiumAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text("This is a PetCare 360 Premium feature. Your existing records stay fully visible, editable, exportable and deletable on the free plan.") }
    }
}

struct InsuranceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    let pet: Pet
    let existing: InsurancePolicy?
    init(pet: Pet, existing: InsurancePolicy? = nil) { self.pet = pet; self.existing = existing }
    @State private var provider = ""
    @State private var number = ""
    @State private var coverage = ""
    @State private var deductible = ""
    @State private var reimbursement = ""
    @State private var hasRenewal = false
    @State private var renewal = Date()
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Provider", text: $provider)
                TextField("Policy number", text: $number)
                TextField("Coverage details", text: $coverage, axis: .vertical)
                TextField("Deductible (USD)", text: $deductible).keyboardType(.decimalPad)
                TextField("Reimbursement %", text: $reimbursement).keyboardType(.numberPad)
                Toggle("Renewal date", isOn: $hasRenewal)
                if hasRenewal { DatePicker("Renewal", selection: $renewal, displayedComponents: .date) }
                if existing != nil {
                    Section {
                        Button("Delete Policy", role: .destructive) { confirmDelete = true }
                        Text("Deleting a policy also deletes its claims on this device.")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Policy" : "Edit Policy")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(provider.isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    provider = existing.provider; number = existing.policyNumber
                    coverage = existing.coverageDetails; deductible = existing.deductibleString
                    reimbursement = String(existing.reimbursementPercent)
                    if let date = existing.renewalDate { hasRenewal = true; renewal = date }
                }
            }
            .alert("Delete this policy?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let existing {
                        let policyID = existing.id
                        context.delete(existing)
                        do {
                            try context.save()
                            // Cancel the renewal reminder only AFTER
                            // the deletion is saved (v1.2.6 ordering).
                            NotificationService.shared.cancel(ids: ["ins-\(policyID.uuidString)"])
                            dismiss()
                        } catch {
                            context.rollback()
                            saveError = "This policy could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                        }
                    }
                }
            } message: { Text("The policy and its claims will be permanently deleted.") }
        }
    }
    private func save() {
        let policy: InsurancePolicy
        if let existing { policy = existing } else {
            policy = InsurancePolicy(provider: provider, petID: pet.id, petName: pet.name)
            context.insert(policy)
        }
        policy.provider = provider; policy.policyNumber = number
        policy.coverageDetails = coverage
        policy.deductibleString = deductible.isEmpty ? "0" : deductible
        policy.reimbursementPercent = Int(reimbursement) ?? 0
        policy.renewalDate = hasRenewal ? renewal : nil
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        NotificationService.shared.cancel(ids: ["ins-\(policy.id.uuidString)"])
        if hasRenewal && (profiles.first?.remindersEnabled ?? false) {
            let fire = Calendar.current.date(byAdding: .day, value: -14, to: renewal) ?? renewal
            NotificationService.shared.scheduleOneOff(id: "ins-\(policy.id.uuidString)",
                title: "Insurance renewal soon", body: "\(pet.name): \(provider) renews soon", fireDate: fire)
        }
        dismiss()
    }
}


struct ClaimEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let policy: InsurancePolicy?
    let existing: InsuranceClaim?
    init(policy: InsurancePolicy?, existing: InsuranceClaim? = nil) {
        self.policy = policy
        self.existing = existing
    }
    @State private var title = ""
    @State private var amount = ""
    @State private var status: ClaimStatus = .draft
    @State private var notes = ""
    @State private var confirmDelete = false
    @State private var loaded = false
    @State private var saveError = ""
    var body: some View {
        Form {
            TextField("Claim title", text: $title)
            TextField("Amount (USD)", text: $amount).keyboardType(.decimalPad)
            Picker("Status", selection: $status) {
                ForEach(ClaimStatus.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            TextField("Notes", text: $notes, axis: .vertical)
            Button(existing == nil ? "Save Claim" : "Save Changes") { save() }
                .disabled(title.isEmpty || Decimal(string: amount) == nil)
            if existing != nil {
                Button("Delete Claim", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(existing == nil ? "Add Claim" : "Edit Claim")
        .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
                title = existing.title; amount = existing.amountString
                status = existing.status; notes = existing.notes
            }
        }
        .alert("Delete this claim?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let existing {
                    context.delete(existing)
                    do { try context.save(); dismiss() } catch {
                        context.rollback()
                        saveError = "This claim could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                    }
                }
            }
        }
    }
    private func save() {
        guard let value = Decimal(string: amount) else { return }
        if let existing {
            existing.title = title
            existing.amountString = NSDecimalNumber(decimal: value).stringValue
            existing.statusRaw = status.rawValue
            existing.notes = notes
        } else {
            guard let policy else { return }
            let claim = InsuranceClaim(title: title, amount: value)
            claim.statusRaw = status.rawValue
            claim.notes = notes
            claim.policy = policy
            context.insert(claim)
        }
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        dismiss()
    }
}


struct RecallsView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.modelContext) private var context
    @State private var showPremiumAlert = false
    @Query private var brands: [SavedFoodBrand]
    @Query private var alerts: [RecallAlert]
    @State private var newBrand = ""
    @State private var saveError = ""
    @AppStorage("recallLastCheckedEpoch") private var lastCheckedEpoch: Double = 0
    private var lastChecked: Date? { lastCheckedEpoch > 0 ? Date(timeIntervalSince1970: lastCheckedEpoch) : nil }
    var body: some View {
        List {
            Section("Official Source") {
                Text("Recall information comes only from the US FDA Center for Veterinary Medicine. PetCare 360 never invents recalls. Checks are manual: the app does not monitor the FDA automatically or send recall notifications — open the FDA page and record anything that affects your saved brands.")

                    .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                Link("Open FDA Recalls & Withdrawals", destination: AppConfig.fdaRecallsURL)
                if let lastChecked {
                    Text("Last opened: \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                } else {
                    Text("No successful check yet on this device. If you are offline, connect and open the FDA page.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                }
                Button("Mark FDA page checked now") { lastCheckedEpoch = Date().timeIntervalSince1970 }
            }
            Section("Your Saved Brands") {
                ForEach(brands, id: \.id) { brand in Text(brand.brand) }
                HStack {
                    TextField("Brand to watch", text: $newBrand)
                    Button("Add") {
                        guard store.isPremium else { showPremiumAlert = true; return }
                        guard !newBrand.isEmpty else { return }
                        context.insert(SavedFoodBrand(brand: newBrand))
                        do { try context.save() } catch {
                            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
                            return
                        }
                        newBrand = ""
                    }
                }
            }
            Section("Saved Recall Entries") {
                if alerts.isEmpty {
                    Text("No recall entries saved. When the FDA publishes a recall affecting a brand you use, open it above and record it here from the official notice.")
                        .foregroundStyle(PCColor.secondaryText)
                }
                ForEach(alerts, id: \.id) { alert in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.productName).font(.headline)
                        Text("\(alert.manufacturer) • \(alert.recallDate.formatted(date: .abbreviated, time: .omitted))").font(.caption)
                        Text(alert.reason).font(.subheadline)
                        if let url = URL(string: alert.sourceURL) { Link("Official source", destination: url).font(.caption) }
                    }
                }
            }
        }
        .navigationTitle("Recall Tracking")
        .alert("Premium", isPresented: $showPremiumAlert) {
            Button("OK", role: .cancel) {}
        } message: { Text("This is a PetCare 360 Premium feature. Your existing records stay fully visible, editable, exportable and deletable on the free plan.") }
    }
}

struct LostPetView: View {
    @Bindable var pet: Pet
    @State private var lastSeen = ""
    @State private var contact = ""
    @State private var includeMicrochip = false
    @State private var consent = false
    var body: some View {
        Form {
            Section("Shareable Profile") {
                HStack { PetAvatar(pet: pet, size: 64); Text(pet.name).font(.title2.bold()) }
                LabeledContent("Species / breed", value: "\(pet.species.label) / \(pet.breed)")
                LabeledContent("Identifying features", value: pet.colorMarkings)
            }
            Section("Owner-approved details") {
                TextField("Last-seen location (optional)", text: $lastSeen)
                TextField("Contact method to publish", text: $contact)
                Toggle("Include microchip number", isOn: $includeMicrochip)
                Toggle("I consent to share these details on the poster", isOn: $consent)
                Text("Nothing is published anywhere by the app. The poster is a PDF you choose to share or print.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
            Section {
                PDFShareButton(title: "Create Lost-Pet Poster PDF") {
                    PDFService.lostPetPoster(pet: pet, lastSeen: lastSeen, contactMethod: contact, includeMicrochip: includeMicrochip)
                }
                .disabled(!consent)
            }
        }
        .navigationTitle("Lost Pet — \(pet.name)")
    }
}
