import XCTest
@testable import PetCare360

/// Trial + personalization tests (owner brief 2026-11-07).
/// The trial is exercised through an in-memory date store and a
/// controllable clock, so no test touches the real Keychain and the
/// 7-day boundary is checked exactly. These tests are WRITTEN here;
/// like every PetCare 360 test they can only RUN under Xcode on a
/// Mac — this build environment has no Xcode.
final class PetCare360TrialTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeManager(store: InMemoryTrialDateStore, now: Date) -> TrialManager {
        TrialManager(store: store, now: { now })
    }

    func testTrialNotStartedBeforeBegin() {
        let store = InMemoryTrialDateStore()
        let trial = makeManager(store: store, now: t0)
        XCTAssertEqual(trial.state, .notStarted)
        XCTAssertFalse(trial.isActive)
        XCTAssertEqual(trial.daysRemaining, 0)
    }

    func testTrialStartsOnFirstBeginWithSevenDays() {
        let store = InMemoryTrialDateStore()
        let trial = makeManager(store: store, now: t0)
        trial.beginIfNeeded()
        XCTAssertTrue(trial.isActive)
        XCTAssertEqual(trial.daysRemaining, 7)
        XCTAssertEqual(trial.endsAt, t0.addingTimeInterval(TrialManager.duration))
        XCTAssertEqual(store.loadStartDate(), t0)
    }

    func testTrialCountsDownAndExpiresAtExactlySevenDays() {
        let store = InMemoryTrialDateStore()
        makeManager(store: store, now: t0).beginIfNeeded()

        let daySix = makeManager(store: store, now: t0.addingTimeInterval(6 * 86400))
        XCTAssertTrue(daySix.isActive)
        XCTAssertEqual(daySix.daysRemaining, 1)

        let lastSecond = makeManager(store: store, now: t0.addingTimeInterval(TrialManager.duration - 1))
        XCTAssertTrue(lastSecond.isActive)

        let daySeven = makeManager(store: store, now: t0.addingTimeInterval(TrialManager.duration))
        XCTAssertEqual(daySeven.state, .expired)
        XCTAssertFalse(daySeven.isActive)
        XCTAssertEqual(daySeven.daysRemaining, 0)
    }

    func testTrialDoesNotResetOnRelaunchOrReinstall() {
        // A new TrialManager over the same store simulates a relaunch
        // AND a delete-and-reinstall: the Keychain-backed store keeps
        // the original start date, so beginIfNeeded must not move it.
        let store = InMemoryTrialDateStore()
        makeManager(store: store, now: t0).beginIfNeeded()
        let later = makeManager(store: store, now: t0.addingTimeInterval(3 * 86400))
        later.beginIfNeeded()
        XCTAssertEqual(store.loadStartDate(), t0, "Start date must never be overwritten")
        XCTAssertEqual(later.daysRemaining, 4)
    }

    func testExpiredTrialStaysExpired() {
        let store = InMemoryTrialDateStore()
        makeManager(store: store, now: t0).beginIfNeeded()
        let after = makeManager(store: store, now: t0.addingTimeInterval(30 * 86400))
        after.beginIfNeeded()
        XCTAssertEqual(after.state, .expired)
    }

    func testAccessCombinesPurchaseAndTrial() {
        XCTAssertTrue(EntitlementPolicy.hasAccess(isPremium: true, trialActive: false))
        XCTAssertTrue(EntitlementPolicy.hasAccess(isPremium: false, trialActive: true))
        XCTAssertTrue(EntitlementPolicy.hasAccess(isPremium: true, trialActive: true))
        XCTAssertFalse(EntitlementPolicy.hasAccess(isPremium: false, trialActive: false),
                       "No purchase and no active trial means free plan — never a silent unlock")
    }

    // MARK: Personalization integrity

    func testIconOptionsMatchBundledAssets() {
        // The onboarding grid and the Settings picker both read this
        // one list; every alternate name must be a bundled appiconset
        // or setAlternateIconName would fail on device.
        XCTAssertEqual(AppIconOption.all.count, 8)
        XCTAssertNil(AppIconOption.all.first { $0.id == "dogcat" }?.alternateName,
                     "Default Dog & Cat is the primary icon")
        for option in AppIconOption.all {
            XCTAssertFalse(option.previewImageName.isEmpty)
        }
        XCTAssertEqual(Set(AppIconOption.all.compactMap { $0.alternateName }),
                       ["AppIconDog", "AppIconCat", "AppIconBird", "AppIconRabbit",
                        "AppIconReptile", "AppIconHorse", "AppIconOther"])
    }

    func testOwnerSoundFilesAndMapping() {
        // Only the owner's supplied recordings plus the app chime.
        XCTAssertEqual(Set(PetSoundKind.allCases.map { $0.fileName }),
                       ["petcare-dog.wav", "petcare-cat.wav", "petcare-bird.wav",
                        "petcare-rabbit.wav", "petcare-horse.wav", "petcare-chime.wav"])
        XCTAssertNil(PetSoundKind(rawValue: "reptile"), "There is no reptile sound kind any more")
        // A stale stored selection of "reptile" (from an older build)
        // falls back to the chime rather than a missing file.
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: nil, animalEnabled: false, defaultSelection: "reptile"), "petcare-chime.wav")
    }

    func testNewProfilesStartWithRemindersOn() {
        // Model default only: profiles created from now on start with
        // reminders enabled (owner brief 2026-11-07).
        XCTAssertTrue(UserProfile().remindersEnabled)
    }
}
