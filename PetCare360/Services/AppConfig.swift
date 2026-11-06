import Foundation

/// Central configuration — the ONLY place legal URLs and the support
/// mailbox are defined. Every view reads them from here.
enum AppConfig {
    static let appName = "PetCare 360"
    static let tagline = "A healthier life together."
    static let bundleID = "com.xenon-media.petcare360"
    /// The existing iCloud container of the registered App Store
    /// Connect application (owner-confirmed 2026-11-06).
    static let iCloudContainerID = "iCloud.com.xenon-media.petcare360"
    /// CloudKit sync is ACTIVE (restored 2026-11-06 at the owner's
    /// instruction, matching the registered app). It was disabled in
    /// v1.2.2 because the Developer-portal setup could not be verified
    /// from the build environment at that time. If the container
    /// cannot be opened (missing capability/profile), PetCare360App
    /// falls back to the local store and then to its storage-error
    /// screen — it never crashes or deletes data.
    static let cloudKitSyncEnabled = true
    // Legal + support details supplied by the owner on 2026-11-05.
    // NOTE: the live pages could not be fetched from the build environment
    // (the page fetcher failed and neither host is search-indexed), so the
    // URLs are exactly as the owner supplied them. If a link ever needs to
    // change (e.g. a different GitHub username), change it HERE only.
    static let privacyPolicyURL = URL(string: "https://salmanalihere.github.io/petcare360-legal/privacy.html")!
    static let termsOfUseURL = URL(string: "https://salmanalihere.github.io/petcare360-legal/terms.html")!
    static let websiteURL = URL(string: "https://salmanalihere.github.io/petcare360-legal/")!
    static let supportEmail = "Salmanali929929@gmail.com"
    static var supportMailtoURL: URL {
        URL(string: "mailto:\(supportEmail)?subject=PetCare%20360%20Support")!
    }
    static let fdaRecallsURL = URL(string: "https://www.fda.gov/animal-veterinary/safety-health/recalls-withdrawals")!
    static let medicalDisclaimer = "PetCare 360 is a record-keeping and tracking tool. It does not provide veterinary diagnosis or treatment. Always consult a licensed veterinarian about your pet's health."
}

enum PremiumProduct {
    static let monthly = "com.petcare360.premium.monthly"
    static let yearly = "com.petcare360.premium.yearly"
    static let all: [String] = [monthly, yearly]
    /// US target prices from the master prompt. The price actually charged
    /// is always read live from StoreKit (`Product.displayPrice`).
    static let targetPrices = [monthly: "$4.99", yearly: "$29.99"]
}

enum PremiumFeature: String, CaseIterable {
    case unlimitedPets, householdSharing, fullMedicationHistory, unlimitedRecords, documentScanning, expenseTracking, insuranceOrganizer, advancedCharts, emergencyQR, advancedPDF, recallNotifications
    var label: String {
        switch self {
        case .unlimitedPets: return "Unlimited pet profiles"
        case .householdSharing: return "Household coordination & caregiver roles"
        case .fullMedicationHistory: return "Full medication history"
        case .unlimitedRecords: return "Unlimited medical records"
        case .documentScanning: return "Document scanning (on-device OCR)"
        case .expenseTracking: return "Expense tracking & reports"
        case .insuranceOrganizer: return "Insurance organizer"
        case .advancedCharts: return "Advanced health charts"
        case .emergencyQR: return "Emergency QR profile"
        case .advancedPDF: return "Advanced PDF exports"
        case .recallNotifications: return "Recall tracking & saved brands"
        }
    }
}

/// The benefits the paywall may advertise: only features that are
/// genuinely implemented AND differentiated from the free plan
/// (v1.2.4 accuracy pass). Full medication history and unlimited
/// medical records are available to everyone, so they are not sold
/// as Premium benefits.
extension PremiumFeature {
    static var paywallFeatures: [PremiumFeature] {
        [.unlimitedPets, .householdSharing, .documentScanning, .expenseTracking,
         .insuranceOrganizer, .advancedCharts, .emergencyQR, .advancedPDF, .recallNotifications]
    }
}

enum EntitlementPolicy {
    static let freePetLimit = 1
    static let freeDocumentLimit = 10
    static func canAddPet(currentCount: Int, isPremium: Bool) -> Bool {
        isPremium || currentCount < freePetLimit
    }
    static func canUse(_ feature: PremiumFeature, isPremium: Bool) -> Bool {
        isPremium
    }
    /// Phase 2, section D — downgrade safety: premium gates apply to
    /// CREATING new premium content and to premium-only workflows.
    /// Viewing, editing, exporting and deleting records the user already
    /// has is NEVER gated, and downgrading never deletes data.
    static func canCreate(_ feature: PremiumFeature, isPremium: Bool) -> Bool {
        isPremium
    }
}
