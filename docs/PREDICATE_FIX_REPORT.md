# PetCare 360 — SwiftData #Predicate Capture Fix

Date: 2026-11-06. Targeted correction for the Codemagic
Xcode 26.6 predicate-macro compilation failure.

## Exact change (1 file, +1 line, 1 line modified)

PetCare360/Services/PetDeletionService.swift,
cancelAllReminders(for:in:):

- Added before the fetch: `let petID = pet.id`
- Predicate changed from `#Predicate { $0.petID == pet.id }`
  to `#Predicate { $0.petID == petID }`

The #Predicate macro cannot translate a member access on a
captured SwiftData model instance; capturing the UUID value
first is the supported pattern. A diff against the previous
package's file confirms these are the only changes to it.

## Project-wide predicate audit

Every #Predicate in the project was checked:
- PetDeletionService deletePet already captured `let petID`
  before its four fetches (InsurancePolicy, CareHandoff,
  EmergencyProfile, FeedingLog) — already correct, untouched.
- All remaining uses are @Query constant filters of the form
  `#Predicate<Pet> { !$0.isArchived }`, which capture nothing —
  safe, untouched.
- A pattern search for predicates comparing against a captured
  model's property now returns ZERO matches project-wide.

Behaviour preserved exactly: the same InsurancePolicy fetch runs
during pet archival/deletion reminder cancellation, the same
"ins-<uuid>" identifiers are collected and cancelled, and no
other deletion, archive or notification code changed. Bundle ID
com.xenon-media.petcare360, version 1.2.8 / build 11, iOS
platform settings and CloudKit configuration are untouched.

## Validation

- swiftc -parse on the changed file + full project: PASS
  (syntax only)
- Xcode build: NOT performed (no Xcode in this environment) and
  not claimed. The next Codemagic build verifies compilation.
