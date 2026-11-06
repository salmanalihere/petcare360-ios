# PetCare 360 — Build Number Bump for Next Upload

Date: 2026-11-06. Single-purpose change for the next
App Store Connect / TestFlight upload.

## Exact change

- CURRENT_PROJECT_VERSION: 11 → 12, in the PetCare360 app
  target's Debug and Release configurations ONLY (project.pbxproj
  lines 200 and 223). A diff against the previous package's
  project.pbxproj shows these two lines are the ONLY difference.
- The project generator was updated to match, so regeneration
  keeps build 12.

## Verified final settings

- MARKETING_VERSION = 1.2.8 (unchanged, both configurations)
- CURRENT_PROJECT_VERSION = 12 (both app configurations; the
  test targets carry no CURRENT_PROJECT_VERSION of their own)
- PRODUCT_BUNDLE_IDENTIFIER = com.xenon-media.petcare360;
  tests com.xenon-media.petcare360.tests and
  com.xenon-media.petcare360.uitests — all unchanged
- CFBundleVersion: the project generates its Info.plist
  (GENERATE_INFOPLIST_FILE = YES) with no override, so the
  generated CFBundleVersion resolves to
  $(CURRENT_PROJECT_VERSION) = 12. (Build Settings in Xcode
  will show Version 1.2.8 / Build 12.)
- Untouched, per instruction: functionality, UI, assets,
  entitlements (CloudKit container
  iCloud.com.xenon-media.petcare360), platform settings
  (SDKROOT/SUPPORTED_PLATFORMS), notification code, and every
  other project setting. The Codemagic workflow lives outside
  this package (in the repo) and was not modified.

## Validation

- project.pbxproj greps + diff as above
- swiftc -parse full project: 45/45 PASS (syntax only)
- Xcode build: NOT performed (no Xcode here), not claimed.
