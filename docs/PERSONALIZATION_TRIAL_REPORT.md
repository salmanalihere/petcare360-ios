# PetCare 360 — Personalization, Sounds & 7-Day Trial (2026-11-07)

Brief: owner-supplied icons and sounds, onboarding personalization,
reminders on by default, removal confirmation, Family & Care Team
redesign, Settings entries, and a 7-day free trial of all features.
Branch: `petcare360-personalization-trial` (from
`petcare360-clean-release` @ 5ec0f637). **Build number NOT
incremented — still 14, as instructed.** Nothing was submitted for
App Review; nothing was released.

## Trial architecture — the decision and its limits

Two architectures were evaluated, as the brief required:

- **StoreKit introductory offer** — attaches to a subscription
  purchase: the user must start a paid subscription (with a payment
  method on file) to receive the free period. It cannot start at
  first launch with no purchase, which the brief explicitly
  requires ("no purchase required"). NOT chosen.
- **App-managed trial (CHOSEN)** — a new `TrialManager`
  (`PetCare360/Services/TrialManager.swift`) records the first-launch
  date and unlocks every Premium feature for 7 days.

How it behaves, point by point against the brief:
- Starts at first launch (StoreManager initialisation), no purchase,
  no sign-up, no payment method.
- No popups or interruptions during the trial: feature gates read
  `StoreManager.hasPremiumAccess` (verified purchase OR active
  trial), so no premium prompt can appear while the trial is active.
- The Premium screen shows "Free trial — N days left" and the end
  date; Settings shows the same.
- On expiry, the subscription screen is presented once per launch
  (dismissible, locks nothing), offering Monthly $4.99 / Yearly
  $29.99 and Restore Purchases (product IDs unchanged).
- Data is never deleted; viewing, editing, exporting and deleting
  existing records are never gated (EntitlementPolicy downgrade
  safety unchanged). Only creating premium content re-locks.
- Trial authority is the **Keychain** (service
  `com.xenon-media.petcare360.trial`, ThisDeviceOnly accessibility),
  which survives delete-and-reinstall on the same device — the trial
  does NOT reset on reinstall. There is no UserDefaults-only flag
  and no hardcoded unlock; `EntitlementPolicy.hasAccess` is the
  single combination point, and `isPremium` remains purchase-only
  (the paywall's purchase completion still keys off verified
  StoreKit entitlement).

Stated limitations:
- A factory reset / erased device wipes the Keychain, so the trial
  can start again there. No on-device store can prevent that.
- A different device has no record and starts its own trial.
- The trial clock is the device clock; setting the clock backwards
  can stretch remaining time. The stored start date can never be
  overwritten once written (beginIfNeeded is idempotent, verified
  by test).

## What changed in code

New files:
- `PetCare360/Services/TrialManager.swift` — trial state machine
  (notStarted / active(daysRemaining, endsAt) / expired) over an
  injectable date store + clock.
- `PetCare360/Features/PersonalizationViews.swift` — shared sound
  choice list with previews; Settings destinations (Notification
  Sound, App Icon, Reminder Preferences with an honest iOS-permission
  check); onboarding icon page and sound+permission page.
- `PetCare360Tests/PetCare360TrialTests.swift` — 9 test methods:
  trial start/countdown/exact 7-day expiry/no-reset-on-reinstall/
  stays-expired, purchase∨trial access matrix, icon-option↔asset
  integrity, owner sound set + stale "reptile" selection fallback,
  reminders-on default for new profiles.

Modified:
- `NotificationSounds.swift` — `PetSoundKind.reptile` removed;
  reptiles resolve to the iOS system default (nil) while animal
  sounds are on; labels now name the owner's recordings factually;
  header documents provenance. A stale stored "reptile" default
  selection falls back to the chime.
- `StoreManager.swift` — owns the TrialManager, forwards its change
  notifications, refreshes trial state with entitlement refreshes.
- `AppConfig.swift` — `EntitlementPolicy.hasAccess(isPremium:trialActive:)`.
- Gate sweep (feature gates only, to `hasPremiumAccess`): PetsView
  5 sites, RecordsView 11 sites, FamilyView/CareTeam 5 sites.
  PaywallView's purchase-completion handler still uses `isPremium`.
- `PetModels.swift` — `UserProfile.remindersEnabled` defaults to
  true for NEW profiles (existing profiles untouched).
- `OnboardingView.swift` — two personalization pages appended
  (icon, then sound + notification permission + name + Get Started);
  Skip still finishes from any page; reminder page copy updated to
  match reminders-on-by-default.
- `FamilyView.swift` — redesigned as Family & Care Team (see below);
  Settings gained Premium + Personalize & Family sections.
- `PaywallView.swift` — trial-active banner (days remaining, end
  date) and trial-expired banner (data-safe wording).
- `ContentView.swift` — presents the paywall once per launch when
  the trial has expired and there is no purchase.
- `PetCare360ReleaseTests.swift` — reptile sound expectations
  updated to the new owner-directed behaviour.
- `project.pbxproj` — regenerated (new files in, petcare-reptile.wav
  out); **CURRENT_PROJECT_VERSION still 14**, version 1.2.8,
  entitlements wiring and INCLUDE_ALL_APPICON_ASSETS preserved.

Family & Care Team redesign:
- Title "Family & Care Team", subtitle "Manage everyone who helps
  care for your pets."
- Owner card section; "Your Care Team" cards with human-readable
  role descriptions; prominent bordered "Add Caregiver" button
  (same premium gate + resume-after-purchase as before).
- Removal now asks first, with the brief's exact copy:
  title "Remove Family Member?", message "Are you sure you want to
  remove [Name] from your household? They will no longer be listed
  as a household caregiver on this device.", buttons Cancel /
  Remove Member. Nothing is deleted until Remove Member is tapped.
- Roles & Permissions is now a separate screen (plain-language
  permissions per role); a compact "Shared device" card replaces
  the long inline explanation. Models, persistence, the permission
  matrix, handoffs, sheets and navigation are unchanged.
- Honest scope kept: members are local records on this device.
  There are no accounts, invites or cross-device sharing — a
  two-device family test cannot pass on this architecture.

Settings entries (all functional, none decorative): Premium
Subscription (paywall), Restore Purchases (with result messages),
Change App Icon, Change Notification Sound, Reminder Preferences,
Family & Care Team, Roles & Permissions — in addition to the
pre-existing inline Reminders / sound / icon controls.

## Assets

Reused exactly as supplied by the owner:
- Icons: default_icon.png + pet_dog/cat/bird/rabbit/reptiles/
  horses/other.png → the 8 appiconsets (1024×1024) and 8 preview
  imagesets. Pet artwork was 512×512 and was upscaled to 1024×1024
  (Lanczos) — a faithful reproduction, no redesign.
- Sounds: dog/cat/bird/rabbit/hourse[sic] MP3s → WAV (22050 Hz
  mono 16-bit) because iOS notification sounds require WAV/AIFF/CAF;
  durations preserved (1.03/2.04/2.53/4.65/2.52 s). Conversion is a
  format change only — the recordings are the owner's.

Missing assets (nothing substituted, per instruction):
- No reptile sound was supplied — by the owner's instruction
  reptiles use the iOS system default sound.
- No "other" sound was supplied — Other pets use the user's chosen
  default sound.
- `petcare-chime.wav` (the app's neutral default, synthesized
  earlier, not an animal sound) is retained as a selectable default.

## App Store Connect

- Subscription group "PetCare 360 Premium" and both products
  already existed and were verified field by field: Monthly
  com.petcare360.premium.monthly $4.99, Yearly
  com.petcare360.premium.yearly $29.99, 175-country pricing, no
  offers, both "Prepare for Submission".
- The brief's descriptions exceed Apple's 55-character limit for
  subscription descriptions (99 and 111 characters). The owner
  approved shortened wording on 2026-11-07: Monthly "Unlock
  unlimited pets, family care & all features", Yearly "One year of
  Premium: unlimited pets, all features" (49 characters each), and
  setting availability to all countries for both products was
  actioned in the same session.
- Sandbox testers: still none — creating one needs a fresh email
  address that is not an Apple ID, from the owner.

## Verification (honest status)

- Static only: swiftc -parse 52/52 files PASS; tree-sitter parse
  52/52 PASS. Parse is syntax, NOT compilation.
- Tests: 9 new methods written + 1 updated; like all PetCare 360
  tests, ZERO were executed here (no Xcode on this machine).
- Package verified from the extracted ZIP (build 14, new files
  present, reptile WAV absent, gate sweep present).
- NOT done / still needs a Mac + device: Xcode build, test run,
  Codemagic build, on-device checks of icon switching, sound
  previews and delivery, permission flow, trial countdown display,
  and the removal dialog. Shipping this needs a build-number bump
  to 15 — not done, per instruction to report first.
- Preserved safeguards: local storage fallback untouched; no
  CloudKit schema change; no relationship-optionality change; no
  data deletion; product IDs and prices unchanged; no new
  third-party dependencies; tab structure unchanged.

## GitHub note

Text changes are pushed to `petcare360-personalization-trial`.
Binary files cannot travel through the push tool and must be
committed with GitHub Desktop (they are also in the ZIP):
8 appiconset PNGs, 8 preview PNGs, 5 WAV files
(petcare-dog/cat/bird/rabbit/horse.wav), and the deletion of
petcare-reptile.wav. Do not merge to `petcare360-clean-release`
without the owner's approval.

---

# Review addendum (2026-11-07, owner's pre-Build-15 review)

## 1. Existing-user migration policy (FIXED)
Problem confirmed: the first version started a trial for ANY
install with no Keychain date — including existing users upgrading
from build 14, who would silently have received a fresh trial.
Policy implemented: the trial is for new users of this build.
- StoreManager no longer begins the trial at init.
- ContentView resolves the trial exactly once, when it can read the
  store: if a UserProfile already exists, the install is an
  upgrading existing user → a migration sentinel (1970-01-01) is
  recorded in the Keychain and the state is `.notApplicable` — no
  trial starts, no "trial ended" UI ever shows for them, and the
  trial-expired paywall never appears. A failed store read defers
  the decision to the next foreground return instead of guessing.
- If no profile exists → the trial begins (genuine new install).
- A recorded decision is never re-decided (tests cover relaunch,
  reinstall ordering, and trial-started-then-data-exists).
- Purchases and data are untouched: resolution only counts
  profiles; entitlement still comes solely from verified StoreKit
  transactions.

## 2. Keychain failure handling (FIXED)
- `TrialDateStore.saveStartDate` now returns Bool; the Keychain
  store returns the real SecItem status.
- `beginIfNeeded()` activates the trial ONLY after the start date
  is written AND read back (≤1s tolerance). On failure: state stays
  `.notStarted`, `persistenceFailed` is raised — no phantom trial.
- Tests with an injectable failing store cover write failure,
  read-back failure, and migration with a failing store.

## 3. Exactly what happens after day 7
- The trial state becomes .expired. Once per launch, the
  subscription screen is presented (dismissible — the free plan
  keeps working underneath; during the trial nothing was shown).
- NEVER gated (before, during, after the trial): viewing, editing
  and deleting every existing record; medication logging and
  history; care tasks and handoffs; feeding logs; the emergency
  screen; the full JSON backup export in Settings; all reminders.
- Premium-only again (creation / premium workflows only): adding a
  pet beyond the 1 free profile; restoring an archived pet beyond
  the free limit; adding a caregiver; document scanning (new
  scans); filing insurance claims and adding policies; adding an
  expense; saving recall brands; advanced health charts (the
  underlying weight history itself stays fully visible — only the
  chart rendering is Premium, as designed in v1.2.4); Emergency QR
  setup; two branded PDF exports (Visit Preparation PDF, Expense
  Report PDF) — these two were Premium features long before the
  trial existed; the free JSON backup export is unaffected. If the
  owner wants those PDFs free, that is a product decision to make
  explicitly — it was NOT changed here.
- Nothing is deleted at expiry; subscribing (Monthly $4.99 /
  Yearly $29.99) or restoring a purchase reopens everything
  immediately.

## 4. Icon verification (against the owner's original files)
Pixel comparison of each packaged 1024×1024 app icon against the
supplied originals (pet artwork composited on white, compared at
512×512): mean absolute error 0.22–0.34 out of 255 for all seven
pet icons — resampling noise only; the artwork is the owner's,
unmodified. The default icon is a PIXEL-EXACT downscale (MAE 0.0)
of default_icon.png composited on its own green. Registration:
every appiconset has a Contents.json naming its 1024 PNG;
ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = YES is set, so
Xcode generates CFBundleAlternateIcons from the 7 alternate
appiconsets; AppIconOption alternate names match the appiconset
names exactly (test-covered). Final confirmation inside a SIGNED
app requires the actool asset compilation in a real build
(Codemagic/device checklist below) — it cannot be inspected from
source alone, and is not claimed here.

## 5. Audio verification
All six WAVs are in the target's Resources phase of the pbxproj
(bundle root, where UNNotificationSound looks): petcare-dog/cat/
bird/rabbit/horse.wav + petcare-chime.wav. Durations match the
owner's MP3 originals to <0.02s (1.03/2.04/2.53/4.65/2.52s; chime
0.95s); all 22050 Hz mono 16-bit WAV, far under the 30s limit.
Mapping: dog/cat/bird/rabbit/horse → their recordings; reptile →
nil → UNNotificationSound .default (iOS system default), verified
in NotificationService (two scheduling sites pass the resolved
filename as UNNotificationSoundName, nil → .default); "other" →
the user's chosen default. Filenames are produced by
PetSoundKind.fileName ("petcare-<kind>.wav") — the same names the
scheduler resolves (test-covered, incl. bundle presence).

## 6. Tests
No Codemagic workflow ran the full suite (petcare360-ios builds
only; the diagnostics workflow runs selected storage tests). A new
workflow `petcare360-full-tests` was ADDED to codemagic.yaml on
this branch only: build-for-testing + test-without-building with
NO -only-testing filter, full log + xcresult as artifacts, and a
summary step quoting the real "Executed N tests" lines. It must be
run from Codemagic on this branch; NO test result is reported here
— the suite (now 17 trial tests incl. migration + Keychain-failure
coverage, plus all pre-existing suites) remains WRITTEN, NOT
EXECUTED, until that log exists.

## 7. Release safety (verified)
- localConfiguration keeps cloudKitDatabase: .none at both call
  sites (PetCare360App.swift lines 58/60); openStorage ladder
  unchanged.
- No CloudKit relationship or schema change: HouseholdModels.swift
  is byte-identical to petcare360-clean-release; the only model
  change in this whole feature is the remindersEnabled DEFAULT for
  new profiles (a default, not a relationship or schema change).
- StoreKit verification untouched (checkVerified gates purchase,
  entitlement refresh and transaction updates exactly as before).
- petcare360-clean-release untouched; nothing merged; build number
  still 14; Build 15 not started.

## 8. Reptile sound rule — correction (2026-11-07 review)
The owner clarified: reptiles must ALWAYS use the iOS system
default sound, regardless of the animal-sounds toggle or the
selected default sound. The first version returned nil only when
animal sounds were enabled; with them disabled, a reptile reminder
could fall through to the selected default. Fixed:
`resolvedFileName` now returns nil for `.reptile` FIRST, before
every other rule. All scheduling paths use this one function, so
no other notification behaviour changed. Coverage:
`testReptilesAlwaysUseSystemDefaultSound` checks the full matrix
(animal on/off × chime/cat/dog/system selections → always nil)
plus control cases proving dog/horse/other resolution is
unchanged; the older contradicting assertion in
`testNewSpeciesSelectTheirSounds` was corrected. (The audio
section above is superseded on this one point: "animal sounds
off → default applies" no longer holds for reptiles.)
