# PetCare 360

**Tagline:** A healthier life together.

Premium native iOS app for pet health and daily care — SwiftUI, SwiftData,
StoreKit 2, Vision (on-device OCR), PDFKit, UserNotifications and Swift Charts.
iPhone only, iOS 17+, bundle ID placeholder `com.petcare360.app`.

## The five tabs
1. **Home** — greeting, pet summary, today's care progress, upcoming medication
   (overdue shown distinctly), next vet appointment, upcoming vaccinations,
   recent observations, latest care handoff, one-tap emergency access.
2. **Pets** — unlimited profiles with Premium (free plan: 1 pet): photo, species
   (dog/cat/bird/rabbit/other), breed, DOB with age calculation, gender, weight,
   color, microchip, adoption date, allergies, conditions, vet clinic, emergency
   contact, insurance info, notes. Edit, archive, delete.
3. **Care** — medication scheduling (once/twice/multiple daily, weekly, custom,
   temporary) with a shared administration log (Given / Skipped / Delayed, who +
   when) and **duplicate-administration prevention**; feeding schedules + fed
   logging; care tasks with assignment and completion; structured Care Handoffs.
4. **Records** — Medical Passport (chronological timeline, vaccinations,
   documents with originals preserved, selectable-category PDF export),
   appointments + Visit Preparation PDF, health timeline + Swift Charts weight
   history, expenses (Decimal-exact, PDF report), insurance organizer with claim
   statuses, FDA recall section (official source only — no invented recalls),
   lost-pet profile + poster PDF, on-device Vision document scanner with
   review-before-save.
5. **Family** — household members with roles (Owner / Family / Pet Sitter /
   Dog Walker / Viewer) and a permission matrix, invitations with temporary
   access expiry, handoff history, Emergency Mode + owner-controlled QR
   profile, Settings (reminders, JSON export/import, data deletion).

## Money & subscriptions
- StoreKit 2 only; entitlement comes solely from verified
  `Transaction.currentEntitlements`. No fake purchase states.
- Products: `com.petcare360.premium.monthly` — target $4.99/mo,
  `com.petcare360.premium.yearly` — target $29.99/yr. Live price is always read
  from StoreKit. Local `PetCare360.storekit` config is bound to the scheme.

## Privacy
- Data lives on-device in SwiftData; models are CloudKit-compatible so personal
  and shared household data can sync via the user's private iCloud once the
  iCloud container is enabled (see docs/ARCHITECTURE.md).
- `PrivacyInfo.xcprivacy`: no tracking, no collected data types.
- PetCare 360 is a record-keeping tool, not a veterinary diagnostic or
  treatment service.

## Before App Store submission (owner steps)
Phase 2 (1.2.0) added complete CRUD, the full medication editor, VisionKit camera scanning, wrapped/paginated PDFs, centralized premium gates, full backup/restore v2 and ID-based household identity — see docs/PHASE2_IMPLEMENTATION_REPORT.md.

See docs/APP_STORE.md and docs/TEST_REPORT.md — Xcode build, tests and StoreKit
sandbox can only run on a Mac.
