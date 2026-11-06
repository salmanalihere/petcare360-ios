# PetCare 360 — Database Recovery (Build 13)

Date: 2026-11-06. Trigger: TestFlight build 12 fails to open
SwiftData storage on iPhone 16 Pro Max, iOS 26.5.2. The owner
confirmed all existing records are demo/test data and may be
permanently lost; recovery was authorized on that basis.

## Root cause

What can be established from the code (the device's exact error
text was not available here — build 12 swallowed it, see defect
2 — so this is a code-level diagnosis, not a console log):

Build 12 was the FIRST build with CloudKit enabled. Devices that
ran builds up to 11 hold a local store at SwiftData's default
location, created WITHOUT CloudKit. Build 12's opening sequence
then had three defects:

1. **Same store file, two configurations.** The CloudKit
   configuration and the local fallback both target the default
   store URL. Opening a store created without the CloudKit
   integration through a CloudKit-mirroring configuration can
   fail at container creation — and a failed/partially-initialized
   CloudKit setup can leave that same file in a state the plain
   local open also rejects. The "fallback" was never independent.
2. **The CloudKit error was swallowed** (`try?`), so the error
   screen showed only the LOCAL error. The actual first failure
   was undiagnosable — which is why this report cannot quote it.
3. **No recovery path existed.** The only action offered was
   "Try Again", which replays the identical failing sequence
   forever. A poisoned store file could never heal.

(Secondary suspects that code cannot rule out from here: the
TestFlight/Production CloudKit environment's schema never having
been deployed from the Development environment — that fails
mirroring rather than the open itself, and is a CloudKit
Dashboard task, listed under "Owner actions" below.)

## The fix — smallest reliable recovery (Services/StoreRecovery.swift + PetCare360App.swift)

`openStorage()` is now an explicit ladder:
1. CloudKit-backed store (unchanged configuration).
2. Local store at the default location (unchanged).
3. **One-time automatic recovery, per store generation:** if
   both opens failed, the attempt is recorded FIRST, the local
   store files (store + -wal + -shm) are removed, and the local
   open is retried exactly once. Recording before retrying makes
   a delete/recreate loop impossible by construction.
4. Otherwise the storage-error screen — now showing BOTH error
   messages, plus a user-confirmed "Reset Database" action
   (confirmation dialog, destructive role) that starts a new
   store generation, wipes the local files, and reopens. A manual
   reset is the only way a second wipe can ever occur.

Guarantees preserved from the original design: NO in-memory
fallback anywhere; no model properties or relationships changed;
the CloudKit container and its schema are never touched by this
code; nothing outside PetCare360's own store files is deleted
(the wiper removes exactly 3 paths derived from the store URL).

## What data/store was reset

- By this code, on the device, only when BOTH opens fail: the
  LOCAL store files at SwiftData's default location (demo data
  on the test device). On a fresh install no wipe occurs at all —
  the store is created normally at step 1 or 2 and the app
  reaches onboarding/home.
- NOT reset: the CloudKit container, its schema, or any records
  in it. App code cannot delete server-side data, and none was
  attempted. Note the consequence: if the CloudKit store opens
  after a local reset, the demo records still in the container
  will sync back down — that is sync working correctly, not the
  bug returning.

## Owner actions (only if needed)

- Clean device start: delete the app before installing build 13
  for the simplest guaranteed-fresh store.
- To remove demo records from the container itself: CloudKit
  Dashboard → iCloud.com.xenon-media.petcare360 → Production →
  Records: delete the demo records (do NOT reset the schema).
- If the error screen persists on a fresh install, its message
  now contains the real first error — send a screenshot of it and
  the next diagnosis will be exact, not inferential.

## What was preserved

Bundle com.xenon-media.petcare360; version 1.2.8; all app
functionality and model definitions (unchanged); app icons
(universal-format Contents.json); platform settings
(SDKROOT/SUPPORTED_PLATFORMS); CFBundleIconName; CloudKit
entitlements + container; predicate fix; notification sound fix
and the full sound system. Build number 12 → 13 (app target
Debug + Release only).

## Database recovery tests performed

Written (PetCare360RecoveryTests, 6 methods; 143 total written,
ZERO executed — no Xcode/device here, not claimed):
- Policy: one wipe allowed per generation; never on success;
  a new generation re-arms exactly one
- Ledger: generation/attempted round-trip in isolated defaults
- Wiper: removes store + both sidecars, leaves unrelated files
- File-backed container: create → insert → reopen same file →
  record present → update → delete (real on-disk CRUD/reopen)
Local static verification: swiftc -parse 47/47 PASS,
tree-sitter 47/47 PASS, per-struct state sweep ALL RESOLVE,
project config checks PASS (bundle/build 13/version/platform/
icon name/entitlements).
NOT performed (stated plainly): iPhone or Xcode testing of any
kind. On-device verification still required: fresh install of
build 13 reaches onboarding, relaunch reopens the store,
add/edit a pet, and (with an earlier build's store present)
the upgrade path opens or recovers once as designed.

## Exact files changed

- NEW PetCare360/Services/StoreRecovery.swift (policy, ledger, wiper)
- PetCare360/PetCare360App.swift (openStorage ladder, both errors
  surfaced, StorageErrorView: honest copy + confirmed Reset action)
- NEW PetCare360Tests/PetCare360RecoveryTests.swift (6 tests)
- PetCare360.xcodeproj/project.pbxproj (build 13; new files)
- docs/RECOVERY_REPORT.md (this file), docs/TEST_REPORT.md addendum
- (Outside the ZIP) generator petcare-build: build 13 so
  regeneration cannot revert it.
