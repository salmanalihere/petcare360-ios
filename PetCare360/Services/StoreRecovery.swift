import Foundation

/// Bounded database recovery (build 13, owner-authorized 2026-11-06:
/// all existing records are demo/test data and may be lost).
///
/// Design rules — deliberately strict:
/// - Recovery runs AT MOST ONCE automatically per store generation.
///   There is no retry loop: if the wiped store still cannot open,
///   the user gets the storage-error screen.
/// - A manual reset from the error screen starts a NEW generation
///   (and is the only way to wipe again).
/// - Nothing here ever touches the CloudKit container or its
///   schema; the wipe removes only the LOCAL store files.
/// - There is no in-memory fallback anywhere in this flow.
enum StoreRecoveryPolicy {
    /// Decide whether the one-time automatic wipe may run: only when
    /// opening failed AND no recovery has been attempted yet for the
    /// current store generation.
    static func shouldWipeAndRetry(openFailed: Bool,
                                   recoveryAttemptedGeneration: Int,
                                   currentGeneration: Int) -> Bool {
        openFailed && recoveryAttemptedGeneration < currentGeneration
    }
}

/// UserDefaults bookkeeping for recovery attempts, keyed by store
/// generation so a manual reset (new generation) re-arms exactly
/// one automatic attempt for the new store — never more.
enum StoreRecoveryLedger {
    private static let generationKey = "pc360.store.generation"
    private static let attemptedKey = "pc360.store.recoveryAttemptedGeneration"

    static func currentGeneration(defaults: UserDefaults = .standard) -> Int {
        max(1, defaults.integer(forKey: generationKey))
    }

    static func recoveryAttemptedGeneration(defaults: UserDefaults = .standard) -> Int {
        defaults.integer(forKey: attemptedKey)
    }

    static func markRecoveryAttempted(for generation: Int, defaults: UserDefaults = .standard) {
        defaults.set(generation, forKey: attemptedKey)
    }

    /// Manual reset: a new generation begins. The caller wipes the
    /// store files and reopens; the new store gets its own single
    /// automatic recovery allowance.
    @discardableResult
    static func beginNewGeneration(defaults: UserDefaults = .standard) -> Int {
        let next = currentGeneration(defaults: defaults) + 1
        defaults.set(next, forKey: generationKey)
        return next
    }
}

/// Removes a SwiftData/SQLite store and its journal sidecars.
enum StoreFileWiper {
    static func wipeStoreFiles(at storeURL: URL, fileManager: FileManager = .default) {
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            try? fileManager.removeItem(at: url)
        }
    }
}
