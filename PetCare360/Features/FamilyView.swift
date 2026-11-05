import SwiftUI
import SwiftData
import UIKit

struct FamilyView: View {
    @EnvironmentObject private var store: StoreManager
    @Query private var households: [Household]
    @Query private var profiles: [UserProfile]
    @Query private var handoffs: [CareHandoff]
    @State private var showPaywall = false
    @State private var showMemberEditor = false
    @State private var handoffToDelete: CareHandoff? = nil
    @State private var deleteError = ""

    private var household: Household? { households.first }
    private var myRole: HouseholdRole {
        // Resolved by stable member ID, never by display name (Phase 2 G).
        // No match -> Viewer (read-only), never accidental full access.
        guard let profile = profiles.first else { return .viewer }
        return HouseholdIdentity.resolveRole(memberID: profile.memberID,
                                             members: household?.members ?? []) ?? .viewer
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Household") {
                    if !store.isPremium {
                        Text("Household coordination is a Premium feature. Your household is kept on this device only and unlocks when you subscribe.")
                            .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                        Button("See Premium") { showPaywall = true }
                    }
                    ForEach(household?.members.sorted { $0.displayName < $1.displayName } ?? []) { member in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(member.displayName).foregroundStyle(PCColor.charcoal)
                                Text("\(member.role.label)\(member.isInvitationPending ? " • Local record" : "")\(member.hasActiveAccess ? "" : " • Access inactive/expired")")
                                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                            }
                            Spacer()
                            if HouseholdPermissions.can(myRole, do: .managePets) && member.role != .owner {
                                Button("Remove", role: .destructive) { remove(member) }
                                    .font(.caption)
                            }
                        }
                    }
                    if HouseholdPermissions.can(myRole, do: .managePets) {
                        Button("Add member") { if store.isPremium { showMemberEditor = true } else { showPaywall = true } }
                    }
                }
                Section("Roles on this device") {
                    Text("Roles organise who usually does what in this household's records on THIS device. They are not separate accounts, there is no member sign-in, and they do not lock anyone out of this shared device — treat them as care organisation, not access control.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                    ForEach(HouseholdRole.allCases, id: \.self) { role in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(role.label).font(.subheadline.bold())
                            Text(HouseholdPermissions.permissions(for: role).map { $0.rawValue }.sorted().joined(separator: ", "))
                                .font(.caption).foregroundStyle(PCColor.secondaryText)
                        }
                    }
                    Text("Roles help organise household responsibilities. Everyone using this device may be able to access the information stored in the app — roles are not separate accounts and do not restrict access on this shared device.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                }
                Section("Care Handoffs") {
                    if handoffs.isEmpty { Text("No handoffs yet.").foregroundStyle(PCColor.secondaryText) }
                    ForEach(handoffs.sorted { $0.date > $1.date }.prefix(10)) { handoff in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(handoff.petName) — \(handoff.authorName)").font(.subheadline).foregroundStyle(PCColor.charcoal)
                            Text(handoff.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(PCColor.secondaryText)
                            Text([handoff.wasFed ? "Fed" : nil, handoff.medicationGiven ? "Medication given" : nil,
                                  handoff.walkCompleted ? "Walked" : nil, handoff.appetiteNormal ? "Appetite normal" : "Appetite NOT normal"]
                                .compactMap { $0 }.joined(separator: " • ")).font(.caption)
                            if !handoff.unusualBehavior.isEmpty { Text("Unusual: \(handoff.unusualBehavior)").font(.caption) }
                            if !handoff.notes.isEmpty { Text(handoff.notes).font(.caption) }
                            Button("Delete handoff", role: .destructive) { handoffToDelete = handoff }
                                .font(.caption)
                        }
                    }
                }
                Section("App") {
                    NavigationLink("Emergency profiles") { EmergencyListView() }
                    NavigationLink("Settings & data") { SettingsView() }
                    Button("PetCare 360 Premium") { showPaywall = true }
                    if store.isPremium {
                        Label("Premium active", systemImage: "checkmark.seal.fill").foregroundStyle(PCColor.freshGreen)
                    }
                }
                Section {
                    Text(AppConfig.medicalDisclaimer).font(.caption).foregroundStyle(PCColor.secondaryText)
                }
            }
            .navigationTitle("Family")
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .sheet(isPresented: $showMemberEditor) { MemberEditorView() }
            .alert("Delete this handoff?", isPresented: Binding(
                get: { handoffToDelete != nil },
                set: { if !$0 { handoffToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { handoffToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let handoffToDelete {
                        context.delete(handoffToDelete)
                        do { try context.save() } catch {
                            context.rollback()
                            deleteError = "This handoff could not be deleted. That could not be saved on this device, so nothing was changed. Please try again."
                        }
                    }
                    handoffToDelete = nil
                }
            } message: { Text("This care handoff will be permanently deleted.") }
            .alert("Couldn't delete", isPresented: Binding(get: { !deleteError.isEmpty }, set: { if !$0 { deleteError = "" } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(deleteError) }
        }
    }

    @Environment(\.modelContext) private var context
    private func remove(_ member: HouseholdMember) {
        context.delete(member)
        do { try context.save() } catch {
            context.rollback()
            deleteError = "That member could not be removed. That could not be saved on this device, so nothing was changed. Please try again."
        }
    }
}

struct MemberEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var households: [Household]
    @State private var name = ""
    @State private var email = ""
    @State private var role: HouseholdRole = .viewer
    @State private var temporary = false
    @State private var expires = Date().addingTimeInterval(7 * 24 * 3600)
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Email (for your records)", text: $email).keyboardType(.emailAddress)
                Picker("Role", selection: $role) {
                    ForEach(HouseholdRole.allCases.filter { $0 != .owner }, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Temporary access", isOn: $temporary)
                if temporary { DatePicker("Access expires", selection: $expires) }
                Text("Members are recorded on THIS device only. Nothing is sent to the person, they cannot accept or view anything, and no data syncs between devices — cross-device iCloud sharing is not part of this build.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
            .navigationTitle("Add Member")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let household = households.first else { return }
                        let member = HouseholdMember(displayName: name, role: role)
                        member.invitedEmail = email
                        member.accessExpiresAt = temporary ? expires : nil
                        member.household = household
                        context.insert(member)
                        do { try context.save() } catch {
                            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
                            return
                        }
                        dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}

struct EmergencyListView: View {
    @Query(filter: #Predicate<Pet> { !$0.isArchived }) private var pets: [Pet]
    var body: some View {
        List {
            if pets.isEmpty { Text("Add a pet first.").foregroundStyle(PCColor.secondaryText) }
            ForEach(pets) { pet in
                NavigationLink(pet.name) { EmergencyView(pet: pet) }
            }
        }
        .navigationTitle("Emergency Profiles")
    }
}

/// Emergency Mode: large, readable, high-contrast. Shows only what the
/// owner put on the pet profile. PetCare 360 does not provide emergency
/// veterinary treatment — it shows your information fast.
struct EmergencyView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var store: StoreManager
    @Bindable var pet: Pet
    @Query private var emergencyProfiles: [EmergencyProfile]
    @State private var showQRSetup = false

    private var profile: EmergencyProfile? { emergencyProfiles.first { $0.petID == pet.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    PetAvatar(pet: pet, size: 96)
                    Text(pet.name).font(.largeTitle.bold()).foregroundStyle(PCColor.charcoal)
                }
                emergencyRow("Emergency contact", "\(pet.emergencyContactName) \(pet.emergencyContactPhone)")
                emergencyRow("Veterinary clinic", "\(pet.vetClinic) \(pet.vetPhone)")
                emergencyRow("Allergies", pet.allergies)
                emergencyRow("Medical conditions", pet.medicalConditions)
                emergencyRow("Microchip", pet.microchipNumber)
                emergencyRow("Insurance", pet.insuranceInfo)
                if !pet.medications.filter({ $0.isActive }).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current medications").font(.headline)
                        ForEach(pet.medications.filter { $0.isActive }) { med in
                            Text("• \(med.name) \(med.dosage)").font(.title3)
                        }
                    }
                    .pcCard()
                }
                if !pet.notes.isEmpty { emergencyRow("Emergency notes", pet.notes) }
                Section {
                    if store.isPremium {
                        Button("Emergency QR profile settings") { showQRSetup = true }
                        if let profile, profile.isEnabled {
                            let payload = EmergencyService.payload(pet: pet, profile: profile, medications: pet.medications)
                            if let qr = EmergencyService.qrImage(from: payload) {
                                Image(uiImage: qr).resizable().interpolation(.none).frame(width: 180, height: 180)
                                    .accessibilityLabel("Emergency QR code for \(pet.name)")
                                Text("Shows only the fields you enabled. Turning the QR profile off hides the code in this app — it cannot recall copies already photographed or printed, because the code contains the information itself. Treat shared copies like the information they show. QR settings last saved \(profile.updatedAt.formatted(date: .abbreviated, time: .omitted)).")
                                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                            }
                        }
                    } else {
                        Text("The shareable Emergency QR profile is a Premium feature. This emergency screen is always free.")
                            .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                    }
                }
                Text("In a life-threatening emergency, contact your veterinarian or an emergency animal hospital immediately. PetCare 360 does not provide emergency veterinary treatment.")
                    .font(.subheadline.bold()).foregroundStyle(PCColor.errorRed)
            }
            .padding()
        }
        .background(PCColor.warmIvory)
        .navigationTitle("Emergency — \(pet.name)")
        .sheet(isPresented: $showQRSetup) { EmergencyQRSetupView(pet: pet) }
    }

    private func emergencyRow(_ label: String, _ value: String) -> some View {
        Group {
            if !value.trimmingCharacters(in: .whitespaces).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.headline).foregroundStyle(PCColor.secondaryText)
                    Text(value).font(.title3).foregroundStyle(PCColor.charcoal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .pcCard()
            }
        }
    }
}

struct EmergencyQRSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var emergencyProfiles: [EmergencyProfile]
    let pet: Pet
    @State private var enabled = false
    @State private var selected: Set<String> = []
    private let labels: [String: String] = [
        "allergies": "Allergies", "medications": "Current medications", "conditions": "Medical conditions",
        "microchip": "Microchip number", "vet": "Veterinary clinic", "emergencyContact": "Emergency contact",
        "insurance": "Insurance details", "notes": "Emergency notes", "photo": "Photo"
    ]
    @State private var saveError = ""
    var body: some View {
        NavigationStack {
            Form {
                Toggle("Enable QR emergency profile", isOn: $enabled)
                Text("Sensitive information is hidden by default. Only the fields you switch on are encoded in the QR code. No home address is ever included.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                Section("Fields to share") {
                    ForEach(EmergencyProfile.allFields, id: \.self) { key in
                        Toggle(labels[key] ?? key, isOn: Binding(
                            get: { selected.contains(key) },
                            set: { if $0 { selected.insert(key) } else { selected.remove(key) } }
                        ))
                        .disabled(!enabled)
                    }
                }
            }
            .navigationTitle("QR Profile — \(pet.name)")
            .alert("Couldn't save", isPresented: Binding(get: { !saveError.isEmpty }, set: { if !$0 { saveError = "" } })) { Button("OK", role: .cancel) {} } message: { Text(saveError) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                if let existing = emergencyProfiles.first(where: { $0.petID == pet.id }) {
                    enabled = existing.isEnabled
                    selected = Set(existing.sharedFieldKeys)
                }
            }
        }
    }
    private func save() {
        let profile = emergencyProfiles.first { $0.petID == pet.id } ?? EmergencyProfile(petID: pet.id, petName: pet.name)
        if profile.modelContext == nil { context.insert(profile) }
        profile.isEnabled = enabled
        profile.sharedFieldKeys = Array(selected)
        profile.updatedAt = Date()
        do { try context.save() } catch {
            saveError = "Your changes could not be saved on this device. Nothing was closed — please try again."
            return
        }
        dismiss()
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var allPets: [Pet]
    @Query private var households: [Household]
    @Query private var allTasks: [CareTask]
    @Query private var allHandoffs: [CareHandoff]
    @Query private var allFeedingLogs: [FeedingLog]
    @Query private var allPolicies: [InsurancePolicy]
    @Query private var allProfiles: [EmergencyProfile]
    @Query private var allBrands: [SavedFoodBrand]
    @Query private var allAlerts: [RecallAlert]
    @Query private var allSchedules: [MedicationSchedule]
    @Query private var allEntitlements: [SubscriptionEntitlement]
    @State private var exportData: Data? = nil
    @State private var showShare = false
    @State private var showDeleteConfirm = false
    @State private var importMessage = ""
    @State private var showImporter = false
    @State private var pendingImport: BackupService.ImportSource? = nil
    @State private var showPermissionDenied = false
    @State private var showImportPreview = false
    @State private var lastExportSummary: [(String, Int)] = []

    var body: some View {
        Form {
            Section("Reminders") {
                Toggle("Enable reminders", isOn: Binding(
                    get: { profiles.first?.remindersEnabled ?? false },
                    set: { newValue in
                        if let profile = profiles.first { profile.remindersEnabled = newValue }
                        if newValue {
                            Task {
                                let granted = await NotificationService.shared.requestAuthorizationIfNeeded()
                                if granted {
                                    // Rebuild immediately (v1.2.3): dose
                                    // reminders (global + per-medication
                                    // preferences respected) and the
                                    // one-off types from current data.
                                    NotificationService.shared.synchronizeReminders(
                                        pets: allPets, schedules: allSchedules, policies: allPolicies,
                                        remindersEnabled: true)
                                } else {
                                    // Never silently pretend reminders are
                                    // on when iOS will not deliver them.
                                    showPermissionDenied = true
                                }
                            }
                        } else {
                            NotificationService.shared.cancelAll()
                        }
                        do { try context.save() } catch {
                            context.rollback()
                            if let profile = profiles.first { profile.remindersEnabled = !newValue }
                            showPermissionDenied = false
                            importMessage = "That setting could not be saved on this device. Please try again."
                        }
                    }
                ))
                Text("Permission is only requested when you turn reminders on. Medication, feeding, vaccination, appointment, refill and insurance reminders are local notifications.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                Text("How medication reminders work: they are prepared one week at a time and refreshed whenever you open the app (iOS does not guarantee background refresh). If the app is not opened for more than a week, later dose reminders may not fire until you open it again.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
            Section("Your Data") {
                Button("Export full backup (JSON)") {
                    let backup = BackupService.makeFullBackup(
                        pets: allPets, households: households, careTasks: allTasks,
                        careHandoffs: allHandoffs, feedingLogs: allFeedingLogs,
                        insurancePolicies: allPolicies, emergencyProfiles: allProfiles,
                        savedBrands: allBrands, recallAlerts: allAlerts,
                        medicationSchedules: allSchedules)
                    exportData = try? BackupService.encode(backup)
                    lastExportSummary = backup.summary
                    showShare = exportData != nil
                }
                if !lastExportSummary.isEmpty {
                    Text("Backup created \(Date().formatted(date: .abbreviated, time: .shortened)) — includes: \(lastExportSummary.map { "\($0.0) (\($0.1))" }.joined(separator: ", ")). No passwords or credentials are ever included.")
                        .font(.caption).foregroundStyle(PCColor.secondaryText)
                }
                Button("Import backup (JSON)") { showImporter = true }
                if !importMessage.isEmpty { Text(importMessage).font(.caption) }
                Text("Your pets' data is stored on this device only. iCloud sync and cross-device sharing are not enabled in this build. PetCare 360 collects no analytics and does not track you.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
            }
            Section("Support") {
                Link("Contact Support", destination: AppConfig.supportMailtoURL)
                Text("Email us at \(AppConfig.supportEmail) and we will get back to you.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                Link("Website", destination: AppConfig.websiteURL)
                Link("Privacy Policy", destination: AppConfig.privacyPolicyURL)
                Link("Terms of Use", destination: AppConfig.termsOfUseURL)
            }
            Section {
                Button("Delete all my data", role: .destructive) { showDeleteConfirm = true }
                Text(AppConfig.medicalDisclaimer).font(.caption).foregroundStyle(PCColor.secondaryText)
            }
        }
        .navigationTitle("Settings & Data")
        .sheet(isPresented: $showShare) {
            if let exportData { ShareSheet(items: [exportData]) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .alert("Notifications are turned off for PetCare 360", isPresented: $showPermissionDenied) {
            Button("Open iOS Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Reminders are switched on in the app, but iOS permission is off, so no reminders can be delivered. You can allow notifications in iOS Settings.")
        }
        .sheet(isPresented: $showImportPreview) {
            if let importSource = pendingImport {
                ImportPreviewView(source: importSource) { strategy in
                    confirmImport(strategy: strategy)
                } onCancel: {
                    pendingImport = nil
                    showImportPreview = false
                }
            }
        }
        .alert("Delete all data?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) { deleteAll() }
        } message: {
            Text("This deletes every pet, record and household member on this device. This cannot be undone.")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { importMessage = "Import was cancelled."; return }
        guard url.startAccessingSecurityScopedResource() else { importMessage = "Could not read that file."; return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            // Fully decoded and validated BEFORE anything is shown or saved.
            pendingImport = try BackupService.decodeAny(data: data)
            showImportPreview = true
        } catch {
            importMessage = "That file is not a valid PetCare 360 backup. Nothing was imported."
        }
    }

    private func confirmImport(strategy: BackupService.RestoreStrategy) {
        guard let importToRestore = pendingImport else { return }
        defer {
            pendingImport = nil
            showImportPreview = false
        }
        switch importToRestore {
        case .v2(let backup):
            do {
                let summary = try BackupService.restore(backup, into: context, strategy: strategy)
                importMessage = "Imported \(summary.inserted) new record(s). Records that already existed were kept unchanged (merge never overwrites)."
            } catch {
                importMessage = "Import failed and was rolled back. Nothing was changed."
            }
        case .v1(let payload):
            // Legacy backups carry no IDs: pets are added as new profiles.
            for petBackup in payload.pets {
                let pet = Pet(name: petBackup.name, species: PetSpecies(rawValue: petBackup.species) ?? .other)
                pet.breed = petBackup.breed
                pet.dateOfBirth = petBackup.dateOfBirth
                pet.allergies = petBackup.allergies
                pet.medicalConditions = petBackup.medicalConditions
                pet.microchipNumber = petBackup.microchipNumber
                pet.notes = petBackup.notes
                context.insert(pet)
            }
            do {
                try context.save()
                importMessage = "Imported \(payload.pets.count) pet profile(s) from a legacy backup."
            } catch {
                context.rollback()
                importMessage = "That legacy backup could not be imported — nothing was saved. Please try again."
            }
        }
    }

    private func deleteAll() {
        for pet in allPets { context.delete(pet) }
        for household in households { context.delete(household) }
        for task in allTasks { context.delete(task) }
        for handoff in allHandoffs { context.delete(handoff) }
        for log in allFeedingLogs { context.delete(log) }
        for policy in allPolicies { context.delete(policy) }
        for profile in allProfiles { context.delete(profile) }
        for brand in allBrands { context.delete(brand) }
        for alert in allAlerts { context.delete(alert) }
        for schedule in allSchedules { context.delete(schedule) }
        for entitlement in allEntitlements { context.delete(entitlement) }
        for profile in profiles { context.delete(profile) }
        do {
            try context.save()
            NotificationService.shared.cancelAll()
        } catch {
            context.rollback()
            importMessage = "Your data could not be deleted — nothing was removed. Please try again."
        }
    }
}

/// Backup restore preview: shows exactly what a backup contains and lets
/// the user choose Merge (skip existing IDs, never overwrite) or Replace
/// (delete current data first) before anything is written.
struct ImportPreviewView: View {
    let source: BackupService.ImportSource
    let onConfirm: (BackupService.RestoreStrategy) -> Void
    let onCancel: () -> Void
    @State private var strategy: BackupService.RestoreStrategy = .merge

    private var rows: [(String, Int)] {
        switch source {
        case .v2(let backup): return backup.summary
        case .v1(let payload): return [("Pet profiles (legacy format)", payload.pets.count)]
        }
    }
    private var exportedAt: Date {
        switch source {
        case .v2(let backup): return backup.exportedAt
        case .v1(let payload): return payload.exportedAt
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Backup contents") {
                    LabeledContent("Created", value: exportedAt.formatted(date: .abbreviated, time: .shortened))
                    ForEach(rows, id: \.0) { row in
                        LabeledContent(row.0, value: "\(row.1)")
                    }
                }
                if case .v2 = source {
                    Section("Import strategy") {
                        Picker("Strategy", selection: $strategy) {
                            Text("Merge — keep my data, skip duplicates").tag(BackupService.RestoreStrategy.merge)
                            Text("Replace — delete my data, then import").tag(BackupService.RestoreStrategy.replace)
                        }
                        .pickerStyle(.inline)
                        if strategy == .replace {
                            Text("Replace permanently deletes everything currently in the app before importing. This cannot be undone.")
                                .font(.caption).foregroundStyle(PCColor.errorRed)
                        } else {
                            Text("Merge never overwrites existing records: anything whose ID already exists is skipped.")
                                .font(.caption).foregroundStyle(PCColor.secondaryText)
                        }
                    }
                } else {
                    Section {
                        Text("This is a legacy (v1) backup containing pet profiles only. They will be added as new pets.")
                            .font(.caption).foregroundStyle(PCColor.secondaryText)
                    }
                }
                Section {
                    Button("Import") { onConfirm(strategy) }
                    Button("Cancel", role: .cancel) { onCancel() }
                }
            }
            .navigationTitle("Review Backup")
        }
    }
}
