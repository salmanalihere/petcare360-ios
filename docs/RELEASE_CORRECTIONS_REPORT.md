# PetCare 360 — Release-Critical Corrections (pre-Codemagic)

Date: 2026-11-06. Nothing uploaded to GitHub (private repo, no
credentials in this environment).

## 1. Final bundle identifier

**com.xenon-media.petcare360** — restored everywhere it is
configured:
- Xcode project (both configs): PRODUCT_BUNDLE_IDENTIFIER =
  com.xenon-media.petcare360; tests com.xenon-media.petcare360.tests;
  UI tests com.xenon-media.petcare360.uitests. The old
  com.petcare360.app no longer appears in the project file.
- The project generator (petcare-build) carries the same values, so
  regeneration cannot revert them.
- AppConfig.bundleID updated; the sync-coordinator queue label too.
- Info.plist is generated from these build settings, so it follows
  automatically. No new App Store Connect app was created and the
  app identity/version are untouched: version 1.2.8, build 11,
  deployment target iOS 17.0.

**StoreKit product IDs deliberately NOT changed:**
com.petcare360.premium.monthly / .yearly are App Store Connect
product identifiers in their own right — they are not the bundle
ID, and renaming them in code while the products exist under the
current IDs would break purchases. If the products registered
under the xenon-media app use different IDs, send them and they
will be updated in AppConfig + the .storekit file in one pass.

## 2. CloudKit configuration — restored

Why it was disabled: in v1.2.2 an audit found the app attempted a
CloudKit store automatically with a container whose Developer
setup could not be verified from the build environment, so sync
was gated off behind AppConfig.cloudKitSyncEnabled (with the
activation steps documented) rather than risk a store that failed
open on users' devices. It was a deliberate gate, not an accident.

Now restored, per the registered app:
- AppConfig.cloudKitSyncEnabled = true
- Container: iCloud.com.xenon-media.petcare360 (AppConfig +
  entitlements file, which declares the container + CloudKit
  service, now wired via CODE_SIGN_ENTITLEMENTS in both app
  configurations)
- PetCare360App.openStorage attempts the CloudKit private-database
  store first. Safety: if the container cannot be opened, it falls
  back to the local store, then to the storage-error screen — no
  crash, no silent data loss, no new database introduced. The
  SwiftData schema was re-scanned: every stored model property is
  optional or has a default (CloudKit-compatible); relationships
  are optional; no unique constraints.
- In-app wording that claimed "device only / no sync" was updated
  (Settings data text, household member explanation, premium
  upsell line) to describe private iCloud sync truthfully. Sharing
  with OTHER people's accounts is still not implemented (that
  needs CKShare, a separate feature) — records sync only across
  the owner's own devices on the same Apple ID.
- Backup/restore unchanged and fully compatible (local JSON,
  independent of the store backend).

EXACT REMAINING BLOCKERS (outside the code, cannot be verified
from here): (a) the Apple Developer App ID for
com.xenon-media.petcare360 must have the iCloud capability enabled
with container iCloud.com.xenon-media.petcare360 assigned;
(b) the provisioning profile used by the Codemagic Xenon signing
setup must include that capability/container — if it does not,
signing will reject the entitlements at archive time, which is
the correct failure (better than a silent no-sync build);
(c) STORE MIGRATION: turning CloudKit on changes the on-device
store location — export a full backup from the current build
BEFORE installing the first CloudKit build; if existing records
do not appear afterwards, Merge-restore that backup (documented
in docs/CLOUDKIT_SETUP.md). Also update the published privacy
policy if it states data never leaves the device.

## 3. New pet species

PetSpecies gained `reptile` ("Reptiles", SF Symbol "lizard") and
`horse` ("Horses", "horse"). Existing cases' raw values — the
stored identifiers in the database, backups and CloudKit — are
unchanged, so every existing record stays valid. Both appear
automatically in Add/Edit Pet (the picker iterates allCases),
avatars render from the species symbol everywhere PetAvatar is
used, backups round-trip both species (tested), CloudKit stores
the same speciesRaw string, and notification sounds now resolve:
reptile → petcare-reptile.wav, horse → petcare-horse.wav (the
files shipped in the previous build).

## 4. Regression verification

Full local suite re-run on the corrected tree (this environment
has no Xcode, so — as instructed — no release-readiness is claimed
from parsing alone):
- swiftc -parse 45/45 PASS; tree-sitter 45/45 PASS
- Per-struct alert/state sweep: ALL RESOLVE
- Project config: bundle IDs (above), entitlements plist valid +
  wired, version/build/target unchanged, StoreKit JSON intact,
  8 app icon sets valid, 7 sound files in bundle resources,
  pbx coverage of all 45 Swift files PASS
- Previous features re-checked in code: Home schedule + same-day
  appointment fix, appointment cancellation, vaccination and
  medication reminder gates, species/default sounds, alternate
  icons, premium prompts/paywall/entitlement, backup/restore —
  no changes were made to their logic in this round except the
  CloudKit wording updates noted above.
- Tests: 137 written (129 unit + 8 UI) including 7 new release
  tests (identity, CloudKit config, product-ID stability, species
  set/labels/icons, raw-value stability, sound mapping, backup
  round-trip). Executed: ZERO (no Xcode/StoreKit runtime here).

## 5. Build result

No Xcode archive was performed — this environment is Linux
without Xcode or the signing assets. The next Codemagic build
(with the Xenon signing integration, assuming its profile carries
the iCloud capability) is the first true compile + archive test.

## 6. Files changed

- PetCare360.xcodeproj/project.pbxproj (bundle IDs, entitlements)
- PetCare360/Services/AppConfig.swift (bundle ID, container, flag)
- PetCare360/PetCare360.entitlements (container ID)
- PetCare360/Services/NotificationService.swift (queue label)
- PetCare360/Services/NotificationSounds.swift (species mapping)
- PetCare360/Models/PetModels.swift (PetSpecies +2 cases)
- PetCare360/Features/FamilyView.swift (sync wording ×3)
- PetCare360Tests/PetCare360ReleaseTests.swift (NEW, 7 tests)
- docs/CLOUDKIT_SETUP.md, docs/STOREKIT_SETUP.md, docs/APP_STORE.md,
  README.md (identifier updates; dated version reports left as
  historical record), docs/RELEASE_CORRECTIONS_REPORT.md (this file)
- (Outside the ZIP) the project generator petcare-build/p2_pbx.py
  carries the same bundle IDs + entitlements wiring.
