# PetCare 360 — v1.2.3 Reminder & StoreKit Audit (build 6)

## 1. Individual medication reminder preferences — fixed end-to-end
Previously `MedicationSchedule.reminderEnabled` was written only when a
medication was created, never loaded into the editor, never updated on
edit, and ignored by rolling replenishment. Now:
- The editor loads the medication's own preference
  (`NotificationService.isReminderEnabled`, default enabled when no
  schedule record exists) into the "Medication reminder" toggle.
- Saving creates-or-updates the MedicationSchedule with the toggle value
  for both new and existing medications.
- If the toggle is off at save, that medication's dose reminders are
  cancelled immediately (dose-only cancel; the separate refill supply
  alert is untouched). If on, its reminders re-arm (subject to the
  global setting, as before).
- `rescheduleAllMedicationReminders` now takes the schedules and
  schedules ONLY `eligibleReminders` — active medications on active
  pets whose individual preference is enabled. Global and per-medication
  settings are distinct and both respected.

## 2. Initial-launch replenishment — fixed
ContentView now runs the same idempotent `syncReminders()` pass from
`onAppear` (initial launch) and from scenePhase (foreground returns),
guarded by a one-time flag so the launch-time scenePhase event does not
run it twice back-to-back. Duplicate protection is structural: the pass
removes stale `pc360-med-*` requests first, and dose identifiers are
deterministic (`doseReminderID`), so any re-run replaces rather than
duplicates. Data comes from live @Query pets + schedules.

## 3. Global reminders re-enable — fixed
Settings toggle ON now: requests permission (user action only, as
before); if GRANTED, immediately rebuilds dose reminders via the shared
eligibility pass AND rebuilds the one-off types from current data
(`rebuildOneOffReminders`: active feeding schedules, vaccinations,
future appointments, insurance renewals — same deterministic IDs as
save-time scheduling, so no duplicates). If DENIED, an alert states
plainly that reminders cannot be delivered and offers an "Open iOS
Settings" route. Toggle OFF still cancels all pending notifications.

## 4. Household-sharing claims — removed from purchase surfaces
- `PetCare360.storekit` subscription description: "household sharing"
  → "household coordination and caregiver roles on this device".
  Product IDs and prices unchanged (verified: monthly $4.99, yearly
  $29.99, same IDs; JSON re-validated).
- `docs/STOREKIT_SETUP.md` premium list corrected the same way.
- `docs/APP_STORE.md` no longer suggests enabling iCloud/CloudKit for
  "sync + household sharing"; it now says NOT to enable it for this
  release and points to CLOUDKIT_SETUP.md.
- The in-app paywall label was already corrected in v1.2.2 and is now
  pinned by a test. (Two FamilyView strings that mention cross-device
  sharing do so to state it is NOT available — those are corrections,
  not claims.)

## 5. Documentation correction
`docs/V122_CORRECTIONS_REPORT.md` §1 rewritten: the v1.2.2 claim was
wrong because that report itself printed the incorrect hostname. The
literal incorrect hostname has been removed from the report and the
corrected accounting recorded there. Verified by project-wide search:
the literal incorrect hostname now remains ONLY in
`PetCare360V122Tests.testIncorrectLegalHostIsAbsent`, the guard
assertion. AppConfig legal URLs/email unchanged (salmanalihere.github.io
+ Salmanali929929@gmail.com).

## 6. Tests
Preserved: 59 unit + 8 UI = 67. Added: 9 unit tests
(PetCare360V123Tests) — reminder disabled / enabled / missing-schedule
default / per-medication independence / inactive exclusion /
deterministic identifiers (launch+foreground no-duplicate guarantee) /
shared toggle-rebuild eligibility / paywall-label accuracy / CloudKit
still disabled. Total written: 68 unit + 8 UI = 76.
Executed: **0** (no Xcode in this environment). Compilation UNVERIFIED.
Static suite re-run on the final tree: ALL PASS.

## 7. Files modified
NotificationService.swift, ContentView.swift, CareView.swift,
FamilyView.swift (+ UIKit import), PetCare360.storekit,
docs/STOREKIT_SETUP.md, docs/APP_STORE.md,
docs/V122_CORRECTIONS_REPORT.md, docs/TEST_REPORT.md,
project.pbxproj + scheme (regenerated; version 1.2.3 / build 6 + new
test file only). Added: PetCare360Tests/PetCare360V123Tests.swift,
this report.

## 8. Configuration & remaining manual items
Bundle ID, iOS 17.0 target, StoreKit IDs/prices, legal URLs/email and
CloudKit-disabled state all preserved; no signing settings exist or
were touched; codemagic.yaml still does not exist in this project and
was not modified. Remaining owner items unchanged: App Store Connect
products, signing team, first Xcode build + Cmd+U, physical-iPhone
camera test.
