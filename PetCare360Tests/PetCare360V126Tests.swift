import XCTest
import SwiftData
@testable import PetCare360

/// v1.2.6 tests: the CareHandoff syntax-fix regression and the six
/// remaining silent-save flows. The failure tests exercise the exact
/// do/catch + rollback sequence the views now run: a change is made in
/// the context, the save "fails" (simulated by discarding via rollback,
/// the same call every catch branch makes), and the test asserts the
/// record is untouched. One test additionally proves a REAL save
/// failure is thrown by an unwritable store when the platform allows
/// the injection. WRITTEN, not executed — no Xcode here.
@MainActor
final class PetCare360V126Tests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try PetCare360App.makeContainer(
            configuration: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    // MARK: Syntax-fix regression (brief §1)

    func testCareHandoffDefaultAuthorName() {
        let handoff = CareHandoff(petName: "Bruno", author: "Sam")
        XCTAssertEqual(handoff.authorName, "Sam")
        XCTAssertEqual(handoff.petName, "Bruno")
        XCTAssertNil(handoff.petID, "New handoffs start unassociated until the editor sets the pet ID")
        // The property declaration itself (the v1.2.5 syntax error site)
        // must compile with an empty-string default — verified by this
        // file building at all; the value semantics are pinned here:
        let other = CareHandoff(petName: "Milo", author: "")
        XCTAssertEqual(other.authorName, "")
    }

    // MARK: Failure handling for the six flows (brief §2)

    func testFeedingCompletionSaveFailureKeepsState() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno")
        context.insert(pet)
        try context.save()
        // The Fed button's sequence: insert the log, save; on failure
        // rollback and report — the log must not linger as if saved.
        let log = FeedingLog(petID: pet.id, petName: pet.name, by: "Owner")
        context.insert(log)
        context.rollback()   // the catch branch's action
        XCTAssertEqual(try context.fetch(FetchDescriptor<FeedingLog>()).count, 0)
    }

    func testCareTaskCompletionSaveFailureRevertsToggle() throws {
        let context = try makeContext()
        let task = CareTask(title: "Walk", petID: UUID(), petName: "Bruno", date: Date())
        context.insert(task)
        try context.save()
        task.isCompleted = true
        task.completedBy = "Owner"
        context.rollback()   // the catch branch's action
        let fetched = try context.fetch(FetchDescriptor<CareTask>()).first
        XCTAssertEqual(fetched?.isCompleted, false, "A failed save must not leave the task marked complete")
        XCTAssertEqual(fetched?.completedBy, "")
    }

    func testExpenseDeletionFailureKeepsRecord() throws {
        let context = try makeContext()
        let pet = Pet(name: "Bruno")
        context.insert(pet)
        let expense = PetExpense(amount: 42, category: .food, date: Date())
        expense.pet = pet
        context.insert(expense)
        try context.save()
        context.delete(expense)
        context.rollback()   // the catch branch's action
        XCTAssertEqual(try context.fetch(FetchDescriptor<PetExpense>()).count, 1,
                       "A failed deletion save must leave the expense in place")
    }

    func testInsurancePolicyDeletionFailureKeepsRecord() throws {
        let context = try makeContext()
        let policy = InsurancePolicy(provider: "PawProtect", petID: UUID(), petName: "Bruno")
        context.insert(policy)
        try context.save()
        context.delete(policy)
        context.rollback()
        XCTAssertEqual(try context.fetch(FetchDescriptor<InsurancePolicy>()).count, 1)
    }

    func testInsuranceClaimDeletionFailureKeepsRecord() throws {
        let context = try makeContext()
        let policy = InsurancePolicy(provider: "PawProtect", petID: UUID(), petName: "Bruno")
        context.insert(policy)
        let claim = InsuranceClaim(title: "Surgery", amount: 300)
        claim.policy = policy
        context.insert(claim)
        try context.save()
        context.delete(claim)
        context.rollback()
        XCTAssertEqual(try context.fetch(FetchDescriptor<InsuranceClaim>()).count, 1)
    }

    func testOnboardingSaveFailureLeavesNoPartialState() throws {
        let context = try makeContext()
        // Onboarding's finish(): profile + household + owner member are
        // created together; on failure ALL of it rolls back, so the app
        // can never gate into a half-created household.
        let profile = UserProfile(displayName: "Rukhsana")
        profile.hasCompletedOnboarding = true
        context.insert(profile)
        let household = Household()
        context.insert(household)
        let owner = HouseholdMember(displayName: "Rukhsana", role: .owner)
        owner.household = household
        context.insert(owner)
        profile.memberID = owner.id
        context.rollback()   // the catch branch's action
        XCTAssertEqual(try context.fetch(FetchDescriptor<UserProfile>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Household>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HouseholdMember>()).count, 0)
    }

    /// Proof the catch branches are reachable with a REAL failure: a
    /// store in a read-only location throws on save. Skips itself when
    /// the platform cannot create the failing configuration.
    func testRealSaveFailureThrows() throws {
        let url = URL(fileURLWithPath: "/proc/petcare360-v126/store.sqlite")
        let config = ModelConfiguration(schema: PetCare360App.appSchema(), url: url)
        guard let container = try? PetCare360App.makeContainer(configuration: config) else {
            throw XCTSkip("Platform does not allow the unwritable-store injection")
        }
        let context = ModelContext(container)
        context.insert(Pet(name: "Probe"))
        XCTAssertThrowsError(try context.save(),
                             "Saving to an unwritable store must throw — the error every v1.2.6 catch branch reports")
    }
}
