# Architecture

- **UI:** SwiftUI, 5-tab TabView (Home / Pets / Care / Records / Family),
  centralized design system in `DesignSystem/Theme.swift` using the exact
  master-prompt palette (Deep Teal #123C3A, Fresh Green #218A77, Warm Ivory
  #F5F4EF, Card White #FFFFFF, Soft Peach #E6A56C, Charcoal #253431,
  Secondary #788681, Amber #D99A36, Red #D85B5B). Light + dark mode, Dynamic
  Type and VoiceOver labels throughout.
- **Data:** SwiftData `@Model` types, one file per domain (Pet, Medication,
  Health, Household, Finance). All properties have defaults and relationships
  are optional, which keeps the schema **CloudKit-compatible**: enable the
  iCloud container + CloudKit in Signing & Capabilities and the same models
  sync; household sharing then maps to CloudKit sharing with the app's role
  matrix (`HouseholdPermissions`) enforced in the service layer. The local
  store remains the source of truth (offline-first); duplicate medication
  administration is prevented by the slot key (medication + day + minutes +
  status `given`) regardless of sync order.
- **Services:** StoreManager (StoreKit 2), MedicationService (pure scheduling
  + duplicate logic, unit-tested), NotificationService (local notifications,
  deterministic `pc360-` identifiers, authorization requested only when the
  user enables reminders), FinancialCalculationService (single Decimal totals
  definition for UI + PDF), VisionDocumentScanner + DocumentTextParser
  (on-device OCR behind the `DocumentScanning` protocol — no external AI is
  required; a future external extractor can plug into the same protocol),
  PDFService (Medical Passport, expense report, visit preparation, lost-pet
  poster), BackupService (validate-before-insert JSON export/import),
  EmergencyService (owner-gated QR payload + CoreImage QR generation).
- **No third-party dependencies.**

## Phase 2 additions (1.2.0)
- **Identity:** household roles resolve from `UserProfile.memberID`, linked
  to the owner `HouseholdMember.id` at onboarding (`HouseholdIdentity`).
  Display names are presentation only. Sharing is still LOCAL: SwiftData is
  not synchronised between devices. Cross-device household sharing requires
  CloudKit sharing with the owner's own iCloud container (Signing &
  Capabilities → iCloud → CloudKit, plus a CKShare flow) — not implemented
  and not simulated.
- **Backup v2:** `BackupService` exports/imports every user-data model with
  preserved IDs; restore strategies Merge (skip existing IDs) and Replace;
  decode validates the entire file (including duplicate IDs) before any
  insert, and a failed save rolls back.
- **PDFs:** `PDFService` lays out wrapped text with exact pagination and
  numbered, dated pages.
- **Scanner:** VisionKit camera (multi-page) + photo library; Vision OCR
  on-device; review-before-save; one stored document per page.
- **Entitlements:** `EntitlementPolicy` is the single gate reference;
  creation and premium workflows are gated, existing-data access never is.
