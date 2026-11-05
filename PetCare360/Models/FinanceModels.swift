import Foundation
import SwiftData

enum ExpenseCategory: String, Codable, CaseIterable {
    case food, medication, veterinary, vaccinations, grooming, toys, insurance, boarding, other
    var label: String {
        switch self {
        case .food: return "Food"
        case .medication: return "Medication"
        case .veterinary: return "Veterinary visits"
        case .vaccinations: return "Vaccinations"
        case .grooming: return "Grooming"
        case .toys: return "Toys"
        case .insurance: return "Insurance"
        case .boarding: return "Boarding"
        case .other: return "Other"
        }
    }
}

/// Money is stored as a Decimal string so totals are exact, never float-rounded.
@Model
final class PetExpense {
    var id: UUID = UUID()
    var amountString: String = "0"
    var date: Date = Date()
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var vendor: String = ""
    var notes: String = ""
    @Attribute(.externalStorage) var receiptData: Data? = nil
    var pet: Pet? = nil
    init(amount: Decimal, category: ExpenseCategory, date: Date = Date()) {
        self.id = UUID()
        self.amountString = NSDecimalNumber(decimal: amount).stringValue
        self.categoryRaw = category.rawValue
        self.date = date
    }
    var amount: Decimal { Decimal(string: amountString) ?? 0 }
    var category: ExpenseCategory { ExpenseCategory(rawValue: categoryRaw) ?? .other }
}

enum ClaimStatus: String, Codable, CaseIterable {
    case draft, submitted, underReview, approved, rejected, paid
    var label: String {
        switch self {
        case .draft: return "Draft"
        case .submitted: return "Submitted"
        case .underReview: return "Under review"
        case .approved: return "Approved"
        case .rejected: return "Rejected"
        case .paid: return "Paid"
        }
    }
}

@Model
final class InsurancePolicy {
    var id: UUID = UUID()
    var petID: UUID = UUID()
    var petName: String = ""
    var provider: String = ""
    var policyNumber: String = ""
    var coverageDetails: String = ""
    var startDate: Date = Date()
    var renewalDate: Date? = nil
    var deductibleString: String = "0"
    var reimbursementPercent: Int = 0
    @Relationship(deleteRule: .cascade) var claims: [InsuranceClaim] = []
    init(provider: String, petID: UUID, petName: String) {
        self.id = UUID()
        self.provider = provider
        self.petID = petID
        self.petName = petName
        self.startDate = Date()
    }
    var deductible: Decimal { Decimal(string: deductibleString) ?? 0 }
}

@Model
final class InsuranceClaim {
    var id: UUID = UUID()
    var title: String = ""
    var amountString: String = "0"
    var statusRaw: String = ClaimStatus.draft.rawValue
    var date: Date = Date()
    var notes: String = ""
    var policy: InsurancePolicy? = nil
    init(title: String, amount: Decimal) {
        self.id = UUID()
        self.title = title
        self.amountString = NSDecimalNumber(decimal: amount).stringValue
        self.date = Date()
    }
    var amount: Decimal { Decimal(string: amountString) ?? 0 }
    var status: ClaimStatus { ClaimStatus(rawValue: statusRaw) ?? .draft }
}

@Model
final class FoodSchedule {
    var id: UUID = UUID()
    var foodBrand: String = ""
    var foodType: String = ""
    var portion: String = ""
    var timeMinutes: Int = 480
    var frequencyNote: String = "Daily"
    var instructions: String = ""
    var transitionNote: String = ""
    var isActive: Bool = true
    @Attribute(.externalStorage) var packagingPhotoData: Data? = nil
    var pet: Pet? = nil
    init(brand: String) {
        self.id = UUID()
        self.foodBrand = brand
    }
}

@Model
final class FeedingLog {
    var id: UUID = UUID()
    var petID: UUID = UUID()
    var petName: String = ""
    var date: Date = Date()
    var fedBy: String = ""
    var portionGiven: String = ""
    init(petID: UUID, petName: String, by: String) {
        self.id = UUID()
        self.petID = petID
        self.petName = petName
        self.fedBy = by
        self.date = Date()
    }
}

/// A recall entry is only ever created from an official source the user
/// opens; the app ships with NO bundled recall data and never invents recalls.
@Model
final class RecallAlert {
    var id: UUID = UUID()
    var productName: String = ""
    var manufacturer: String = ""
    var recallDate: Date = Date()
    var reason: String = ""
    var affectedDetails: String = ""
    var sourceURL: String = ""
    var savedBrand: String = ""
    var createdAt: Date = Date()
    init(productName: String, manufacturer: String, sourceURL: String) {
        self.id = UUID()
        self.productName = productName
        self.manufacturer = manufacturer
        self.sourceURL = sourceURL
        self.createdAt = Date()
    }
}

@Model
final class SavedFoodBrand {
    var id: UUID = UUID()
    var brand: String = ""
    var productName: String = ""
    var manufacturer: String = ""
    init(brand: String) {
        self.id = UUID()
        self.brand = brand
    }
}

/// Owner-controlled emergency profile. Sensitive fields are excluded
/// unless the owner explicitly includes them in `sharedFieldKeys`.
@Model
final class EmergencyProfile {
    var id: UUID = UUID()
    var petID: UUID = UUID()
    var petName: String = ""
    var sharedFieldKeys: [String] = []
    var isEnabled: Bool = false
    var updatedAt: Date = Date()
    init(petID: UUID, petName: String) {
        self.id = UUID()
        self.petID = petID
        self.petName = petName
        self.updatedAt = Date()
    }
    static let allFields = ["allergies", "medications", "conditions", "microchip", "vet", "emergencyContact", "insurance", "notes"]
    func shares(_ key: String) -> Bool { isEnabled && sharedFieldKeys.contains(key) }
}

@Model
final class SubscriptionEntitlement {
    var id: UUID = UUID()
    var productID: String = ""
    var isActive: Bool = false
    var expirationDate: Date? = nil
    var lastVerifiedAt: Date = Date()
    init() {
        self.id = UUID()
        self.lastVerifiedAt = Date()
    }
}
