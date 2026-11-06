# PetCare 360 — Xcode Platform Configuration Fix

Date: 2026-11-06. For the Codemagic exit-code-70 failure
("scheme has only macOS destinations — no iOS Simulator").

## Root cause

The generated project never declared SDKROOT or
SUPPORTED_PLATFORMS anywhere. IPHONEOS_DEPLOYMENT_TARGET alone
does not pin a target's platform, so Xcode inferred the available
destinations from the generic .app product and offered only Mac
destinations (My Mac / Any Mac). The project was never a Mac or
Catalyst project — there are no macosx or Catalyst settings in
it — it was an under-specified iOS project.

## Exactly what changed (project.pbxproj only)

Added to the `common` settings block, which feeds the project
configurations AND the Debug + Release configurations of all
three targets (app, unit tests, UI tests) — 8 configuration
blocks in total:

- SDKROOT = iphoneos;
- SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";

Already present and re-verified in the PetCare360 app target's
Debug and Release configurations:
- IPHONEOS_DEPLOYMENT_TARGET = 17.0;
- TARGETED_DEVICE_FAMILY = 1;

A diff against the previous package's project.pbxproj shows the
ONLY changes are the added SDKROOT / SUPPORTED_PLATFORMS lines —
no other setting was touched. The project generator
(petcare-build) carries the same fix, so regeneration cannot
revert it.

## Scheme check

PetCare360.xcscheme parses as valid XML and its
BuildableReferences point at the correct targets: PetCare360.app
(BlueprintName PetCare360), PetCare360Tests.xctest,
PetCare360UITests.xctest. The TestAction, LaunchAction and
ProfileAction all reference the iOS app target. No scheme change
was needed — the missing platform declaration in the project was
the entire defect.

## Preserved (verified in the corrected project)

- Bundle ID com.xenon-media.petcare360 (tests/uitests suffixed)
- Version 1.2.8, build 11, deployment target iOS 17.0
- CODE_SIGN_ENTITLEMENTS = PetCare360/PetCare360.entitlements,
  container iCloud.com.xenon-media.petcare360, CloudKit enabled
- All 45 Swift files, assets, sounds, app icons, StoreKit config

## Validation performed here

- project.pbxproj structure: brace/paren balance PASS; targeted
  greps confirm all four platform settings in the app target's
  Debug and Release blocks
- Scheme XML: valid, correct references
- swiftc -parse 45/45 PASS (syntax only)

## NOT done (stated plainly)

Xcode is not available in this environment (Linux, no Xcode), so
`xcodebuild -list` could NOT be run and NO build is claimed. The
next Codemagic run is the verification: with SDKROOT=iphoneos and
SUPPORTED_PLATFORMS="iphoneos iphonesimulator" now explicit, the
scheme should offer iOS Simulator destinations and the exit-70
failure should be resolved. If Codemagic still reports Mac-only
destinations after this package, the remaining suspect would be
the workflow's own destination flag (-destination) rather than
the project.
