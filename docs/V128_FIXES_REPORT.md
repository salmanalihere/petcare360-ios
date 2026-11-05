# PetCare 360 — v1.2.8 Final Backup Safety Corrections (build 11)

## 1. RestoreSummary.skipped — parent records now counted
An existing pet profile counts as skipped (+1) and an existing
household counts as skipped (+1), in addition to all per-record
child counting from v1.2.7. Newly inserted records are never counted
as skipped (the counts derive from the pre-merge ID indexes), merge
behaviour is unchanged, and existing records remain untouched.
The v1.2.7 fixture was recounted record by record: it holds exactly
21 records (1 pet + 1 household + 1 member + 9 pet children + 1 task
+ 1 handoff + 1 feeding log + 1 policy + 1 claim + 1 emergency
profile + 1 brand + 1 recall + 1 medication schedule). The test now
asserts the corrected totals: Replace into an empty store —
inserted 21, skipped 0; identical Merge — inserted 0, skipped 21.

## 2. Replace restore is atomic
Previously `deleteEverything(in:)` ran BEFORE restore's do/catch:
if it (or anything after it) failed, the deletions stayed pending in
the context and a later unrelated save could have committed them —
a partially deleted database. The Replace deletion, the existing-ID
indexing (which must run after the deletion so its sets are empty),
the whole import and the final save now live inside ONE do/catch
whose catch calls `context.rollback()`. Any failure — deletion,
fetch, import step or final save — discards everything.
UserProfile is preserved by the existing design (deleteEverything
never touches it; a test pins this). Merge behaviour is unchanged.
Import-screen review: Settings' confirmImport already reports
failure honestly ("Import failed and was rolled back. Nothing was
changed.") and the legacy-v1 path already rolled back; with this
fix, the v2 path's claim is now actually guaranteed by restore()
itself, and no partially modified context state can survive a
failed restore.

## 3. Tests
Preserved: 93 unit + 8 UI = 101 (the v1.2.7 fixture test updated in
place to the corrected 21/21 expectations). Added: 5 tests
(PetCare360V128Tests) — existing pet counted, existing household
counted, Replace-failure rollback of pending deletions, atomic
Replace swap, UserProfile survival. Total written: 98 unit + 8 UI
= 106. Executed: **0**.

## Syntax verification (actual results)
swiftc -parse (official Swift 6.0.3): **38/38 PASS, 0 FAIL**,
re-run on the extracted ZIP. tree-sitter Swift grammar: 38/38 PASS.
Syntax only; Xcode compilation and test execution remain unverified
and are not claimed.

## Configuration
Version 1.2.8, build 11. Bundle ID com.petcare360.app, iOS 17.0,
StoreKit IDs/prices, legal URLs/email, CloudKit disabled — all
preserved. No signing settings exist or were touched;
codemagic.yaml still does not exist.

## Files modified
BackupService.swift (parent skipped counts; Replace inside do/catch),
PetCare360V127Tests.swift (fixture totals 21/21),
docs (this report, TEST_REPORT addendum), project.pbxproj + scheme
(regenerated; 1.2.8/build 11 + new test file).
ADDED: PetCare360Tests/PetCare360V128Tests.swift.
