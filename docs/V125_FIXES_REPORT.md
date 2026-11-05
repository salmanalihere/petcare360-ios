# PetCare 360 — v1.2.5 Final Data Integrity Corrections (build 8)

## 1. Archived-pet restore limit — one shared path
The pet list's Archived section had its own bare
`pet.isArchived = false` button that bypassed the free-plan limit.
There is now ONE restoration implementation, `PetArchiveService`
(PetDeletionService.swift), used by both the pet list and the pet
detail screen. It checks the active-pet count against the verified
premium entitlement (`EntitlementPolicy.canAddPet`), returns
`.limitReached` (the existing limit alert shows), saves with
do/catch + rollback on failure (`.saveFailed`, error alert, nothing
changed), and on success rebuilds eligible reminders through the
centralized synchronization (§5). Archiving goes through the same
service (reminders cancelled, save error-handled).

## 2. Pet deletion failure handling
PetDetailView's delete action previously caught failures, attempted
another silent save, and dismissed anyway. Now: success → dismiss;
failure → `context.rollback()`, the screen STAYS OPEN, and a "Delete
failed" alert explains nothing was removed. PetDeletionService was
reviewed for safety: it performs every deletion inside the context
and saves exactly once at the end, so a failed save leaves all
deletions pending for the caller's rollback — no partial deletion is
possible. Notification cancellation runs first and is deliberately
not transactional with the database: if the deletion then fails, the
pet still exists and its reminders are rebuilt by the next sync pass,
which is the safe direction.

## 3. CareHandoff petID association
`CareHandoff.petID: UUID?` added (optional, so existing records
migrate in place with nil — nothing is guessed). New handoffs from
the editor are associated with the selected pet's ID. Backup export
and restore carry petID; old backups without the key decode with
petID = nil (verified by test). Pet deletion removes ONLY
ID-matched handoffs — records are never deleted by petName, and
legacy unassociated handoffs are preserved.

## 4. Save-error handling, round 2
Every remaining user-initiated delete/save in the brief now uses
do/catch with rollback, no dismiss on failure, and a visible error:
medical record, vaccination, appointment, medication, care task and
feeding schedule deletions (their editors' existing error surfaces);
document deletion (detail screen stays open, "Delete failed" alert);
care handoff deletion and household member removal (Family screen
error alert); Settings changes — the reminders toggle reverts and
reports on failure, the legacy import reports failure instead of
success, and Delete All Data only cancels notifications AFTER a
successful save and reports failure with nothing removed.
Pet archive/restore is covered by §1.

## 5. Serialized notification synchronization
New `SyncCoordinator` (NotificationService.swift): passes submitted
while one is running are coalesced — only the latest queued pass runs
next — so two passes can never interleave their pending-request
cleanup and scheduling. The new central entry point
`NotificationService.synchronizeReminders(...)` runs the medication
pass first (7-day horizon, per-medication preferences, global
setting, pending-limit budget), then the one-off/refill rebuild, all
as one serialized pass. ContentView (launch + foreground), Settings
re-enable, and pet restoration all call this single entry point.
Both underlying passes gained completion callbacks to make the
serialization exact. No background execution is promised anywhere.

## 6. Tests
Preserved: 74 unit + 8 UI = 82. Added: 8 tests
(PetCare360V125Tests + PetCare360V125SyncTests) — free-limit restore
blocked, premium restore allowed, free restore with room allowed,
rollback-restores-pending-deletions (the mechanism the §2 failure
path relies on; a healthy in-memory store cannot be forced to fail
a save, so the forced-failure case is covered by construction, not
by a fake), handoff ID-vs-name deletion, old-backup handoff decode,
handoff petID backup round-trip, and SyncCoordinator
serialization/coalescing with a concurrency assertion.
Total written: 82 unit + 8 UI = 90. Executed: **0**.
Compilation UNVERIFIED (no Xcode here). Static suite: ALL PASS.

## 7. Configuration
Bundle ID com.petcare360.app, iOS 17.0, StoreKit IDs/prices, legal
URLs/email, CloudKit disabled — all preserved. No signing settings
exist or were touched; codemagic.yaml still does not exist.

## Files modified / added
PetsView.swift, PetDeletionService.swift (§1 service, §3 handoffs),
HouseholdModels.swift (petID), BackupService.swift (handoff petID),
CareView.swift (handoff association; medication/task/food deletion
errors), RecordsView.swift (record/vaccination/appointment/document
deletion errors), FamilyView.swift (handoff/member deletion errors,
Settings save handling, central sync call), ContentView.swift
(central sync), NotificationService.swift (SyncCoordinator, central
entry, completion callbacks), docs (this report, TEST_REPORT
addendum), project.pbxproj + scheme (regenerated; 1.2.5/build 8 +
new test file). ADDED: PetCare360Tests/PetCare360V125Tests.swift.
