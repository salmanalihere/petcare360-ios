import Foundation
import SwiftData

enum HouseholdRole: String, Codable, CaseIterable {
    case owner, family, petSitter, dogWalker, viewer
    var label: String {
        switch self {
        case .owner: return "Owner"
        case .family: return "Family"
        case .petSitter: return "Pet Sitter"
        case .dogWalker: return "Dog Walker"
        case .viewer: return "Viewer"
        }
    }
}

enum CarePermission: String, Codable, CaseIterable {
    case managePets, manageRecords, giveMedication, completeCare, logActivity, viewOnly
}

enum HouseholdPermissions {
    static func permissions(for role: HouseholdRole) -> Set<CarePermission> {        switch role {
        case .owner: return [.managePets, .manageRecords, .giveMedication, .completeCare, .logActivity, .viewOnly]
        case .family: return [.manageRecords, .giveMedication, .completeCare, .logActivity, .viewOnly]
        case .petSitter: return [.giveMedication, .completeCare, .logActivity, .viewOnly]
        case .dogWalker: return [.completeCare, .logActivity, .viewOnly]
        case .viewer: return [.viewOnly]
        }
    }
    static func can(_ role: HouseholdRole, do permission: CarePermission) -> Bool {
        permissions(for: role).contains(permission)
    }
}

@Model
final class Household {
    var id: UUID = UUID()
    var name: String = "My Household"
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade) var members: [HouseholdMember] = []
    init(name: String = "My Household") {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

@Model
final class HouseholdMember {
    var id: UUID = UUID()
    var displayName: String = ""
    var roleRaw: String = HouseholdRole.viewer.rawValue
    var invitedEmail: String = ""
    var isInvitationPending: Bool = true
    var accessExpiresAt: Date? = nil   // temporary caregiver access
    var joinedAt: Date = Date()
    var household: Household? = nil
    init(displayName: String, role: HouseholdRole) {
        self.id = UUID()
        self.displayName = displayName
        self.roleRaw = role.rawValue
        self.joinedAt = Date()
    }
    var role: HouseholdRole { HouseholdRole(rawValue: roleRaw) ?? .viewer }
    var hasActiveAccess: Bool {
        if isInvitationPending { return false }
        guard let exp = accessExpiresAt else { return true }
        return exp > Date()
    }
}

enum CareTaskKind: String, Codable, CaseIterable {
    case feeding, medication, walk, grooming, vetVisit, other
    var label: String {
        switch self {
        case .feeding: return "Feeding"
        case .medication: return "Medication"
        case .walk: return "Walk"
        case .grooming: return "Grooming"
        case .vetVisit: return "Vet visit"
        case .other: return "Other"
        }
    }
}

@Model
final class CareTask {
    var id: UUID = UUID()
    var petID: UUID = UUID()
    var petName: String = ""
    var kindRaw: String = CareTaskKind.other.rawValue
    var title: String = ""
    var scheduledDate: Date = Date()
    var assignedTo: String = ""
    var isCompleted: Bool = false
    var completedBy: String = ""
    var completedAt: Date? = nil
    var createdAt: Date = Date()
    init(title: String, petID: UUID, petName: String, kind: CareTaskKind = .other, date: Date = Date()) {
        self.id = UUID()
        self.title = title
        self.petID = petID
        self.petName = petName
        self.kindRaw = kind.rawValue
        self.scheduledDate = date
        self.createdAt = Date()
    }
    var kind: CareTaskKind { CareTaskKind(rawValue: kindRaw) ?? .other }
}

/// Structured caregiver update left for the household.
@Model
final class CareHandoff {
    var id: UUID = UUID()
    var petName: String = ""
    /// The pet this handoff belongs to (v1.2.5). Optional: records
    /// created before this association existed keep nil and are NEVER
    /// deleted by name matching — only ID-matched handoffs are removed
    /// when a pet is deleted.
    var petID: UUID? = nil
    var authorName: String = ""
    /// Stable member identity of the author (Phase 2); authorName is display only.
    var authorMemberID: UUID? = nil
    var date: Date = Date()
    var wasFed: Bool = false
    var medicationGiven: Bool = false
    var walkCompleted: Bool = false
    var appetiteNormal: Bool = true
    var unusualBehavior: String = ""
    var notes: String = ""
    init(petName: String, author: String) {
        self.id = UUID()
        self.petName = petName
        self.authorName = author
        self.date = Date()
    }
}

/// Stable-identity role resolution (Phase 2, section G).
/// Roles are resolved by the member's UUID, never by display name.
/// Resolution order:
/// 1. Exact member-ID match.
/// 2. Single-device fallback: on a device whose owner completed onboarding,
///    the sole Owner member IS this device's user (covers households created
///    before stable IDs were linked at onboarding).
/// 3. No match -> nil (treated as no household role; the UI falls back to
///    read-only behaviour rather than granting access).
enum HouseholdIdentity {
    static func resolveRole(memberID: UUID, members: [HouseholdMember]) -> HouseholdRole? {
        if let match = members.first(where: { $0.id == memberID }) {
            return match.role
        }
        let owners = members.filter { $0.role == .owner }
        if owners.count == 1 { return .owner }
        return nil
    }
}
