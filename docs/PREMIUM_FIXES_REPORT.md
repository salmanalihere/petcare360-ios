# PetCare 360 — Premium Purchase, Upgrade Flow & Onboarding Fixes

Date: 2026-11-06. Version/build unchanged: 1.2.8 (11), per brief.
Nothing uploaded to GitHub (repository is private; no credentials in
this environment) — the corrected tree is packaged for review/upload.

## 1. Root cause of the "Trying Again" paywall

Two layers:

**External (most likely trigger):** `Product.products(for:)` does
NOT throw when the requested IDs are unavailable — it returns an
empty array. Products are unavailable when they do not exist in App
Store Connect for this bundle ID, the Paid Apps agreement is not
active, or a build runs without a StoreKit configuration and without
live products (a TestFlight build has no .storekit file — it reads
App Store Connect). The two product IDs in the app and the local
.storekit file match exactly (`com.petcare360.premium.monthly`
$4.99, `com.petcare360.premium.yearly` $29.99) — the code was asking
for the right products.

**Code (turned it into a dead end):** the old paywall treated
"empty result" and "load error" as the same state — a text line and
a "Try Again" button, forever, with no distinction, no loading
state separation, and the load error stored in the same field as
purchase errors. Retrying could never succeed while the products
were unavailable, and the screen never explained why.

**Fixes in StoreManager + PaywallView:**
- Distinct, derivable paywall states (`PaywallDisplayState`):
  loading ("Loading membership plans…" + spinner), content (real
  products), empty (load finished, Apple returned nothing — honest
  explanation + Retry), failed (the error message + Retry).
- `loadError` is now separate from `purchaseError`; both are cleared
  when a new attempt starts. `hasAttemptedLoad` distinguishes
  "never loaded" from "loaded empty".
- Purchase returns a Bool that is true ONLY when a verified
  transaction left an active entitlement; pending purchases show an
  explanation; cancelled purchases change nothing; unverified
  results never unlock anything. Restore reports honestly when no
  active subscription is found for the Apple ID.
- New headline: "Unlock More. Care Better. Love More." Cards show
  each product's real localized price and its real billing period
  read from the product's subscription data; the yearly "Save X%"
  badge is computed from the two real prices (at the configured
  prices: 50%) and appears only when a real saving exists. CTA is
  "Go Premium"; renewal disclosure uses the selected product's live
  price/period. The hardcoded "Target US prices" line was removed.
- On purchase success the paywall dismisses itself and the screen
  that opened it resumes the user's original action (below).

**Still required outside the code (owner, App Store Connect):**
create the two subscription products with EXACTLY the IDs above in
the app's subscription group, set prices ($4.99 / $29.99) and
localizations, and ensure the Paid Apps agreement is active. Until
then, TestFlight builds will show the new honest "not available"
state instead of plans — no code can sell products that do not
exist in App Store Connect. In Xcode, run the PetCare360 scheme
(its StoreKit configuration file is attached) to test purchases
locally with the sandbox.

## 2. Premium upgrade prompts (no OK-only popups remain)

New reusable component `PremiumPrompt` + `premiumUpgradePrompt`
modifier (Features/PremiumPrompt.swift): feature-specific title and
explanation, a prominent "Upgrade to Premium" button that opens the
paywall, and "Not Now" that closes it and changes nothing. Applied
at every gate:
- PetsView: add pet ("Unlock More for Your Pets!" — the brief's
  exact example copy) and restore archived pet; after a successful
  purchase the pet editor opens / the restore retries automatically.
- PetDetailView: restore-limit alert now has Upgrade / Not Now;
  restore retries after purchase.
- FamilyView: Add member prompts first (was: straight to paywall),
  and the member editor opens automatically after purchase.
- DocumentsView: scanning prompt; the Scan button itself becomes
  available the moment Premium activates.
- AppointmentsView: visit-preparation PDF prompt (PDF button
  appears automatically once Premium is active).
- ExpensesView: add-expense prompt resumes into the expense editor;
  report-PDF prompt (button swaps in automatically).
- InsuranceView: add-policy prompt resumes into the policy editor;
  add-claim prompt resumes into the claim editor for that policy.
- RecallsView: saved-brand prompt; the brand add retries itself
  after purchase.
Verified: zero `.alert("Premium", …)` OK-only alerts remain.

## 3. Entitlement audit

Unchanged source of truth, re-verified: Premium = a verified
transaction for one of the two product IDs in
`Transaction.currentEntitlements`, revocation dates honoured,
refreshed at launch, on foreground (ContentView scenePhase), after
every purchase/restore, and continuously via Transaction.updates.
All screens read the same `StoreManager.isPremium` /
EntitlementPolicy. Free-plan limits still enforced by the same
policy checks. Nothing was bypassed; no fake unlock exists.

## 4. Onboarding

TabView pages now use `.page(indexDisplayMode: .always)` (dots
always visible); every non-final page shows a "Swipe to explore →"
hint (arrow label) and a Next button; a Skip button sits top-right
on every page and the final page keeps its name field + Get
Started. Skip uses the same all-or-nothing creation path as Get
Started with the default name "Owner" — the app requires a profile
and household to exist, so skipping sets those up with defaults and
marks onboarding complete (hasCompletedOnboarding), so the tutorial
never repeats. A save failure still shows the error and completes
nothing.

## 5. App icon — BLOCKED on the image file

"Happy Pet Care Companions.png" did not arrive in this workspace
(no attachment is present in the project folders). The current
AppIcon.appiconset configuration is valid (single 1024×1024 RGB
PNG, correctly referenced), so the replacement is ready to execute
the moment the image is re-attached: the artwork will be adapted
full-bleed (green extended to the edges, no white margin, no alpha,
subjects inside the safe area) and verified at 1024×1024 RGB
no-alpha before packaging.

## 6. Tests

Added PetCare360PremiumTests (10 methods): paywall state derivation
(6 cases incl. the empty-result case that caused the bug), savings
maths at the configured prices (50%) and no-saving cases, prompt
copy completeness, StoreManager initial state. Total unit tests:
108 + 8 UI = 116 written. Executed: ZERO — no Xcode/StoreKit
runtime exists in this environment; sandbox purchase, restore and
entitlement tests require the scheme's StoreKit configuration in
Xcode or a TestFlight build after the App Store Connect products
exist. Verification performed here: swiftc -parse 40/40 PASS,
tree-sitter 40/40 PASS, extended per-struct state sweep ALL
RESOLVE, project/StoreKit/scheme/privacy configuration checks PASS.

## 7. Files changed

- PetCare360/Services/StoreManager.swift (load/purchase/restore states)
- PetCare360/Features/PaywallView.swift (rewritten states + design)
- PetCare360/Features/PremiumPrompt.swift (NEW)
- PetCare360/Features/PetsView.swift (prompts + resume, list & detail)
- PetCare360/Features/RecordsView.swift (5 gated views converted)
- PetCare360/Features/FamilyView.swift (member prompt + resume)
- PetCare360/Features/OnboardingView.swift (Skip/Next/hint/dots)
- PetCare360Tests/PetCare360PremiumTests.swift (NEW, 10 tests)
- PetCare360.xcodeproj/project.pbxproj (regenerated for the 2 new files; version 1.2.8 build 11 unchanged)
- docs/PREMIUM_FIXES_REPORT.md (this file), docs/TEST_REPORT.md (addendum)
