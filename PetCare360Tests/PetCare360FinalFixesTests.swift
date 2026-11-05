import XCTest
@testable import PetCare360

/// Pre-release fix tests (1.2.1). WRITTEN, not executed — no Xcode in the
/// build environment. See docs/TEST_REPORT.md.
final class PetCare360FinalFixesTests: XCTestCase {

    // MARK: Legal configuration (brief section 1 + 11)

    func testLegalURLsUseHTTPSAndTheLegalHost() {
        for url in [AppConfig.privacyPolicyURL, AppConfig.termsOfUseURL, AppConfig.websiteURL] {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "salmanalihere.github.io")
        }
        XCTAssertTrue(AppConfig.privacyPolicyURL.path.hasSuffix("privacy.html"))
        XCTAssertTrue(AppConfig.termsOfUseURL.path.hasSuffix("terms.html"))
    }

    func testNoPlaceholderLegalValuesRemain() {
        XCTAssertFalse(AppConfig.privacyPolicyURL.absoluteString.contains("example.com"))
        XCTAssertFalse(AppConfig.termsOfUseURL.absoluteString.contains("example.com"))
        XCTAssertFalse(AppConfig.supportEmail.contains("example.com"))
    }

    func testSupportEmailAndMailto() {
        XCTAssertEqual(AppConfig.supportEmail, "Salmanali929929@gmail.com")
        XCTAssertEqual(AppConfig.supportMailtoURL.scheme, "mailto")
        XCTAssertTrue(AppConfig.supportMailtoURL.absoluteString.contains("Salmanali929929@gmail.com"))
    }

    func testICloudContainerMatchesBundleID() {
        XCTAssertEqual(AppConfig.iCloudContainerID, "iCloud.\(AppConfig.bundleID)")
    }

    // MARK: Medication scheduling (brief section 5)

    func testSlotsStopAtCourseEndDate() {
        let med = Medication(name: "Course", dosage: "5mg")
        let cal = Calendar.current
        med.startDate = cal.date(byAdding: .day, value: -10, to: Date())!
        med.endDate = cal.date(byAdding: .day, value: 1, to: Date())
        med.doseMinutes = [480]
        let lastDay = med.endDate!
        XCTAssertEqual(MedicationService.slots(for: med, on: lastDay).count, 1, "The end date itself is included")
        let after = cal.date(byAdding: .day, value: 1, to: lastDay)!
        XCTAssertTrue(MedicationService.slots(for: med, on: after).isEmpty, "No doses — and therefore no reminders — after the course ends")
    }

    func testSlotsDoNotStartBeforeCourseStart() {
        let med = Medication(name: "Future", dosage: "5mg")
        let cal = Calendar.current
        med.startDate = cal.date(byAdding: .day, value: 3, to: Date())!
        med.doseMinutes = [480]
        XCTAssertTrue(MedicationService.slots(for: med, on: Date()).isEmpty)
        XCTAssertEqual(MedicationService.slots(for: med, on: med.startDate).count, 1)
    }

    // MARK: Backup media preservation (brief section 4)

    func testBackupPreservesPetPhotoAndDocumentOriginal() throws {
        let pet = Pet(name: "Buddy")
        pet.photoData = Data([0xFF, 0xD8, 0xFF, 0x01])
        let doc = MedicalDocument(title: "Rabies certificate")
        doc.originalData = Data([0x01, 0x02, 0x03])
        doc.pet = pet
        pet.documents.append(doc)
        let backup = BackupService.makeFullBackup(
            pets: [pet], households: [], careTasks: [], careHandoffs: [],
            feedingLogs: [], insurancePolicies: [], emergencyProfiles: [],
            savedBrands: [], recallAlerts: [], medicationSchedules: [])
        let decoded = try BackupService.decodeFull(data: BackupService.encode(backup))
        XCTAssertEqual(decoded.pets.first?.photoData, Data([0xFF, 0xD8, 0xFF, 0x01]),
                       "Pet photos must not be silently lost in a backup")
        XCTAssertEqual(decoded.pets.first?.documents.first?.originalData, Data([0x01, 0x02, 0x03]),
                       "Scanned document originals must not be silently lost in a backup")
    }

    func testBackupRejectsCorruptFile() {
        XCTAssertThrowsError(try BackupService.decodeAny(data: Data("not json".utf8)))
        XCTAssertThrowsError(try BackupService.decodeAny(data: Data("{}".utf8)))
    }
}
