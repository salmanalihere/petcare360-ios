# PetCare 360 — Explicit Local Fallback (cloudKitDatabase: .none)

Date: 2026-11-06. Based on EXECUTED Codemagic diagnostic build 4
(commit d4cd992): A PASS, B PASS, D1-D4 PASS, E OPENED (both
locations), C FAILED with "CloudKit integration requires that
all relationships be optional" (11 to-many relationships listed).

## Why the old "local" fallback was not local

ModelConfiguration.cloudKitDatabase DEFAULTS to `.automatic`.
`.automatic` engages CloudKit mirroring whenever the app binary
carries the iCloud entitlement. Build 12 wired
CODE_SIGN_ENTITLEMENTS into the signed app, so on a real device
the fallback configuration silently ran the SAME CloudKit schema
validation as the primary configuration — and failed it
identically (SwiftDataError 1 in both lines, fresh install
included). Builds up to 11 had no entitlement wired, so
`.automatic` had nothing to engage and the store was genuinely
local — which is why they worked. The unsigned simulator
workflow (CODE_SIGNING_ALLOWED=NO, no entitlement in effect)
cannot reproduce this: there `.automatic` resolves to local,
which is exactly why tests B and E passed in Codemagic while
the entitled device build failed.

## The change (PetCare360App.swift only)

New single helper, used by openStorage's fallback AND by
resetAndReopen (both previously built `.automatic` configs):

    static func localConfiguration(schema:url:) -> ModelConfiguration
    // default URL: ModelConfiguration(schema:, isStoredInMemoryOnly: false,
    //                                 cloudKitDatabase: .none)
    // explicit URL: ModelConfiguration(schema:, url:, cloudKitDatabase: .none)

`.none` removes CloudKit from the fallback by construction,
regardless of entitlements, so a CloudKit validation failure can
never prevent the local store from opening. A diff against the
previous package shows the helper + two call-site swaps are the
ONLY production change. NOT changed, per instruction: any model
or relationship; the CloudKit container or production schema;
the primary CloudKit attempt (still first in the ladder); the
recovery safeguards (one-time bounded wipe, no in-memory
fallback, error chain reporting); workflows; bundle; build (13).

## Consequence, stated plainly

Until the separate, not-yet-authorized change makes the 11
to-many relationships optional, the primary CloudKit attempt
will keep failing validation and the app will run on the
explicit local store. The app OPENS and all local functionality
works; iCloud sync remains blocked by the optionality issue —
that is a model change for a future, separately approved task.

## Tests

NEW testF_ExplicitLocalFallbackOpensSavesReopens in
PetCare360StorageDiagnosticsTests: builds the configuration via
the production helper (temp URL), creates, saves a pet,
releases the container, reopens, verifies the record. Written,
NOT executed here (no SwiftData runtime in this environment) —
run it on a Mac or add a step later; the diagnostic workflow was
left intact per instruction, so its steps do not include F yet.
Local verification: swiftc -parse 49/49 PASS.

## Not claimed

No iPhone success is claimed from simulator results. The device
verification is: install this build, launch — the error screen
should not appear and onboarding/home should open on the local
store. If it still fails, the error screen's chain (now captured
in full) is the evidence to send back.
