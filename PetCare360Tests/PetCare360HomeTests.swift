import XCTest
import SwiftData
@testable import PetCare360

/// Home schedule, notification-sound and app-icon tests
/// (2026-11-06 brief). WRITTEN, not executed — no Xcode here.
@MainActor
final class PetCare360HomeTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try PetCare360App.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        let base = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: offset, to: base)!
            .addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func petWithAppointment(_ context: ModelContext, apptDate: Date,
                                    completed: Bool = false, cancelled: Bool = false) throws -> Pet {
        let pet = Pet(name: "Bruno", species: .dog)
        context.insert(pet)
        let appt = VetAppointment(title: "Checkup", date: apptDate)
        appt.pet = pet
        appt.isCompleted = completed
        appt.isCancelled = cancelled
        context.insert(appt)
        try context.save()
        return pet
    }

    // MARK: Status buckets

    func testScheduleStatusBuckets() {
        let now = day(0, hour: 12)
        XCTAssertEqual(ScheduleStatus.bucket(for: day(-1), now: now), .overdue)
        XCTAssertEqual(ScheduleStatus.bucket(for: day(0, hour: 8), now: now), .dueToday)
        XCTAssertEqual(ScheduleStatus.bucket(for: day(1), now: now), .tomorrow)
        XCTAssertEqual(ScheduleStatus.bucket(for: day(4), now: now), .thisWeek)
        XCTAssertEqual(ScheduleStatus.bucket(for: day(20), now: now), .later)
    }

    // MARK: Appointments on Home — the reported bug

    func testFutureAppointmentAppearsInSchedule() throws {
        let context = try makeContext()
        let pet = try petWithAppointment(context, apptDate: day(3))
        let items = HomeSchedule.build(pets: [pet], tasks: [], policies: [], includeTodayActionable: false)
        XCTAssertEqual(items.filter { $0.kind == .appointment }.count, 1)
        XCTAssertEqual(items.first?.petName, "Bruno")
    }

    func testSameDayAppointmentEarlierTodayStillAppears() throws {
        // Regression: the old Home filter used date >= now, so a
        // 9am appointment vanished by 10am. Start-of-day semantics
        // keep it visible all day.
        let context = try makeContext()
        let pet = try petWithAppointment(context, apptDate: day(0, hour: 0).addingTimeInterval(60))
        let items = HomeSchedule.build(pets: [pet], tasks: [], policies: [], includeTodayActionable: false)
        XCTAssertEqual(items.filter { $0.kind == .appointment }.count, 1)
        XCTAssertEqual(items.first?.status, .dueToday)
    }

    func testCompletedCancelledAndPastAppointmentsExcluded() throws {
        let context = try makeContext()
        let pet = Pet(name: "Multi", species: .cat)
        context.insert(pet)
        for (date, completed, cancelled) in [(day(2), true, false), (day(2), false, true), (day(-2), false, false)] {
            let appt = VetAppointment(title: "Visit", date: date)
            appt.pet = pet
            appt.isCompleted = completed
            appt.isCancelled = cancelled
            context.insert(appt)
        }
        try context.save()
        let items = HomeSchedule.build(pets: [pet], tasks: [], policies: [], includeTodayActionable: false)
        XCTAssertTrue(items.filter { $0.kind == .appointment }.isEmpty)
    }

    func testScheduleIsChronologicalWithUniqueIDs() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno", species: .dog)
        context.insert(pet)
        for offset in [5, 1, 3] {
            let appt = VetAppointment(title: "Visit \(offset)", date: day(offset))
            appt.pet = pet
            context.insert(appt)
        }
        let vax = VaccinationRecord(vaccineName: "Rabies", date: day(-60))
        vax.expirationDate = day(-1)
        vax.pet = pet
        context.insert(vax)
        try context.save()
        let items = HomeSchedule.build(pets: [pet], tasks: [], policies: [], includeTodayActionable: false)
        XCTAssertEqual(items.map { $0.date }, items.map { $0.date }.sorted())
        XCTAssertEqual(Set(items.map { $0.id }).count, items.count, "No duplicate schedule items")
        XCTAssertEqual(items.first?.status, .overdue, "The overdue vaccination sorts first")
    }

    func testMedicationDosesTodayExcludedFromHomeCardButInFullSchedule() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno", species: .dog)
        context.insert(pet)
        let med = Medication(name: "Insulin", dosage: "2u")
        med.startDate = day(-10)
        med.doseMinutes = [480, 1200]
        med.pet = pet
        context.insert(med)
        try context.save()
        let home = HomeSchedule.build(pets: [pet], tasks: [], policies: [], includeTodayActionable: false)
        XCTAssertTrue(home.filter { $0.kind == .medication && Calendar.current.isDateInToday($0.date) }.isEmpty,
                      "Today's doses live in Today's Care on Home — not duplicated in the schedule card")
        let full = HomeSchedule.build(pets: [pet], tasks: [], policies: [], includeTodayActionable: true)
        XCTAssertEqual(full.filter { $0.kind == .medication && Calendar.current.isDateInToday($0.date) }.count, 2)
        XCTAssertEqual(full.filter { $0.kind == .medication && !Calendar.current.isDateInToday($0.date) }.count, 2,
                       "Tomorrow's doses appear in both")
    }

    func testBirthdayWithinHorizonAppears() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno", species: .dog)
        var comps = Calendar.current.dateComponents([.month, .day], from: Date())
        let dobYear = (Calendar.current.dateComponents([.year], from: Date()).year ?? 2026) - 4
        comps.year = dobYear
        // Birthday in 5 days.
        let future = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        var fc = Calendar.current.dateComponents([.month, .day], from: future)
        fc.year = dobYear
        pet.dateOfBirth = Calendar.current.date(from: fc)
        context.insert(pet)
        try context.save()
        let items = HomeSchedule.build(pets: [pet], tasks: [], policies: [], includeTodayActionable: false)
        let birthday = items.first { $0.kind == .birthday }
        XCTAssertNotNil(birthday)
        XCTAssertTrue(birthday?.detail.contains("Turns 5") ?? false)
    }

    func testShouldNotScheduleReminderForCancelledAppointment() throws {
        let context = try makeContext()
        let pet = try petWithAppointment(context, apptDate: day(2), cancelled: true)
        let appt = try XCTUnwrap(pet.appointments.first)
        XCTAssertFalse(NotificationService.shouldScheduleAppointmentReminder(appt))
    }

    func testCancelledAppointmentSurvivesBackupRoundTrip() throws {
        let context = try makeContext()
        let pet = try petWithAppointment(context, apptDate: day(2), cancelled: true)
        let backup = BackupService.makeFullBackup(
            pets: [pet], households: [], careTasks: [], careHandoffs: [],
            feedingLogs: [], insurancePolicies: [], emergencyProfiles: [],
            savedBrands: [], recallAlerts: [], medicationSchedules: [])
        let dto = try XCTUnwrap(backup.pets.first?.appointments.first)
        XCTAssertEqual(dto.isCancelled, true)
        // A legacy DTO (field absent) decodes as nil = not cancelled.
        let legacy = BackupService.AppointmentFull(
            id: dto.id, title: dto.title, clinic: dto.clinic, vetName: dto.vetName,
            date: dto.date, notes: dto.notes, questions: dto.questions,
            followUpDate: dto.followUpDate, isCompleted: dto.isCompleted, isCancelled: nil)
        let data = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(BackupService.AppointmentFull.self, from: data)
        XCTAssertNil(decoded.isCancelled)
    }

    // MARK: Notification sounds

    func testSoundKindMappingForSpecies() {
        XCTAssertEqual(PetSoundKind.forSpecies(.dog), .dog)
        XCTAssertEqual(PetSoundKind.forSpecies(.cat), .cat)
        XCTAssertEqual(PetSoundKind.forSpecies(.bird), .bird)
        XCTAssertEqual(PetSoundKind.forSpecies(.rabbit), .rabbit)
        XCTAssertNil(PetSoundKind.forSpecies(.other))
    }

    func testSoundResolutionHonoursPreferences() {
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: .dog, animalEnabled: true, defaultSelection: "chime"), "petcare-dog.wav")
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: .dog, animalEnabled: false, defaultSelection: "chime"), "petcare-chime.wav",
            "Animal sounds off -> the chosen default applies to every pet")
        XCTAssertEqual(NotificationSoundPreferences.resolvedFileName(
            species: .other, animalEnabled: true, defaultSelection: "cat"), "petcare-cat.wav",
            "Species without a dedicated sound falls back to the default")
        XCTAssertNil(NotificationSoundPreferences.resolvedFileName(
            species: .cat, animalEnabled: false, defaultSelection: NotificationSoundPreferences.systemDefaultValue),
            "System default selection means iOS plays its own sound")
    }

    func testAllSoundFilesAreBundled() {
        for kind in PetSoundKind.allCases {
            XCTAssertNotNil(Bundle.main.url(forResource: kind.fileName, withExtension: nil),
                            "\(kind.fileName) must be in the app bundle root for UNNotificationSound")
        }
    }

    func testReminderCategoryKeysAndPrefixes() {
        XCTAssertEqual(Set(ReminderCategory.allCases.map { $0.defaultsKey }).count, 5)
        for category in ReminderCategory.allCases {
            XCTAssertFalse(category.pendingPrefixes.isEmpty)
        }
    }

    // MARK: App icons

    func testAppIconOptionsAreTheFixedBundledSet() {
        XCTAssertEqual(AppIconOption.all.count, 8)
        XCTAssertNil(AppIconOption.all.first?.alternateName, "First option is the primary Dog and Cat icon")
        XCTAssertEqual(AppIconOption.all.first?.label, "Dog and Cat")
        let alternates = AppIconOption.all.compactMap { $0.alternateName }
        XCTAssertEqual(Set(alternates).count, 7)
        XCTAssertEqual(Set(alternates), ["AppIconDog", "AppIconCat", "AppIconBird", "AppIconRabbit",
                                         "AppIconReptile", "AppIconHorse", "AppIconOther"])
        XCTAssertEqual(Set(AppIconOption.all.map { $0.previewImageName }).count, 8)
    }
}
