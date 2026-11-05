# PetCare 360 — v1.2.4 Correction Build (build 7)

Implements the independent review of v1.2.3, in its priority order.

## 1. Backup Merge is now per-record (was: whole-pet skip)
`BackupService.restore()` rewritten. Merge indexes existing pets,
households and policies by ID, then merges EVERY child collection by
record ID: medications, administrations, vaccinations, medical
records, documents, appointments, observations, expenses, food
schedules, household members and insurance claims. An existing pet
keeps its current profile fields; only records whose IDs are new are
inserted. The review's Bruno scenario (backup → add vaccination + 3
records → Merge) now imports the new records. Covered by a real
in-memory-container test (source/restore/re-export/merge, counts
asserted). The Settings import message now says records are kept
unchanged rather than "pets skipped". Replace behaviour unchanged.

## 2. Pet deletion is complete
New `PetDeletionService.deleteAllData`: cancels all of the pet's
notifications (dose + refill via medication prefixes; vaccination,
appointment, feeding AND insurance-renewal one-offs), then deletes the
petID-linked records that do NOT cascade — CareTasks, FeedingLogs,
InsurancePolicies (claims cascade from the policy), EmergencyProfiles
and MedicationSchedule preference records — then deletes the pet
(relationship children cascade). The deletion confirmation text is now
true. Also: ARCHIVING a pet cancels all its reminders, and RESTORING
an archived pet now checks the free 1-pet limit (closing the
archive/restore loophole) with a clear alert.

## 3. Notifications
- Feeding schedule deactivation (edit or create) cancels its daily
  notification; the create path now honours the Active toggle at all.
- Completed (or past) appointments never schedule a reminder — gated by
  `NotificationService.shouldScheduleAppointmentReminder`, also applied
  on edit (existing reminder cancelled).
- Foreground sync (launch + foreground + Settings re-enable) now
  rebuilds ALL reminder types, not only medication doses:
  `rebuildOneOffReminders` (feeding, vaccinations, future appointments,
  insurance) also re-arms REFILL reminders for medications at/below
  threshold, and the rebuild checks notification authorization itself.
- Medication editor race fixed: dose reminders are cancelled with a
  completion handler and the new reminders are scheduled only from that
  completion, so a late removal snapshot cannot delete fresh requests.
- The 7-day horizon is now explained in Settings, honestly: reminders
  are prepared a week at a time and refreshed when the app opens; iOS
  does not guarantee background refresh.

## 4. Documents are manageable
Documents list rows now open a Document Detail screen: the preserved
original (image preview, or PDF preview via PDFKit), this page's own
extracted text (text-selectable), share/export, and delete with
confirmation. Scanner fix: each saved page now stores ITS OWN OCR text
(previously the combined text was stored on every page); the combined
text remains only as a fallback for a page whose OCR was empty.

## 5. Household claims corrected
Roles are organisational, not access control — and the app now says so:
the Family screen section is "Roles on this device" with an explicit
caption (no separate accounts, no member sign-in, no lock-out on a
shared device), and the onboarding "Care together" page no longer
claims members "get the right access". (Genuine per-member enforcement
is impossible without accounts; the review's recommended wording route
was taken.)

## 6. Premium accuracy
- Paywall now lists only genuinely differentiated benefits
  (`PremiumFeature.paywallFeatures`): unlimited pets, household
  coordination, document scanning, expenses, insurance organiser,
  advanced charts, emergency QR, advanced PDFs, recall tracking.
  "Full medication history" and "Unlimited medical records" were
  removed from the paywall — they are not separately gated.
- Labels corrected: "AI document scanning" → "Document scanning
  (on-device OCR)"; "Recall notifications" → "Recall tracking & saved
  brands". StoreKit config descriptions updated to match ("medication
  tracking and history", "recall tracking"); IDs/prices unchanged.
- Recalls screen renamed "Recall Tracking" with explicit text that
  checks are manual and nothing is monitored automatically; the
  last-checked date now PERSISTS (@AppStorage) instead of resetting.

## 7. Emergency QR honesty
- The Photo field is removed from the QR field list — a text QR cannot
  carry a photo, so the toggle no longer pretends otherwise.
- "QR profile last updated" → "QR settings last saved" (the timestamp
  tracks settings saves, not pet-data changes).
- Revocation wording corrected: turning the profile off hides the code
  in the app; it cannot recall copies already photographed or printed,
  because the code contains the information itself.

## 8. Save-error handling
Every editor save path (pet, medication, care task, food schedule,
handoff, household member, medical record, vaccination, appointment,
observation, expense, insurance policy, claim, emergency QR setup,
document scanner) now uses do/catch: on failure the form STAYS OPEN
and shows "Your changes could not be saved on this device…" — never a
silent dismiss. Dose administration (Given/Skip/Delay) reports save
failure through its notice banner and does not record the dose.
Remaining `try?` saves are non-form actions (toggles, deletes inside
confirmed flows, settings switches).

## Tests
Preserved: 68 unit + 8 UI = 76. Added: 6 unit tests
(PetCare360V124Tests) running against real in-memory SwiftData
containers — per-record merge (the Bruno scenario), merge
no-duplication, complete pet deletion, appointment reminder gate,
QR field accuracy, paywall accuracy. Total written: 74 unit + 8 UI
= 82. Executed: **0**. Compilation UNVERIFIED (no Xcode here).
Static suite re-run on the final tree: ALL PASS.

## Files modified / added
BackupService.swift, PetCare360App.swift (unchanged), PetsView.swift,
CareView.swift, RecordsView.swift, FamilyView.swift, ContentView.swift,
NotificationService.swift, AppConfig.swift, PaywallView.swift,
OnboardingView.swift, DocumentScannerView.swift, FinanceModels.swift,
PetCare360.storekit, docs (this report, TEST_REPORT addendum,
STOREKIT_SETUP wording), project.pbxproj + scheme (regenerated:
1.2.4/build 7 + new files). ADDED: Services/PetDeletionService.swift,
Features: DocumentDetailView (in RecordsView.swift),
Tests/PetCare360V124Tests.swift.

## Configuration & remaining manual items
Bundle ID com.petcare360.app, iOS 17.0, StoreKit IDs/prices, legal
URLs/email, CloudKit disabled — all preserved. No signing settings
exist or were touched; codemagic.yaml still does not exist. Owner
items unchanged: App Store Connect products, signing team, first
Xcode build + Cmd+U, physical-iPhone camera test.
