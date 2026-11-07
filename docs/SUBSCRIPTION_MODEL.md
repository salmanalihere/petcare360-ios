# Subscription-Only Model (2026-11-08)

PetCare 360 is subscription-only. The app-managed 7-day trial
(Keychain start date, `TrialManager`) was **removed** and replaced
by Apple's official introductory free trial through StoreKit 2.
There is no free tier, no limited mode, and no access to any app
screen without an active Apple subscription entitlement.

## How access is decided

- `StoreManager.accessState` (`SubscriptionAccessState`) is the
  single source of truth, computed by the pure
  `SubscriptionAccessPolicy` from **verified** StoreKit data only:
  `Transaction.currentEntitlements` and
  `Product.SubscriptionInfo.status(for:)` for group `22553779`.
- States: `.unknown` (not yet read — UI shows a checking screen,
  never the app), `.active` (paid period, introductory free-trial
  period, billing grace period, or cancelled-but-unexpired),
  `.inactive(billingIssue:)` (no entitlement; flag set when Apple
  reports billing retry).
- Re-checked at launch, on every foreground return
  (`scenePhase == .active` in ContentView), after purchases and
  restores, and on every `Transaction.updates` event (renewal,
  trial conversion, expiry, revocation, billing changes).
- Revoked transactions grant nothing. Cancellation never shortens
  access: a cancelled subscription stays active until its
  expiration date, during the trial and paid periods alike.
- Nothing local decides access — no UserDefaults flag, no
  Keychain record. The retired Keychain trial entry from earlier
  builds is simply never read again.

## The lock

ContentView gates the whole app:

1. Onboarding (unchanged) if it has not been completed.
2. `SubscriptionCheckingView` while entitlements resolve.
3. The full TabView only while `accessState` is `.active`.
4. `SubscriptionGateView` otherwise — no tab bar, no settings, no
   data screens. The gate offers plan selection, purchase via
   Apple's confirmation sheet, Restore Purchases, Manage
   Subscription, Privacy Policy and Terms of Use. It has no close
   button.

All SwiftData records stay on the device, untouched, behind the
gate. Nothing is deleted on lock, expiry, or revocation.

## Trial display honesty

The 7-day free trial is offered and described **only** when both
are true for the signed-in Apple ID: the product carries a
free-trial introductory offer in App Store Connect, and
`Product.SubscriptionInfo.isEligibleForIntroOffer` is true.
Prices and the post-trial charge always come from the live
`Product` data. A user in the trial period sees "Free trial
active" with the real end date (from the entitlement's expiration
date) in the paywall, Family header and Settings.

## App Store Connect configuration still required

The app reads whatever offers App Store Connect holds; the code
cannot create them. Before this build ships:

1. **Create the introductory offer on BOTH products** in the
   "PetCare 360 Premium" group: Monthly
   (`com.petcare360.premium.monthly`) and Yearly
   (`com.petcare360.premium.yearly`) — type **Free Trial**,
   duration **7 days**, for new subscribers. (As of 2026-11-07
   both products had **no offers**; until these exist, nobody is
   offered a trial and the gate shows plain prices.)
2. Subscriptions must be submitted for review **with the new app
   version** (they are still "Prepare for Submission").
3. The local `PetCare360.storekit` configuration mirrors the same
   7-day free-trial introductory offers for Xcode/Codemagic test
   runs; it has no effect on production.

## Existing users (migration)

- Users of earlier builds keep all data. On first launch of this
  build they are treated like everyone else: no Apple subscription
  → the gate; their old app-managed trial state grants nothing and
  is not converted into an Apple trial.
- Whether a returning user is offered Apple's introductory trial
  is Apple's decision (introductory offers are once per
  subscription group per Apple ID), surfaced through
  `isEligibleForIntroOffer` — the app never promises it otherwise.

## Tests

- `PetCare360SubscriptionAccessTests` (17 methods) drives the pure
  policy: expiry, revocation, grace period, billing retry,
  cancelled-but-unexpired, trial flagging, product filtering.
- UI tests pre-purchase the monthly plan through `SKTestSession`
  against the local StoreKit configuration (copied into the UI
  test bundle for this purpose), because every journey now starts
  behind the gate. Fail-soft: if the session cannot start, the
  journeys fail on their own assertions rather than passing
  vacuously.
