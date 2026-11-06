import Foundation

/// Full NSError-chain reporting for storage failures (build 13
/// diagnostic instrumentation). Build 12/13's error screen showed
/// only `localizedDescription` — "(SwiftData.SwiftDataError
/// error 1.)" — which identifies nothing. This formatter walks the
/// whole chain: domain, code, description, failure reason,
/// recovery suggestion, and every underlying error recursively,
/// plus CloudKit-specific userInfo when present. The text is shown
/// on the storage-error screen so a screenshot captures everything
/// needed to diagnose without a Mac console.
enum StorageDiagnostics {
    static func describe(_ error: Error, prefix: String) -> String {
        var lines: [String] = []
        describe(error as NSError, depth: 0, into: &lines)
        return ([prefix] + lines).joined(separator: "\n")
    }

    private static func describe(_ ns: NSError, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        lines.append("\(indent)[\(ns.domain) code \(ns.code)] \(ns.localizedDescription)")
        if let reason = ns.localizedFailureReason, !reason.isEmpty {
            lines.append("\(indent)reason: \(reason)")
        }
        if let suggestion = ns.localizedRecoverySuggestion, !suggestion.isEmpty {
            lines.append("\(indent)suggestion: \(suggestion)")
        }
        // CloudKit errors carry the real cause in userInfo
        // (partial errors per record zone, retry-after, etc.).
        if ns.domain == "CKErrorDomain" || ns.domain.hasPrefix("CK") {
            for (key, value) in ns.userInfo where key != NSUnderlyingErrorKey {
                lines.append("\(indent)ck \(key): \(value)")
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("\(indent)underlying:")
            describe(underlying, depth: depth + 1, into: &lines)
        }
        // Some frameworks chain via a userInfo array instead.
        if let chain = ns.userInfo["NSMultipleUnderlyingErrors"] as? [NSError] {
            for (index, sub) in chain.enumerated() {
                lines.append("\(indent)underlying[\(index)]:")
                describe(sub, depth: depth + 1, into: &lines)
            }
        }
    }
}
