import SwiftUI
import SwiftData
import PhotosUI

struct PetsView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.modelContext) private var context
    @Query private var allPets: [Pet]
    @State private var showEditor = false
    @State private var showPremiumAlert = false
    @State private var showSaveError = false

    private var pets: [Pet] { allPets.filter { !$0.isArchived } }
    private var archived: [Pet] { allPets.filter { $0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                if pets.isEmpty {
                    PCEmptyState(icon: "pawprint", title: "No pets yet",
                                 message: "Add a profile for each of your pets.")
                }
                ForEach(pets) { pet in
                    NavigationLink {
                        PetDetailView(pet: pet)
                    } label: {
                        HStack(spacing: 12) {
                            PetAvatar(pet: pet)
                            VStack(alignment: .leading) {
                                Text(pet.name).font(.headline).foregroundStyle(PCColor.charcoal)
                                Text("\(pet.species.label)\(pet.breed.isEmpty ? "" : " • \(pet.breed)")\(pet.ageDescription.map { " • \($0)" } ?? "")")
                                    .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                            }
                        }
                    }
                }
                if !archived.isEmpty {
                    Section("Archived") {
                        ForEach(archived) { pet in
                            HStack {
                                Text(pet.name).foregroundStyle(PCColor.secondaryText)
                                Spacer()
                                Button("Restore") { restoreFromList(pet) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pets")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addPetTapped() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add pet")
                }
            }
            .sheet(isPresented: $showEditor) { PetEditorView(pet: nil) }
            .alert("Premium", isPresented: $showPremiumAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The free plan includes one pet. PetCare 360 Premium unlocks unlimited pet profiles.")
            }
            .alert("Couldn't restore", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That change could not be saved on this device, so nothing was changed. Please try again.")
            }
        }
    }

    /// The ONE restore path (v1.2.5): limit-checked, error-handled,
    /// reminder-rebuilding — shared with the pet detail screen.
    private func restoreFromList(_ pet: Pet) {
        switch PetArchiveService.restore(pet: pet, activeCount: pets.count,
                                         isPremium: store.isPremium, in: context) {
        case .done: break
        case .limitReached: showPremiumAlert = true
        case .saveFailed: showSaveError = true
        }
    }

    private func addPetTapped() {
        if EntitlementPolicy.canAddPet(currentCount: pets.count, isPremium: store.isPremium) {
            showEditor = true
        } else {
            showPremiumAlert = true
        }
    }
}

struct PetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: StoreManager
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var activePets: [Pet]
    @Bindable var pet: Pet
    @State private var showEditor = false
    @State private var showEmergency = false
    @State private var confirmDelete = false
    @State private var showRestoreLimitAlert = false
    @State private var showArchiveSaveError = false
    @State private var deleteError = "" 

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    PetAvatar(pet: pet, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pet.name).font(.title.bold()).foregroundStyle(PCColor.charcoal)
                        Text("\(pet.species.label) • \(pet.breed)").foregroundStyle(PCColor.secondaryText)
                        if let age = pet.ageDescription { Text("Age: \(age)").foregroundStyle(PCColor.secondaryText) }
                        if pet.weightKg > 0 { Text("Weight: \(pet.weightKg, specifier: "%.1f") kg").foregroundStyle(PCColor.secondaryText) }
                    }
                }
                Button {
                    showEmergency = true
                } label: {
                    Label("Emergency Profile", systemImage: "cross.case.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(PCColor.errorRed).foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                detailCard(title: "Details", rows: [
                    ("Gender", pet.gender.label),
                    ("Color / markings", pet.colorMarkings),
                    ("Microchip", pet.microchipNumber),
                    ("Allergies", pet.allergies),
                    ("Medical conditions", pet.medicalConditions),
                    ("Veterinary clinic", "\(pet.vetClinic) \(pet.vetPhone)"),
                    ("Emergency contact", "\(pet.emergencyContactName) \(pet.emergencyContactPhone)"),
                    ("Insurance", pet.insuranceInfo),
                    ("Notes", pet.notes)
                ])
            }
            .padding()
        }
        .background(PCColor.warmIvory)
        .navigationTitle(pet.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditor = true }
            }
            ToolbarItem(placement: .destructiveAction) {
                Menu {
                    Button(pet.isArchived ? "Restore" : "Archive") { archiveOrRestore() }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showEditor) { PetEditorView(pet: pet) }
        .sheet(isPresented: $showEmergency) { EmergencyView(pet: pet) }
        .alert("Delete \(pet.name)?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                        // Complete cleanup (v1.2.4): the service cancels
                        // every reminder (including insurance renewals)
                        // and deletes the petID-linked records that do
                        // not cascade — care tasks, feeding logs,
                        // insurance policies/claims, emergency profiles
                        // and medication schedule preferences.
                        // Failure handling (v1.2.5): on failure the
                        // context is rolled back (nothing partially
                        // deleted), the screen STAYS OPEN and an error
                        // is shown — success is never claimed falsely.
                        do {
                            try PetDeletionService.deleteAllData(for: pet, in: context)
                            dismiss()
                        } catch {
                            context.rollback()
                            deleteError = "This pet could not be deleted — nothing was removed. Please try again."
                        }
                    }
        } message: {
            Text("This permanently deletes the profile and its care history on this device.")
        }
        .alert("Couldn't save that change", isPresented: $showArchiveSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The change could not be saved on this device, so nothing was changed. Please try again.")
        }
        .alert("Delete failed", isPresented: Binding(get: { !deleteError.isEmpty }, set: { if !$0 { deleteError = "" } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(deleteError) }
        .alert("Pet limit reached", isPresented: $showRestoreLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The free plan includes 1 active pet. Restoring an archived pet counts toward that limit — PetCare 360 Premium allows unlimited pets.")
        }
    }

    private func archiveOrRestore() {
        let outcome = pet.isArchived
            ? PetArchiveService.restore(pet: pet, activeCount: activePets.count,
                                        isPremium: store.isPremium, in: context)
            : PetArchiveService.archive(pet: pet, in: context)
        switch outcome {
        case .done: break
        case .limitReached: showRestoreLimitAlert = true
        case .saveFailed: showArchiveSaveError = true
        }
    }

    private func detailCard(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PCSectionHeader(title: title)
            ForEach(rows, id: \.0) { label, value in
                if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    HStack(alignment: .top) {
                        Text(label).font(.subheadline).foregroundStyle(PCColor.secondaryText).frame(width: 130, alignment: .leading)
                        Text(value).font(.subheadline).foregroundStyle(PCColor.charcoal)
                    }
                }
            }
        }
        .pcCard()
    }
}

struct PetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let pet: Pet?
    @State private var name = ""
    @State private var species: PetSpecies = .dog
    @State private var breed = ""
    @State private var dob: Date = Date()
    @State private var hasDOB = false
    @State private var gender: PetGender = .unknown
    @State private var weight = ""
    @State private var colorMarkings = ""
    @State private var microchip = ""
    @State private var allergies = ""
    @State private var conditions = ""
    @State private var vetClinic = ""
    @State private var vetPhone = ""
    @State private var emergencyName = ""
    @State private var emergencyPhone = ""
    @State private var insurance = ""
    @State private var notes = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoData: Data? = nil

    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Photo") {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo")
                    }
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image).resizable().scaledToFit().frame(height: 140)
                    }
                }
                Section("Basics") {
                    TextField("Name", text: $name)
                    Picker("Species", selection: $species) {
                        ForEach(PetSpecies.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    TextField("Breed", text: $breed)
                    Picker("Gender", selection: $gender) {
                        ForEach(PetGender.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Toggle("Date of birth known", isOn: $hasDOB)
                    if hasDOB { DatePicker("Date of birth", selection: $dob, displayedComponents: .date) }
                    TextField("Weight (kg)", text: $weight).keyboardType(.decimalPad)
                    TextField("Color / markings", text: $colorMarkings)
                    TextField("Microchip number", text: $microchip)
                }
                Section("Health") {
                    TextField("Allergies", text: $allergies)
                    TextField("Existing medical conditions", text: $conditions)
                }
                Section("Contacts") {
                    TextField("Veterinary clinic", text: $vetClinic)
                    TextField("Vet phone", text: $vetPhone).keyboardType(.phonePad)
                    TextField("Emergency contact name", text: $emergencyName)
                    TextField("Emergency contact phone", text: $emergencyPhone).keyboardType(.phonePad)
                    TextField("Insurance information", text: $insurance)
                }
                Section("Notes") {
                    TextField("Important notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(pet == nil ? "New Pet" : "Edit Pet")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) { photoData = data }
                }
            }
        }
    }

    private func load() {
        guard let pet else { return }
        name = pet.name; species = pet.species; breed = pet.breed
        if let d = pet.dateOfBirth { dob = d; hasDOB = true }
        gender = pet.gender
        weight = pet.weightKg > 0 ? String(pet.weightKg) : ""
        colorMarkings = pet.colorMarkings; microchip = pet.microchipNumber
        allergies = pet.allergies; conditions = pet.medicalConditions
        vetClinic = pet.vetClinic; vetPhone = pet.vetPhone
        emergencyName = pet.emergencyContactName; emergencyPhone = pet.emergencyContactPhone
        insurance = pet.insuranceInfo; notes = pet.notes; photoData = pet.photoData
    }

    private func save() {
        let target = pet ?? Pet(name: name, species: species)
        if pet == nil { context.insert(target) }
        target.name = name; target.speciesRaw = species.rawValue; target.breed = breed
        target.dateOfBirth = hasDOB ? dob : nil
        target.genderRaw = gender.rawValue
        target.weightKg = Double(weight) ?? 0
        target.colorMarkings = colorMarkings; target.microchipNumber = microchip
        target.allergies = allergies; target.medicalConditions = conditions
        target.vetClinic = vetClinic; target.vetPhone = vetPhone
        target.emergencyContactName = emergencyName; target.emergencyContactPhone = emergencyPhone
        target.insuranceInfo = insurance; target.notes = notes; target.photoData = photoData
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        dismiss()
    }
}
