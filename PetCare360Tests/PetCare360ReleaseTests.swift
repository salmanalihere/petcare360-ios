import XCTest
import SwiftData
@testable import PetCare360

/// Release-correction tests (2026-11-06): bundle identity, CloudKit
/// configuration, and the two new species. WRITTEN, not executed.
@MainActor
final class PetCare360ReleaseTests: XCTestCase {

    // MARK: Identity (owner-confirmed registration)

    func testBundleIdentifierIsTheRegisteredApp() {
        XCTAssertEqual(AppConfig.bundleID, "com.xenon-media.petcare360")
    }

    func testCloudKitConfigurationRestored() {
        XCTAssertTrue(AppConfig.cloudKitSyncEnabled)
        XCTAssertEqual(AppConfig.iCloudContainerID, "iCloud.com.xenon-media.petcare360")
    }

    func testStoreKitProductIDsUnchanged() {
        // Product IDs are App Store Connect identifiers of their
        // own; the bundle-ID correction does not rename them.
        XCTAssertEqual(PremiumProduct.monthly, "com.petcare360.premium.monthly")
        XCTAssertEqual(PremiumProduct.yearly, "com.petcare360.premium.yearly")
    }

    // MARK: New species

    func testSpeciesSetIncludesReptilesAndHorses() {
        XCTAssertEqual(PetSpecies.allCases.count, 7)
        XCTAssertTrue(PetSpecies.allCases.contains(.reptile))
        XCTAssertTrue(PetSpecies.allCases.contains(.horse))
        XCTAssertEqual(PetSpecies.reptile.label, "Reptiles")
        XCTAssertEqual(PetSpecies.horse.label, "Horses")
        XCTAssertFalse(PetSpecies.reptile.icon.isEmpty)
        XCTAssertFalse(PetSpecies.horse.icon.isEmpty)
    }

    func testExistingSpeciesRawValuesUnchanged() {
        // speciesRaw is persisted in the database, backups and
        // CloudKit — renaming a raw value would orphan records.
        XCTAssertEqual(PetSpecies.dog.rawValue, "dog")
        XCTAssertEqual(PetSpecies.cat.rawValue, "cat")
        XCTAssertEqual(PetSpecies.bird.rawValue, "bird")
        XCTAssertEqual(PetSpecies.rabbit.rawValue, "rabbit")
        XCTAssertEqual(PetSpecies.other.rawValue, "other")
        XCTAssertEqual(PetSpecies(rawValue: "dog"), .dog)
        XCTAssertEqual(PetSpecies(rawValue: "reptile"), .reptile)
        XCTAssertEqual(PetSpecies(rawValue: "horse"), .horse)
    }

    func testNewSpeciesSelectTheirSounds() {
        // Reptiles have NO bundled sound (owner instruction
        // 2026-11-07): no kind, and resolution returns nil — the iOS
        // system default — ALWAYS (see the dedicated matrix test).
        XCTAssertNil(PetSoundKind.forSpecies(.reptile))
        XCTAssertEqual(PetSoundKind.forSpecies(.horse), .horse)
        XCTAssertNil(NotificationSoundPreferences.resolvedFileName(
            species: .reptile, animalEnabled: true, defaultSelection: "chime"))
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: .horse, animalEnabled: true, defaultSelection: "chime"), "petcare-horse.wav")
    }

    func testReptilesAlwaysUseSystemDefaultSound() {
        // Owner requirement (2026-11-07 review): a reptile reminder
        // uses the iOS system default sound (nil) regardless of the
        // animal-sounds toggle and regardless of the selected
        // default sound. Every combination must return nil.
        for animalEnabled in [true, false] {
            for selection in ["chime", "cat", "dog", NotificationSoundPreferences.systemDefaultValue] {
                XCTAssertNil(NotificationSoundPreferences.resolvedFileName(
                    species: .reptile, animalEnabled: animalEnabled, defaultSelection: selection),
                    "Reptile must resolve to the iOS default (animalEnabled=\(animalEnabled), selection=\(selection))")
            }
        }
        // Control cases: other species still follow the normal
        // preference rules, unchanged by the reptile rule.
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: .dog, animalEnabled: true, defaultSelection: "chime"), "petcare-dog.wav")
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: .dog, animalEnabled: false, defaultSelection: "chime"), "petcare-chime.wav",
            "Animal sounds off -> the chosen default applies to a dog")
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: .other, animalEnabled: true, defaultSelection: "cat"), "petcare-cat.wav",
            "Species without a dedicated sound falls back to the default")
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: .horse, animalEnabled: false, defaultSelection: "cat"), "petcare-cat.wav")
        XCTAssertNil(NotificationSoundPreferences.resolvedFileName(
            species: nil, animalEnabled: true, defaultSelection: NotificationSoundPreferences.systemDefaultValue),
            "No species + system default selection -> iOS default")
    }

    func testNewSpeciesSurviveBackupRoundTrip() throws {
        let container = try PetCare360App.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = ModelContext(container)
        let gecko = Pet(name: "Gex", species: .reptile)
        let mare = Pet(name: "Willow", species: .horse)
        context.insert(gecko)
        context.insert(mare)
        try context.save()
        let backup = BackupService.makeFullBackup(
            pets: [gecko, mare], households: [], careTasks: [], careHandoffs: [],
            feedingLogs: [], insurancePolicies: [], emergencyProfiles: [],
            savedBrands: [], recallAlerts: [], medicationSchedules: [])
        let raws = Set(backup.pets.map { $0.speciesRaw })
        XCTAssertEqual(raws, ["reptile", "horse"])
        let data = try BackupService.encode(backup)
        let decoded = try BackupService.decodeFull(data: data)
        XCTAssertEqual(Set(decoded.pets.map { PetSpecies(rawValue: $0.speciesRaw) ?? .other }), [.reptile, .horse])
    }
}
