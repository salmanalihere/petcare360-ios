import Foundation
import Security

/// Where the trial's start date is persisted. The production store
/// is the Keychain (below); tests substitute an in-memory store.
protocol TrialDateStore {
    func loadStartDate() -> Date?
    func saveStartDate(_ date: Date)
}

/// Keychain-backed trial start date.
///
/// Why Keychain and not UserDefaults: UserDefaults is deleted when
/// the app is deleted, so a UserDefaults-only trial could be reset
/// by reinstalling. Keychain items survive app deletion on the same
/// device, so deleting and reinstalling PetCare 360 does NOT restart
/// the trial. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// additionally keeps the item out of iCloud Keychain and out of
/// backups restored to a DIFFERENT device.
///
/// Honest limitations (also stated in the delivery report):
/// - A factory reset / erased device wipes the Keychain, so a trial
///   can start again there — no on-device store can prevent that.
/// - A brand-new device has no record, so the trial starts fresh.
/// - The trial clock is the device clock; a user who sets the device
///   clock backwards can stretch the remaining time. The stored
///   start date itself can never move earlier once written.
final class KeychainTrialDateStore: TrialDateStore {
    private let service = "com.xenon-media.petcare360.trial"
    private let account = "trial-start-date"

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func loadStartDate() -> Date? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8),
              let seconds = TimeInterval(text) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    func saveStartDate(_ date: Date) {
        let text = String(date.timeIntervalSince1970)
        guard let data = text.data(using: .utf8) else { return }
        let status = SecItemAdd(baseQuery.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(baseQuery as CFDictionary,
                          [kSecValueData as String: data] as CFDictionary)
        }
    }
}

/// In-memory store for tests. Two TrialManagers sharing one instance
/// simulate separate app launches (and a reinstall) on one device.
final class InMemoryTrialDateStore: TrialDateStore {
    private var stored: Date?
    func loadStartDate() -> Date? { stored }
    func saveStartDate(_ date: Date) { stored = date }
}

enum TrialState: Equatable {
    case notStarted
    case active(daysRemaining: Int, endsAt: Date)
    case expired
}

/// The 7-day free trial of ALL Premium features (owner brief
/// 2026-11-07). This is an APP-MANAGED trial, chosen deliberately
/// over a StoreKit introductory offer: the brief requires the trial
/// to start at first launch with no purchase, no payment method and
/// no subscription commitment, which an introductory offer cannot
/// do (it attaches to a purchase). The trade-offs are stated in the
/// delivery report.
///
/// Authority: the Keychain-stored start date above. There is no
/// UserDefaults flag that grants access on its own, no hardcoded
/// permanent unlock, and no interaction with StoreKit verification —
/// a verified purchase always wins (see `EntitlementPolicy.hasAccess`).
final class TrialManager: ObservableObject {
    static let duration: TimeInterval = 7 * 24 * 3600

    @Published private(set) var state: TrialState = .notStarted

    private let store: TrialDateStore
    private let now: () -> Date

    init(store: TrialDateStore = KeychainTrialDateStore(), now: @escaping () -> Date = { Date() }) {
        self.store = store
        self.now = now
        refresh()
    }

    var isActive: Bool {
        if case .active = state { return true }
        return false
    }

    var daysRemaining: Int {
        if case .active(let days, _) = state { return days }
        return 0
    }

    var endsAt: Date? {
        if case .active(_, let end) = state { return end }
        return nil
    }

    /// Starts the trial on first launch. Idempotent: a stored start
    /// date is never overwritten, so the trial cannot be restarted
    /// by relaunching or reinstalling.
    func beginIfNeeded() {
        if store.loadStartDate() == nil {
            store.saveStartDate(now())
        }
        refresh()
    }

    func refresh() {
        guard let start = store.loadStartDate() else {
            state = .notStarted
            return
        }
        let end = start.addingTimeInterval(Self.duration)
        let current = now()
        if current < end {
            let remaining = Int(ceil(end.timeIntervalSince(current) / 86400))
            state = .active(daysRemaining: max(1, remaining), endsAt: end)
        } else {
            state = .expired
        }
    }
}
