# PetCare 360 — Build 13 Storage Failure: Diagnostic Report

Date: 2026-11-06. Status: INVESTIGATION — no production fix is
claimed in this document. Build number UNCHANGED (13). This
package is a DIAGNOSTIC build, not a release.

Device evidence (owner-reported): TestFlight 1.2.8 (13), iPhone
16 Pro Max, iOS 26.5.2, app deleted and reinstalled, error screen
shows BOTH attempts failing with "(SwiftData.SwiftDataError
error 1.)". Reset Database appeared to do nothing.

## 1. What the fresh-install failure PROVES

The build-13 recovery assumed a poisoned legacy store file.
A deleted-and-reinstalled app has NO legacy file, yet a fresh
local ModelContainer creation still throws. CONCLUSION: the
failure is NOT file state, NOT migration of old data, and NOT
CloudKit alone (the plain local configuration fails identically).
It is at ModelContainer CREATION, in the schema/configuration/
environment triangle. The reset button could therefore never
change the outcome (it only deletes files) — see section 4.

## 2. Model audit (all 23 models read in full)

Files: Models/{PetModels, MedicationModels, HealthModels,
FinanceModels, HouseholdModels}.swift. Registered in appSchema():
23 types = 23 @Model classes. Findings:

- Relationships form complete pairs with inferable inverses:
  Pet <-> its 9 children (each child has `var pet: Pet?`; Pet
  declares the 9 cascade arrays); Household.members <->
  HouseholdMember.household; InsurancePolicy.claims <->
  InsuranceClaim.policy. No explicit inverse attributes are used
  anywhere (macro/runtime inference), no dangling references.
- NO @Attribute(.unique) anywhere. 5 @Attribute(.externalStorage)
  Data? properties (photo/receipt/document blobs) — supported by
  local SwiftData and CloudKit.
- Every stored property is a Foundation value type (UUID, String,
  Int, Double, Bool, Date, Data?, [Int], [String]) and is either
  optional or has a default. NO enum-typed stored properties —
  enums persist as raw String columns (speciesRaw etc.).
- No model property lacks a default except optionals; no static
  stored properties; no unsupported types found.

RESULT: no model-level defect was found by static audit that
explains a LOCAL creation failure. The same schema (except the
additive VetAppointment.isCancelled and two new PetSpecies raw
values, neither of which alters stored schema shape) ran on this
device in builds up to 11. The regression window is builds
12-13: CloudKit enabled + entitlements wired, bundle ID changed,
built with Xcode 26.6 for iOS 26.5.2.

## 3. Remaining unknowns (precise)

U1. The underlying NSError chain. "SwiftDataError error 1"
    alone does not identify the cause; the chain (domain, code,
    failure reason, underlying Core Data/CloudKit errors) was
    never captured. FIXED INSTRUMENTATION-WISE in this package:
    StorageDiagnostics formats the full chain and the error
    screen now displays it. A screenshot of the new error screen
    is the single most valuable next artifact.
U2. Whether a MINIMAL schema opens on this device/OS. If even
    one trivial @Model fails, the cause is environmental
    (iOS 26.5.2 / Xcode 26.6 toolchain / store location), not
    PetCare360's models. -> diagnostic test A.
U3. If minimal passes: which model GROUP breaks creation.
    -> diagnostic tests B + D1-D4 (relationship-closed groups).
U4. CloudKit side, unverifiable from here: (a) does the App ID's
    provisioning profile used by Codemagic actually include the
    iCloud capability + container? (b) is the CloudKit schema
    DEPLOYED TO PRODUCTION (TestFlight uses Production; a schema
    that only exists in Development fails there)? (c) is the
    device signed into iCloud? These explain a CloudKit failure
    but NOT the local one; they are not the primary suspect.
U5. Whether the one-time wipe in build 13 actually ran (the
    owner's quote shows only the first two error lines; a wipe
    attempt would add "After one-time reset:" lines — possibly
    below the visible area). The new screen makes this explicit.

## 4. Reset button trace (why it "did nothing")

Path: tap -> confirmationDialog -> destructive action ->
StoreRecoveryLedger.beginNewGeneration() (UserDefaults) ->
StoreFileWiper removes default-store files -> openStorage()
ladder -> both opens throw again -> .failed with a message whose
first lines are IDENTICAL to the pre-reset screen, rendered in
caption-size text, with (in build 13) no spinner, no timestamp,
and no result line. Every step executed; the outcome could not
differ because the defect is not in the files. Two feedback
defects, both corrected in this diagnostic package: a ProgressView
now shows during retry/reset, and a failed reset returns an
explicit outcome line ("Reset ran at <time> (store generation
N): local database files were removed and reopening was retried.
It still failed — the problem is not the database files.")
followed by the full error chain.

## 5. Changes included in this diagnostic package

- NEW Services/StorageDiagnostics.swift — recursive NSError
  chain formatter (domain/code/description/failure reason/
  recovery suggestion/underlying/CK userInfo). No try? anywhere
  in the storage path; every caught error is now described.
- PetCare360App.swift — openStorage uses the chain formatter for
  all three failure points; resetAndReopen adds the outcome
  line; StorageErrorView shows progress while working.
- NEW PetCare360Tests/PetCare360StorageDiagnosticsTests.swift —
  tests A (minimal), B (full local), C (CloudKit attempt,
  record-only, prints the chain), D1-D4 (closed groups), each
  with create/save/reopen against temporary directories.
- NO model changes. NO configuration changes. Build stays 13.
  Bundle/container/entitlements untouched (re-verified:
  com.xenon-media.petcare360 / iCloud.com.xenon-media.petcare360
  / CODE_SIGN_ENTITLEMENTS wired).

## 6. Diagnostic test results

Written: 8 diagnostic methods (151 total tests in project).
Executed: ZERO — this environment has no Xcode, no SwiftData
runtime (Linux), and no iPhone. Any claim otherwise would be
false. They must be run on the owner's Mac (Xcode, run the
PetCare360StorageDiagnosticsTests suite on the iPhone 16 Pro Max
or a simulator on iOS 26.x) or via a Codemagic test workflow on
branch petcare360-clean-release.

## 7. Smallest safe correction — decision tree (no fix yet)

- A fails -> environmental: escalate with the captured chain
  (Apple DTS / toolchain issue); likely remedies live OUTSIDE the
  models (Xcode/OS version pairing, store location). Do not
  touch models.
- A passes, ONE group fails -> bisect inside that group (remove
  one child model at a time using the same temp-store pattern);
  the correction is then scoped to the single offending
  model/attribute (e.g. an attribute or relationship adjustment)
  — made only with the chain as evidence.
- A + B pass on device -> the app binary's failure differs from
  the tests': compare configuration paths (default store URL vs
  explicit URL — see test file note E) and entitlements in the
  signed build; correction targets configuration, not models.
- C's chain decides the CloudKit remedy (profile capability vs
  Production schema deployment vs account state).

Until one branch is evidenced, ANY "fix" would be guessing —
which is how builds 12 and 13 got here.
