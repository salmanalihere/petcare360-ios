import Foundation
import AVFoundation

/// Bundled notification sounds (2026-11-06). Every file is an
/// ORIGINAL synthesized tone created for PetCare 360 — no recordings
/// and no third-party audio — shipped in the app bundle root, which
/// is where iOS looks for custom local-notification sounds. Files
/// are short WAV (a format iOS supports for notification sounds,
/// well under the 30-second system limit).
enum PetSoundKind: String, CaseIterable {
    case dog, cat, bird, rabbit, reptile, horse, chime

    var fileName: String { "petcare-\(rawValue).wav" }

    var label: String {
        switch self {
        case .dog: return "Dog — friendly woof"
        case .cat: return "Cat — gentle meow"
        case .bird: return "Bird — soft chirps"
        case .rabbit: return "Rabbit — soft thump"
        case .reptile: return "Reptile — calm nature chime"
        case .horse: return "Horse — soft whinny"
        case .chime: return "PetCare 360 chime (default)"
        }
    }

    /// The sound kind for a pet species, or nil when the species has
    /// no dedicated sound (the user's default then applies).
    static func forSpecies(_ species: PetSpecies) -> PetSoundKind? {
        switch species {
        case .dog: return .dog
        case .cat: return .cat
        case .bird: return .bird
        case .rabbit: return .rabbit
        case .reptile: return .reptile
        case .horse: return .horse
        case .other: return nil
        }
    }
}

/// Reminder categories the user can switch off individually
/// (Settings → Notification Preferences). All default ON; the gates
/// are read centrally by NotificationService, so editor saves and
/// background rebuilds honour them identically.
enum ReminderCategory: String, CaseIterable {
    case medications, appointments, vaccinations, feeding, insurance

    var defaultsKey: String { "pc-notif-\(rawValue)" }
    var label: String {
        switch self {
        case .medications: return "Medication reminders"
        case .appointments: return "Appointment reminders"
        case .vaccinations: return "Vaccination reminders"
        case .feeding: return "Feeding reminders"
        case .insurance: return "Insurance renewal reminders"
        }
    }
    /// Pending-notification id prefixes (after the pc360- namespace)
    /// belonging to this category, used to cancel promptly when the
    /// user switches the category off.
    var pendingPrefixes: [String] {
        switch self {
        case .medications: return ["med-", "refill-"]
        case .appointments: return ["appt-"]
        case .vaccinations: return ["vax-"]
        case .feeding: return ["feed-"]
        case .insurance: return ["ins-"]
        }
    }
    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }
}

/// Sound preference storage + resolution. Keys are shared verbatim
/// with the Settings @AppStorage bindings.
enum NotificationSoundPreferences {
    static let animalEnabledKey = "pc-sound-animal-enabled"
    static let defaultKindKey = "pc-sound-default-kind"
    /// Picker value meaning "use the iOS system default sound".
    static let systemDefaultValue = "system"

    static var animalSoundsEnabled: Bool {
        UserDefaults.standard.object(forKey: animalEnabledKey) as? Bool ?? true
    }
    static var defaultSelection: String {
        UserDefaults.standard.string(forKey: defaultKindKey) ?? PetSoundKind.chime.rawValue
    }

    /// The bundled sound file a notification for `species` should
    /// use, or nil for the iOS system default sound. Pure given the
    /// two preference values, so it is unit-testable.
    static func resolvedFileName(species: PetSpecies?, animalEnabled: Bool, defaultSelection: String) -> String? {
        if animalEnabled, let species, let kind = PetSoundKind.forSpecies(species) {
            return kind.fileName
        }
        if defaultSelection == systemDefaultValue { return nil }
        return (PetSoundKind(rawValue: defaultSelection) ?? .chime).fileName
    }

    static func resolvedFileName(species: PetSpecies?) -> String? {
        resolvedFileName(species: species, animalEnabled: animalSoundsEnabled, defaultSelection: defaultSelection)
    }
}

/// In-app preview playback for the Settings sound list. This is a
/// convenience preview ONLY — actual reminder sounds are played by
/// iOS itself from the bundled files via UNNotificationSound.
final class SoundPreviewPlayer: ObservableObject {
    private var player: AVAudioPlayer?

    func play(_ kind: PetSoundKind) {
        guard let url = Bundle.main.url(forResource: kind.fileName, withExtension: nil) else { return }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
