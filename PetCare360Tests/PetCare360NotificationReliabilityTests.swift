import XCTest
import UserNotifications
@testable import PetCare360

/// Notification reliability fixes (2026-11-09): the defaults and
/// presentation configuration behind the delivery fixes. These
/// tests deliberately cover only pure, deterministic logic — the
/// same discipline as the rest of the suite. Actual delivery by
/// iOS (banner timing, sound playback, terminated-app firing) is
/// NOT provable by unit tests and is covered by the manual iPhone
/// checklist in the fix report instead.
final class PetCare360NotificationReliabilityTests: XCTestCase {

    // MARK: Notifications ON by default

    /// A newly created profile must start with reminders ON (the
    /// model default). Read sites across the app were aligned to
    /// the same default for the no-profile case in this fix.
    func testUserProfileRemindersEnabledByDefault() {
        XCTAssertTrue(UserProfile().remindersEnabled,
                      "New profiles must default to reminders ON")
    }

    /// Every reminder category defaults to enabled when the user
    /// has never stored a preference. Saves and restores any
    /// pre-existing values so the suite never disturbs app state.
    func testReminderCategoriesEnabledByDefault() {
        let defaults = UserDefaults.standard
        let keys = ReminderCategory.allCases.map { $0.defaultsKey }
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys { defaults.removeObject(forKey: key) }
        for category in ReminderCategory.allCases {
            XCTAssertTrue(category.isEnabled, "\(category.rawValue) must default to enabled")
        }
    }

    /// Sound preferences default to animal sounds ON and the
    /// PetCare chime as the default sound (absent keys).
    func testSoundPreferencesDefaults() {
        let defaults = UserDefaults.standard
        let animalKey = NotificationSoundPreferences.animalEnabledKey
        let kindKey = NotificationSoundPreferences.defaultKindKey
        let savedAnimal = defaults.object(forKey: animalKey)
        let savedKind = defaults.object(forKey: kindKey)
        defer {
            if let savedAnimal { defaults.set(savedAnimal, forKey: animalKey) } else { defaults.removeObject(forKey: animalKey) }
            if let savedKind { defaults.set(savedKind, forKey: kindKey) } else { defaults.removeObject(forKey: kindKey) }
        }
        defaults.removeObject(forKey: animalKey)
        defaults.removeObject(forKey: kindKey)
        XCTAssertTrue(NotificationSoundPreferences.animalSoundsEnabled,
                      "Animal-specific sounds must default to ON")
        XCTAssertEqual(NotificationSoundPreferences.defaultSelection, PetSoundKind.chime.rawValue,
                       "The default sound selection must default to the PetCare chime")
    }

    // MARK: Foreground presentation

    /// The foreground presenter must request the full presentation
    /// set — banner, list, sound, badge — so a reminder that fires
    /// while the app is open behaves exactly like a background one
    /// (before the fix there was no delegate at all and foreground
    /// reminders were silently swallowed by iOS).
    func testForegroundPresentationOptions() {
        XCTAssertEqual(NotificationPresenter.foregroundOptions,
                       [.banner, .list, .sound, .badge])
    }

    // MARK: Sound resolution — the no-species path

    /// Reminders not tied to a pet species (species == nil) use
    /// the user's default sound selection; the system-default
    /// selection yields nil, which the scheduling funnel maps to
    /// UNNotificationSound.default.
    func testSoundResolutionWithoutSpecies() {
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: nil, animalEnabled: true, defaultSelection: "dog"), "petcare-dog.wav")
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: nil, animalEnabled: false, defaultSelection: "chime"), "petcare-chime.wav")
        XCTAssertNil(NotificationSoundPreferences.resolvedFileName(
            species: nil, animalEnabled: true, defaultSelection: NotificationSoundPreferences.systemDefaultValue))
    }
}
