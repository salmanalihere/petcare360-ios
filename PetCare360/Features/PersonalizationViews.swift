import SwiftUI
import SwiftData
import UserNotifications
import UIKit

/// Personalization (owner brief 2026-11-07): the app icon and the
/// reminder sound are chosen during onboarding ("Personalize Your
/// PetCare360 — Make PetCare360 feel more like your pet.") and can be
/// changed later in Settings. Both write through the SAME stores the
/// rest of the app already reads: iOS itself persists the alternate
/// icon (`UIApplication.alternateIconName`), and the sound choice
/// uses the shared `pc-sound-*` UserDefaults keys read by
/// `NotificationSoundPreferences`.

// MARK: - Shared sound choice list

/// The sound picker used by onboarding and by Settings → Change
/// Notification Sound: the animal-sounds toggle, one selectable row
/// per bundled recording (each with a Play Preview), and the iOS
/// System Default option. Reptiles are explained honestly: they have
/// no recording, so their reminders use the iOS system default.
struct SoundChoiceList: View {
    @AppStorage(NotificationSoundPreferences.animalEnabledKey) private var animalSoundsEnabled = true
    @AppStorage(NotificationSoundPreferences.defaultKindKey) private var defaultSoundSelection = PetSoundKind.chime.rawValue
    @StateObject private var preview = SoundPreviewPlayer()

    var body: some View {
        Toggle("Animal-Specific Sounds", isOn: $animalSoundsEnabled)
        Text("When on, a reminder uses the sound matching its pet. Reptiles have no recording, so their reminders always use the iOS system default sound. Pets without a matching recording use the default sound below.")
            .font(.caption).foregroundStyle(PCColor.secondaryText)
        Text("Default sound").font(.subheadline.bold()).foregroundStyle(PCColor.charcoal)
        soundRow(title: "iOS System Default", value: NotificationSoundPreferences.systemDefaultValue, kind: nil)
        ForEach(PetSoundKind.allCases, id: \.rawValue) { kind in
            soundRow(title: kind.label, value: kind.rawValue, kind: kind)
        }
        Text("Sounds play only when iOS allows them: notification permission, the silent switch, Focus modes and your iOS sound settings always take priority.")
            .font(.caption).foregroundStyle(PCColor.secondaryText)
    }

    private func soundRow(title: String, value: String, kind: PetSoundKind?) -> some View {
        HStack {
            Button { defaultSoundSelection = value } label: {
                HStack {
                    Image(systemName: defaultSoundSelection == value ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(PCColor.freshGreen)
                    Text(title).foregroundStyle(PCColor.charcoal)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if let kind {
                Button { preview.play(kind) } label: {
                    Label("Play Preview", systemImage: "play.circle")
                        .font(.subheadline)
                }
                .accessibilityLabel("Play preview of \(title)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Settings destinations

/// Settings → Change Notification Sound.
struct NotificationSoundSettingsView: View {
    var body: some View {
        Form { SoundChoiceList() }
            .navigationTitle("Notification Sound")
    }
}

/// Settings → Change App Icon (the picker section is shared with the
/// previous Settings layout).
struct AppIconSettingsView: View {
    var body: some View {
        Form { AppIconPickerSection() }
            .navigationTitle("App Icon")
    }
}

/// Settings → Reminder Preferences: the per-category switches.
/// Turning a category off cancels its pending notifications at once;
/// turning it on rebuilds from current data — the same behaviour as
/// the switches that previously lived inline in Settings.
struct ReminderPreferencesView: View {
    @Query private var profiles: [UserProfile]
    @Query private var allPets: [Pet]
    @Query private var allSchedules: [MedicationSchedule]
    @Query private var allPolicies: [InsurancePolicy]
    @AppStorage("pc-notif-medications") private var notifMedications = true
    @AppStorage("pc-notif-appointments") private var notifAppointments = true
    @AppStorage("pc-notif-vaccinations") private var notifVaccinations = true
    @AppStorage("pc-notif-feeding") private var notifFeeding = true
    @AppStorage("pc-notif-insurance") private var notifInsurance = true
    @State private var permissionDenied = false

    var body: some View {
        Form {
            Section {
                Toggle("Medication reminders", isOn: $notifMedications)
                    .onChange(of: notifMedications) { _, on in categoryToggled(.medications, on: on) }
                Toggle("Appointment reminders", isOn: $notifAppointments)
                    .onChange(of: notifAppointments) { _, on in categoryToggled(.appointments, on: on) }
                Toggle("Vaccination reminders", isOn: $notifVaccinations)
                    .onChange(of: notifVaccinations) { _, on in categoryToggled(.vaccinations, on: on) }
                Toggle("Feeding reminders", isOn: $notifFeeding)
                    .onChange(of: notifFeeding) { _, on in categoryToggled(.feeding, on: on) }
                Toggle("Insurance renewal reminders", isOn: $notifInsurance)
                    .onChange(of: notifInsurance) { _, on in categoryToggled(.insurance, on: on) }
            } header: {
                Text("Reminder types")
            } footer: {
                Text("Reminders also need the main Reminders switch (Settings → Reminders) and iOS notification permission. A switch being on here never means iOS has granted permission.")
            }
            Section {
                Button("Check notification permission") {
                    Task {
                        let center = UNUserNotificationCenter.current()
                        let settings = await center.notificationSettings()
                        permissionDenied = !(settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
                    }
                }
                if permissionDenied {
                    Text("iOS notification permission is not granted for PetCare 360, so reminders cannot be delivered even though they are switched on in the app.")
                        .font(.caption).foregroundStyle(PCColor.errorRed)
                    Button("Open iOS Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("iOS permission")
            }
        }
        .navigationTitle("Reminder Preferences")
    }

    private func categoryToggled(_ category: ReminderCategory, on: Bool) {
        if on {
            NotificationService.shared.synchronizeReminders(
                pets: allPets, schedules: allSchedules, policies: allPolicies,
                remindersEnabled: profiles.first?.remindersEnabled ?? false)
        } else {
            NotificationService.shared.cancelPending(withPrefixes: category.pendingPrefixes)
        }
    }
}

// MARK: - Onboarding pages

/// Onboarding personalization, step 1: pick the Home Screen icon
/// from the owner's artwork. Applies immediately through the real
/// system API; Skip (in the onboarding chrome) leaves the default.
struct OnboardingIconPage: View {
    @State private var currentName: String? = nil
    @State private var loaded = false
    @State private var errorMessage = ""

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Personalize Your PetCare360")
                        .font(.title2.bold()).foregroundStyle(PCColor.charcoal)
                        .multilineTextAlignment(.center)
                    Text("Make PetCare360 feel more like your pet.")
                        .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
                Text("Choose your app icon")
                    .font(.headline).foregroundStyle(PCColor.charcoal)
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppIconOption.all) { option in
                        Button { select(option) } label: {
                            VStack(spacing: 6) {
                                Image(option.previewImageName)
                                    .resizable().scaledToFit()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(isSelected(option) ? PCColor.freshGreen : Color.clear, lineWidth: 3))
                                Text(option.label).font(.caption).foregroundStyle(PCColor.charcoal)
                                if isSelected(option) {
                                    Label("Selected", systemImage: "checkmark.circle.fill")
                                        .font(.caption2.bold()).foregroundStyle(PCColor.freshGreen)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(option.label) icon\(isSelected(option) ? ", selected" : "")")
                    }
                }
                Text("You can change this anytime in Settings. iOS shows its own confirmation when the icon changes.")
                    .font(.caption).foregroundStyle(PCColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            currentName = AppIconService.currentAlternateName
        }
        .alert("Couldn't change icon", isPresented: Binding(get: { !errorMessage.isEmpty }, set: { if !$0 { errorMessage = "" } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage) }
    }

    private func isSelected(_ option: AppIconOption) -> Bool {
        option.alternateName == currentName
    }

    private func select(_ option: AppIconOption) {
        guard !isSelected(option) else { return }
        AppIconService.setIcon(option) { error in
            if let error {
                errorMessage = error
            } else {
                currentName = AppIconService.currentAlternateName
            }
        }
    }
}

/// Onboarding personalization, step 2: pick the reminder sound
/// (with previews) and turn reminders on. Reminders are ON by
/// default for new users; iOS permission is asked for here, once.
/// If permission is denied, the page explains plainly and offers the
/// iOS Settings shortcut — it never pretends reminders will arrive,
/// and permission is never repeatedly requested.
struct OnboardingSoundPage: View {
    private enum PermissionState { case unknown, granted, denied }
    @State private var permission: PermissionState = .unknown

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Reminder Sounds")
                        .font(.title2.bold()).foregroundStyle(PCColor.charcoal)
                        .multilineTextAlignment(.center)
                    Text("Choose the sound your reminders will use. Tap Play Preview to hear each one.")
                        .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: 10) {
                    SoundChoiceList()
                }
                .pcCard()
                VStack(spacing: 10) {
                    Text("Reminders are on")
                        .font(.headline).foregroundStyle(PCColor.charcoal)
                    Text("Medication, feeding, vaccination and refill reminders are switched on for you. PetCare 360 needs iOS notification permission to deliver them.")
                        .font(.subheadline).foregroundStyle(PCColor.secondaryText)
                        .multilineTextAlignment(.center)
                    switch permission {
                    case .granted:
                        Label("Notifications allowed — you're all set.", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.bold()).foregroundStyle(PCColor.freshGreen)
                    case .denied:
                        Text("Notifications are turned off for PetCare 360 in iOS, so reminders can't be delivered yet. You can allow them in iOS Settings — the app won't keep asking.")
                            .font(.subheadline).foregroundStyle(PCColor.errorRed)
                            .multilineTextAlignment(.center)
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.subheadline.bold())
                    case .unknown:
                        PCPrimaryButton(title: "Allow Notifications") {
                            Task {
                                let granted = await NotificationService.shared.requestAuthorizationIfNeeded()
                                permission = granted ? .granted : .denied
                            }
                        }
                    }
                }
                .pcCard()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
        }
        .task {
            // Reflect an already-decided permission without asking again.
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional: permission = .granted
            case .denied: permission = .denied
            default: permission = .unknown
            }
        }
    }
}
