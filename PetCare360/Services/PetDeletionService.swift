import Foundation
import SwiftData

/// Complete pet deletion (v1.2.4 correction).
///
/// Deleting a Pet cascades its SwiftData-relationship children, but
/// several models are linked only by `petID` and were previously left
/// behind: care tasks, feeding logs, insurance policies (and claims),
/// emergency profiles, and medication schedule preference records.
/// Their pending notifications were also left behind (insurance renewal
/// reminders). This service removes ALL of it, so the deletion
/// confirmation text is actually true.
enum PetDeletionService {

    /// Deletes the pet and every associated record, and cancels every
    /// pending notification that belongs to the pet. Returns the number
    /// of standalone (petID-linked) records removed, for reporting/tests.
    @MainActor
    @discardableResult
    static func deleteAllData(for pet: Pet, in context: ModelContext) throws -> Int {
        let petID = pet.id
        let medicationIDs = pet.medications.map { $0.id }
        var removed = 0

        // Capture every notification identifier as a VALUE first; the
        // cancellations themselves happen only after the deletion has
        // been saved (v1.2.6 ordering), so a failed deletion leaves the
        // pet's reminders untouched.
        var oneOffIDs = pet.vaccinations.map { "vax-\($0.id.uuidString)" }
            + pet.appointments.map { "appt-\($0.id.uuidString)" }
            + pet.foodSchedules.map { "feed-\($0.id.uuidString)" }
        let policies = try context.fetch(FetchDescriptor<InsurancePolicy>(
            predicate: #Predicate { $0.petID == petID }))
        oneOffIDs += policies.map { "ins-\($0.id.uuidString)" }

        // Standalone records linked only by petID / petName / medicationID.
        for task in try context.fetch(FetchDescriptor<CareTask>(
            predicate: #Predicate { $0.petID == petID })) {
            context.delete(task); removed += 1
        }
        for log in try context.fetch(FetchDescriptor<FeedingLog>(
            predicate: #Predicate { $0.petID == petID })) {
            context.delete(log); removed += 1
        }
        for policy in policies {
            context.delete(policy); removed += 1   // claims cascade from the policy
        }
        for profile in try context.fetch(FetchDescriptor<EmergencyProfile>(
            predicate: #Predicate { $0.petID == petID })) {
            context.delete(profile); removed += 1
        }
        // Handoffs are deleted ONLY when their petID matches — legacy
        // handoffs with no petID are preserved, never name-matched
        // (two pets can share a name).
        for handoff in try context.fetch(FetchDescriptor<CareHandoff>()) where handoff.petID == petID {
            context.delete(handoff); removed += 1
        }
        for schedule in try context.fetch(FetchDescriptor<MedicationSchedule>()) where medicationIDs.contains(schedule.medicationID) {
            context.delete(schedule); removed += 1
        }
        context.delete(pet)   // relationship children cascade from here
        try context.save()
        // Deletion is durably saved — now cancel the pet's reminders.
        for medicationID in medicationIDs {
            NotificationService.shared.cancelMedicationReminders(medicationID: medicationID)
        }
        NotificationService.shared.cancel(ids: oneOffIDs)
        return removed
    }

    /// Cancels every pending notification belonging to a pet WITHOUT
    /// deleting anything. Used when a pet is archived (v1.2.4): an
    /// archived pet should not keep reminding. Restoring the pet lets
    /// the normal foreground/settings rebuild passes re-schedule.
    @MainActor
    static func cancelAllReminders(for pet: Pet, in context: ModelContext) {
        for medication in pet.medications {
            NotificationService.shared.cancelMedicationReminders(medicationID: medication.id)
        }
        var ids = pet.vaccinations.map { "vax-\($0.id.uuidString)" }
            + pet.appointments.map { "appt-\($0.id.uuidString)" }
            + pet.foodSchedules.map { "feed-\($0.id.uuidString)" }
        let petID = pet.id
        if let policies = try? context.fetch(FetchDescriptor<InsurancePolicy>(
            predicate: #Predicate { $0.petID == petID })) {
            ids += policies.map { "ins-\($0.id.uuidString)" }
        }
        NotificationService.shared.cancel(ids: ids)
    }
}

/// Shared archive / restore used by EVERY surface (pet list, pet
/// detail) so no Restore button can bypass the free-plan limit
/// (v1.2.5). Both operations save with real error handling: on failure
/// the context is rolled back and the caller is told, so the UI can
/// keep its state and show an error instead of claiming success.
enum PetArchiveService {
    enum Outcome: Equatable { case done, limitReached, saveFailed }

    @MainActor
    static func restore(pet: Pet, activeCount: Int, isPremium: Bool, in context: ModelContext) -> Outcome {
        guard EntitlementPolicy.canAddPet(currentCount: activeCount, isPremium: isPremium) else {
            return .limitReached
        }
        pet.isArchived = false
        do {
            try context.save()
        } catch {
            context.rollback()
            return .saveFailed
        }
        // Rebuild eligible reminders for the restored pet through the
        // centralized serialized synchronization.
        if let pets = try? context.fetch(FetchDescriptor<Pet>()),
           let schedules = try? context.fetch(FetchDescriptor<MedicationSchedule>()),
           let policies = try? context.fetch(FetchDescriptor<InsurancePolicy>()),
           let profiles = try? context.fetch(FetchDescriptor<UserProfile>()) {
            NotificationService.shared.synchronizeReminders(
                pets: pets, schedules: schedules, policies: policies,
                remindersEnabled: profiles.first?.remindersEnabled ?? false)
        }
        return .done
    }

    @MainActor
    static func archive(pet: Pet, in context: ModelContext) -> Outcome {
        pet.isArchived = true
        do {
            try context.save()
        } catch {
            context.rollback()
            return .saveFailed
        }
        PetDeletionService.cancelAllReminders(for: pet, in: context)
        return .done
    }
}
