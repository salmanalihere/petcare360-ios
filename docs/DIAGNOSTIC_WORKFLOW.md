# Codemagic Storage Diagnostics — Setup & Run Guide

Workflow name (as it appears in Codemagic):
**PetCare 360 · Storage Diagnostics**
(id: petcare360-storage-diagnostics)

## Add it (keeps the TestFlight workflow untouched)

The repo's codemagic.yaml already contains the TestFlight
workflow under `workflows:`. The diagnostics workflow is a
SEPARATE block in the same file:

1. Take `codemagic-diagnostics-workflow.yaml` from this package.
2. In the repo's codemagic.yaml, paste its
   `petcare360-storage-diagnostics:` block under `workflows:`,
   at the same indentation as the TestFlight workflow.
3. Commit to branch `petcare360-clean-release` and push.
   (Also commit the updated PetCare360StorageDiagnosticsTests.swift
   from this package — tests close containers before reopening and
   add test E.)

## Run it

1. Codemagic → Applications → petcare360-ios.
2. "Start new workflow" (top right) → branch
   `petcare360-clean-release` → workflow dropdown:
   **PetCare 360 · Storage Diagnostics** → Start.
   It has NO automatic triggers; it only runs when started.
3. When it finishes (about 10-20 min), open the build →
   Artifacts: A.log … E.log, C.log, 99-summary.log,
   exit-codes.txt, and the .xcresult bundles.

## How to read the results

- 99-summary.log lists each test's pass/fail and every captured
  NSError chain in one place.
- A.log fails -> environmental (simulator image / toolchain) —
  the chains still matter; forward them.
- B.log fails while A passes -> app schema; D1-D4 logs name the
  group; forward all logs.
- E.log prints whether the DEFAULT store location opened vs the
  explicit temp URL — the app uses the default location, tests
  A/B/D use explicit ones.
- C.log is EXPECTED to be limited: the workflow builds unsigned
  (CODE_SIGNING_ALLOWED=NO) with no iCloud account/provisioning
  in the simulator, so its CloudKit result can neither prove nor
  disprove the device failure. Its chain is still captured for
  comparison against the device's error-screen chain.

## v2 fix — "module built without '-enable-testing'" (2026-11-06)

The first run failed in Build for testing: `@testable import
PetCare360` needs the app module compiled with testing support.
The workflow now passes **ENABLE_TESTABILITY=YES** as an
xcodebuild argument (the Xcode project itself is unchanged), plus
**ONLY_ACTIVE_ARCH=YES / ARCHS=arm64** so the app and test
bundles use a single simulator architecture (no arm64/x86_64
module mismatch). Gating: the build step uses pipefail, so if
build-for-testing fails, Codemagic stops and NO test step runs —
and each test step additionally checks the built
PetCare360Tests.xctest exists before running, aborting loudly
(a build failure, never a silent "skip"). If a run stops at
Build for testing, download `01-build-for-testing.log` from the
artifacts — publishing still happens on failure.

## What this workflow never does

No IPA, no distribution signing, no TestFlight upload, no
production code/model/config changes, no build-number change
(stays 13).
