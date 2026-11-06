# PetCare 360 — App Store Icon Validation Fix (errors 90713 / 90022)

Date: 2026-11-06. Codemagic build 8 upload errors.

## Root cause

AppIcon.appiconset/Contents.json declared the marketing icon as
idiom "iphone", scale "1x", size "1024x1024". That is not a valid
app-icon declaration: with it, actool does not process the icon
set as the app icon — the generated Info.plist gets no
CFBundleIconName (error 90713) and no derived iPhone icon sizes
are produced (error 90022, the missing 120x120). One malformed
declaration caused both errors.

## Exact changes

1. All 8 appiconset Contents.json files (AppIcon + the 7
   alternates) rewritten to the modern single-size format,
   filenames unchanged:
   {"images": [{"filename": "<existing>-1024.png",
                 "idiom": "universal", "platform": "ios",
                 "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}}
   The primary set is the required fix; the alternates were
   aligned to the same format so the whole catalog is uniform.
2. project.pbxproj: INFOPLIST_KEY_CFBundleIconName = AppIcon
   added to the app target's Debug and Release configurations
   ONLY (exactly 2 occurrences; test targets do not have it —
   a diff vs the previous package shows these 2 added lines are
   the only project change). Together with the existing
   ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon and
   GENERATE_INFOPLIST_FILE = YES, the generated Info.plist now
   contains CFBundleIconName = AppIcon.
3. The artwork itself is untouched: AppIcon-1024.png is the same
   file (1024x1024, opaque RGB — re-verified programmatically,
   as were all 7 alternates). No manual 120x120 image was added:
   with a valid universal 1024 declaration, actool derives the
   required iPhone sizes (including 120x120) at compile time,
   which is the supported mechanism.

## About scripts/generate_app_icon.sh

That script is NOT part of the project package in this
environment (no scripts/ folder exists here) — it lives on the
Codemagic/repo side, like codemagic.yaml, so it could not be run
or inspected from here. What this package guarantees: the correct
PNG already sits inside AppIcon.appiconset with the exact
filename Contents.json references, at 1024x1024 opaque RGB. If
the script regenerates/overwrites that PNG before the build, its
output must meet the same spec (1024x1024, NO alpha channel) —
an RGBA output would reintroduce upload errors. Share the script
and it will be checked line by line.

## Preserved (verified)

Bundle com.xenon-media.petcare360 (+ test suffixes) unchanged;
MARKETING_VERSION 1.2.8; CURRENT_PROJECT_VERSION 12 (kept for
this retry); SDKROOT/SUPPORTED_PLATFORMS platform settings;
CloudKit entitlements + container; predicate fix; notification
sound fix; all functionality, UI and other assets.

## Validation performed here

- All 8 Contents.json parse and match the required schema;
  every referenced PNG exists, 1024x1024, RGB, no alpha.
- project.pbxproj: INFOPLIST_KEY_CFBundleIconName present x2
  (app target only); version/build/bundle greps unchanged.
- swiftc -parse full project: 45/45 PASS (syntax only).
- Xcode/actool build: NOT performed (no Xcode in this
  environment) and not claimed — the .app's generated icon
  metadata can only be inspected after a real build, which the
  next Codemagic run provides.
