# PetCare 360 — v1.2.2 Final Audit Corrections (build 5)

## 1. Legal URLs — corrected (mandatory)
The repository is `salmanalihere/petcare360-legal`. AppConfig now uses:
- Privacy: https://salmanalihere.github.io/petcare360-legal/privacy.html
- Terms: https://salmanalihere.github.io/petcare360-legal/terms.html
- Website: https://salmanalihere.github.io/petcare360-legal/
- Support: Salmanali929929@gmail.com (unchanged)
A project-wide search was run for the incorrect hostname (the owner's
name followed directly by ".github.io", without "here"). CORRECTION
(v1.2.3): the original version of this section claimed the string
survived only inside the new guard test — that was inaccurate, because
this report itself printed the hostname in that very sentence. The
literal incorrect hostname has now been removed from this report. As of
v1.2.3 the only place the literal string remains in the project is the
guard test that asserts its absence from the app's legal URLs
(PetCare360V122Tests.testIncorrectLegalHostIsAbsent).
`testLegalURLsUseHTTPSAndTheLegalHost` expects `salmanalihere.github.io`.

## 2. Medication reminder replenishment — fixed
- `NotificationService.rescheduleAllMedicationReminders` rebuilds the next
  7 days of medication reminders for every active medication, from the
  real dose slots (frequency, weekdays, start/end dates, multiple dose
  times all honoured via MedicationService.slots).
- It runs every time the app becomes active (ContentView scenePhase),
  alongside the existing entitlement refresh — no editor visit needed.
- It first removes all stale `pc360-med-*` requests, then schedules with
  a budget that respects the iOS ~64 pending-notification cap (60 kept
  for medication reminders after counting other pending requests).
- It does nothing when reminders are disabled, and checks notification
  authorization first: denied/not-determined means it silently skips —
  it never prompts (permission is requested only from the Settings
  toggle, as before).
- Inactive medications get no new reminders; deleted medications' were
  already removed at deletion, and the wholesale med-* cleanup catches
  any remainder.
- Background execution: deliberately NOT added. iOS background refresh
  is not guaranteed, and this build does not promise it; foreground
  replenishment on every app activation is the reliable mechanism.
  Practical horizon: reminders exist for 7 days past the last app open.

## 3. Refill notification cancellation — fixed
Refill reminders use the identifier `refill-<medicationID>` (pending:
`pc360-refill-<id>`), which the old dose-only prefix missed.
`NotificationService.medicationCancellationPrefixes` now returns BOTH
prefixes, and `cancelMedicationReminders` — used by medication deletion,
medication edit, and pet deletion — removes dose AND refill requests.
Covered by a dedicated unit test (§7 list).

## 4. CloudKit & household claims — corrected
- `AppConfig.cloudKitSyncEnabled` (default **false**) now gates the
  CloudKit configuration: the app opens the local store and does not
  activate CloudKit automatically. The entitlements file remains
  unwired, as before.
- UI text corrected (FamilyView + AppConfig):
  - The false claim "Household sharing syncs through your private iCloud
    … a pending member has no access until they accept" is REMOVED.
    The member form now states plainly: members are recorded on this
    device only, nothing is sent, nobody can accept or view anything,
    no data syncs between devices.
  - "Invite member" / "Invite Member" → "Add member" / "Add Member";
    "Invitation pending" → "Local record"; "Email for invitation" →
    "Email (for your records)"; premium blurb and Settings data text no
    longer mention iCloud sync; the paywall feature is renamed
    "Household coordination & caregiver roles".
- Local household functionality (members, roles, handoffs) is unchanged
  and still works. Genuine CKShare sharing remains a separate future
  phase — see docs/CLOUDKIT_SETUP.md.

## 5. ModelContainer failure handling — fixed
- The final `try!` in-memory fallback is REMOVED. `PetCare360App` now
  opens storage into a state: success → the app; failure → a
  `StorageErrorView` explaining that existing data has NOT been deleted,
  saving is unavailable until storage opens, with a **Try Again** button
  that re-attempts opening the same persistent store. The existing
  database file is never touched, moved or replaced on failure, and
  there is no launch crash.

## 6. Privacy & legal consistency
- In-app claims now match reality: local storage only, no sync claims,
  no sharing claims. PrivacyInfo.xcprivacy is unchanged and still
  accurate (no data collected by the developer; no third-party SDKs).
- If CloudKit is ever enabled in a future release, the published privacy
  policy must be updated BEFORE that submission (standing note in
  docs/CLOUDKIT_SETUP.md and docs/PRIVACY_POLICY.md).

## 7. Tests
Preserved: 52 unit (25 original + 19 Phase 2 + 8 final-fixes) + 8 UI.
Added (PetCare360V122Tests.swift, 7 tests): two rolling-window
replenishment tests (weekly med across both windows; end date inside
the second window), future-start-date window test, refill/dose
cancellation-prefix test, incorrect-legal-host guard, CloudKit-not-
auto-activated guard, storage-factory success test.
Total written: 59 unit + 8 UI = 67. Executed: **0** — no Xcode in this
environment; nothing is reported as passed. Static suite re-run on the
final tree: ALL PASS (31 Swift files, delimiter balance, pbxproj
coverage both ways, JSON/plist/XML parse, no TODOs, bundle/version/
product checks).

## 8. Configuration confirmations
Bundle `com.petcare360.app` unchanged; iOS 17.0 target unchanged;
StoreKit product IDs unchanged; no signing settings existed or were
added; `codemagic.yaml` — does not exist in this project and was not
created or modified; version bumped to 1.2.2 (build 5) for this
corrections release.

## 9. Files modified
AppConfig.swift, NotificationService.swift, ContentView.swift,
PetCare360App.swift (rewritten), FamilyView.swift,
PetCare360FinalFixesTests.swift (host expectation),
project.pbxproj + scheme (regenerated, version only + new test file),
docs/CLOUDKIT_SETUP.md, docs/TEST_REPORT.md.
Added: PetCare360Tests/PetCare360V122Tests.swift, this report.

## 10. Remaining manual items
Unchanged from 1.2.1: create the two App Store Connect products, set the
signing team, first Xcode build + Cmd+U (compilation is still
UNVERIFIED), physical-iPhone camera test, CloudKit activation only as a
separate approved phase.
