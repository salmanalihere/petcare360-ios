# PetCare 360 — v1.2.7 Final Minor Corrections (build 10)

## 1. Archived-pet insurance reminders
`rebuildOneOffRemindersAuthorized` now schedules insurance renewal
reminders through `NotificationService.eligibleInsurancePolicies`:
only policies whose petID belongs to a pet that exists and is NOT
archived. Eligibility is computed from current data on every rebuild,
so restoring a pet makes its policies eligible again automatically
on the next pass (launch/foreground/settings/restore all rebuild).
Deterministic identifiers (`ins-<policyID>`) unchanged.

## 2. Household privacy wording
FamilyView no longer claims sitters/walkers see only their role's
data. It now reads: "Roles help organise household responsibilities.
Everyone using this device may be able to access the information
stored in the app — roles are not separate accounts and do not
restrict access on this shared device."

## 3. RestoreSummary.skipped — complete accounting
Merge behaviour is unchanged; only the counting was completed.
`skipped` now counts existing records for ALL types: household
members, medications, administrations, vaccinations, medical
records, documents, appointments, observations, expenses, food
schedules, care tasks, care handoffs, feeding logs, insurance
policies (the policy itself) and their claims, emergency profiles,
saved brands, recall records and medication schedules — 19 counting
sites, each computed from the pre-merge ID sets of its own pass, so
newly inserted records are never miscounted as skipped (a counting
bug of exactly that kind in the first draft of this change was
caught and corrected before delivery). Replace restores still
report skipped = 0.

## Tests
Preserved: 90 unit + 8 UI = 98. Added: 3 tests
(PetCare360V127Tests) — insurance eligibility for active/archived/
orphaned policies, restored-pet eligibility, and a full round-trip
asserting skipped = 19 across every record type with inserted = 0
on an identical merge (and skipped = 0 on replace).
Total written: 93 unit + 8 UI = 101. Executed: **0**.

## Syntax verification (actual results)
swiftc -parse (official Swift 6.0.3): **37/37 PASS, 0 FAIL** —
re-run on the extracted ZIP as well.
tree-sitter Swift grammar: 37/37 PASS.
This is syntax verification only; Xcode compilation and test
execution remain unverified and are not claimed.

## Configuration
Version 1.2.7, build 10. Bundle ID com.petcare360.app, iOS 17.0,
StoreKit IDs/prices, legal configuration, CloudKit disabled — all
preserved. No signing settings exist or were touched;
codemagic.yaml still does not exist.

## Files modified
NotificationService.swift (insurance eligibility), FamilyView.swift
(wording), BackupService.swift (skipped accounting),
docs (this report, TEST_REPORT addendum), project.pbxproj + scheme
(regenerated; 1.2.7/build 10 + new test file).
ADDED: PetCare360Tests/PetCare360V127Tests.swift.
