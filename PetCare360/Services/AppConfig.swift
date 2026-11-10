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
    /// CloudKit sync is DISABLED for the initial release (owner
    /// decision 2026-11-11): PetCare 360 launches as a local-only
    /// app. It was active from 2026-11-06, but the current schema
    /// cannot pass CloudKit validation (its to-many relationships
    /// are non-optional), so the CloudKit store never opened and
    /// the app has always run on its local store in practice. With
    /// this flag off, PetCare360App skips the CloudKit attempt
    /// entirely and opens the existing local configuration
    /// (`cloudKitDatabase: .none`) directly — same store location,
    /// no migration, existing data untouched. The container ID
    /// above is retained for a future version, when sync will be
    /// reconsidered together with the schema changes it requires.
    /// The local fallback ladder and storage-error screen remain
    /// in place unchanged.
    static let cloudKitSyncEnabled = false
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
    /// The App Store Connect subscription group "PetCare 360
    /// Premium" (owner-verified 2026-11-07). StoreKit reads the
    /// group's subscription statuses (renewal, grace period,
    /// billing retry) through this ID.
    static let subscriptionGroupID = "22553779"
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
    case unlimitedPets, householdSharing, fullMedicationHistory, unlimitedRecords, documentStorage, expenseTracking, insuranceOrganizer, advancedCharts, emergencyQR, advancedPDF, recallNotifications
    var label: String {
        switch self {
        case .unlimitedPets: return "Unlimited pet profiles"
        case .householdSharing: return "Household coordination & caregiver roles"
        case .fullMedicationHistory: return "Full medication history"
        case .unlimitedRecords: return "Unlimited medical records"
        case .documentStorage: return "Document storage"
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
        [.unlimitedPets, .householdSharing, .documentStorage, .expenseTracking,
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
    /// Full access = a verified Apple subscription entitlement,
    /// nothing else (subscription-only model, 2026-11-08). The
    /// entitlement already includes the introductory free trial,
    /// the billing grace period and a cancelled-but-unexpired
    /// subscription, because StoreManager derives it from
    /// StoreKit's verified current entitlements and subscription
    /// statuses. There is no app-managed trial and no free tier.
    static func hasAccess(isPremium: Bool) -> Bool {
        isPremium
    }
}
