import Foundation
import Security

/// Where the trial's start date is persisted. The production store
/// is the Keychain (below); tests substitute in-memory/failing
/// stores. `saveStartDate` reports success honestly — a trial whose
/// start date was not persisted must never be reported as active.
protocol TrialDateStore {
    func loadStartDate() -> Date?
    @discardableResult func saveStartDate(_ date: Date) -> Bool
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

    @discardableResult
    func saveStartDate(_ date: Date) -> Bool {
        let text = String(date.timeIntervalSince1970)
        guard let data = text.data(using: .utf8) else { return false }
        let status = SecItemAdd(baseQuery.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]) { _, new in new } as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem {
            return SecItemUpdate(baseQuery as CFDictionary,
                                 [kSecValueData as String: data] as CFDictionary) == errSecSuccess
        }
        return false
    }
}

/// In-memory store for tests. Two TrialManagers sharing one instance
/// simulate separate app launches (and a reinstall) on one device.
final class InMemoryTrialDateStore: TrialDateStore {
    private var stored: Date?
    func loadStartDate() -> Date? { stored }
    @discardableResult
    func saveStartDate(_ date: Date) -> Bool { stored = date; return true }
}

enum TrialState: Equatable {
    case notStarted
    case active(daysRemaining: Int, endsAt: Date)
    case expired
    /// Existing user who upgraded from a version without a trial:
    /// no trial is offered, and none was ever started. Distinct from
    /// .expired so the UI never tells them a trial "ended" that they
    /// never had, and the trial-expired paywall never appears.
    case notApplicable
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
///
/// MIGRATION POLICY (2026-11-07 review): the trial is for NEW users
/// of this build. An install that already holds a completed user
/// profile when the trial is first resolved is an upgrading existing
/// user: the trial is recorded as not applicable (a sentinel start
/// date) instead of silently starting a fresh 7-day trial. Purchases
/// and data are untouched — resolution only reads whether a profile
/// exists, and entitlement still comes from StoreKit alone.
final class TrialManager: ObservableObject {
    static let duration: TimeInterval = 7 * 24 * 3600
    /// Stored in place of a real start date for migrated existing
    /// users: a decision is recorded (so it is never re-decided),
    /// but no trial ever runs.
    static let migratedSentinel = Date(timeIntervalSince1970: 0)

    @Published private(set) var state: TrialState = .notStarted
    /// True when a Keychain write could not be persisted/verified.
    /// The trial then stays .notStarted — it is never reported as
    /// active on the strength of an unpersisted start date.
    @Published private(set) var persistenceFailed = false

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

    /// Whether any decision (real start date or migration sentinel)
    /// has been recorded. The app resolves the trial exactly once,
    /// when this is false.
    var hasRecordedDecision: Bool { store.loadStartDate() != nil }

    /// The one-time resolution, called by the app once it knows
    /// whether this install already holds user data:
    /// - decision already recorded → just refresh (relaunch,
    ///   reinstall, or a previously resolved migration);
    /// - existing user (profile predates this build) → record the
    ///   migration sentinel, no trial;
    /// - new user → start the trial.
    func resolveInitialState(hasExistingData: Bool) {
        if store.loadStartDate() != nil {
            refresh()
            return
        }
        if hasExistingData {
            if !store.saveStartDate(Self.migratedSentinel) {
                persistenceFailed = true
            }
            // Even if the sentinel could not be persisted, this
            // session's state is correct; the next launch resolves
            // the same way because the profile still exists.
            state = .notApplicable
        } else {
            beginIfNeeded()
        }
    }

    /// Starts the trial (new users). Idempotent: a stored start date
    /// is never overwritten, so the trial cannot be restarted by
    /// relaunching or reinstalling. The trial becomes active ONLY
    /// when the start date was actually persisted and read back —
    /// a Keychain failure leaves the state .notStarted and raises
    /// `persistenceFailed`, never a phantom trial.
    func beginIfNeeded() {
        if store.loadStartDate() != nil {
            refresh()
            return
        }
        let start = now()
        guard store.saveStartDate(start),
              let persisted = store.loadStartDate(),
              abs(persisted.timeIntervalSince(start)) < 1 else {
            persistenceFailed = true
            state = .notStarted
            return
        }
        refresh()
    }

    func refresh() {
        guard let start = store.loadStartDate() else {
            state = .notStarted
            return
        }
        if start == Self.migratedSentinel {
            state = .notApplicable
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
