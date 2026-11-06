> STATUS (2026-11-06): CloudKit is now ENABLED in code at the
> owner's instruction — AppConfig.cloudKitSyncEnabled = true,
> container iCloud.com.xenon-media.petcare360, entitlements wired
> via CODE_SIGN_ENTITLEMENTS. The portal/profile items below remain
> the owner's responsibility; if the container cannot be opened,
> the app falls back to the local store (no crash, no data loss).
> IMPORTANT: enabling CloudKit changes the on-device store
> location — export a full backup BEFORE installing the first
> CloudKit build, and Merge-restore it afterwards if your existing
> records do not appear.

# CloudKit / iCloud — What Is Implemented, What Is Not, Owner Setup

## What the code does now (1.2.1)
- The SwiftData schema is CloudKit-compatible: every property has a
  default value or is optional, relationships are optional with inverses,
  and there are NO unique constraints anywhere (verified by inspection).
- `PetCare360App` opens the LOCAL on-device store. CloudKit is NOT
  attempted automatically (v1.2.2 audit rule): the CloudKit private
  configuration for container `iCloud.com.xenon-media.petcare360` is only used
  when `AppConfig.cloudKitSyncEnabled` is set to true, which may only
  happen AFTER the owner setup below is complete.
- If the persistent store cannot be opened, the app shows a recoverable
  error screen with a retry (v1.2.2): it never crashes with fatalError
  and never silently substitutes a throwaway in-memory database, and the
  existing database file is left untouched.
- `PetCare360/PetCare360.entitlements` ships in the project with the
  iCloud container identifier + CloudKit service declared. It is NOT yet
  wired into the build settings — that happens when the capability is
  added in Xcode (step 2 below), because the capability must belong to
  YOUR Apple Developer account.

## What this gives you once activated
Sync of the user's own pets/records across THEIR devices signed into the
same iCloud account (private database). Offline edits queue and sync when
connectivity returns; CloudKit resolves conflicts per record.

## What it does NOT give you (be clear with users)
- **Cross-user household sharing is NOT implemented.** SwiftData's
  CloudKit integration exposes the private database only; it does not
  expose CKShare participant sharing between different Apple IDs.
- The in-app household (members, roles, handoffs) is therefore LOCAL to
  one device, exactly as in 1.0–1.2. Do not market "family sharing across
  devices" until a real sharing layer exists.
- Options for true sharing later (each needs a separate, approved piece
  of work): (a) a Core Data + CKShare layer for the household data, or
  (b) a backend service. Neither is in this build, and no fake sharing UI
  was added.

## Owner activation steps (Apple Developer account required)
1. https://developer.apple.com/account → Identifiers → the App ID
   `com.xenon-media.petcare360` → enable **iCloud** → create/select the container
   `iCloud.com.xenon-media.petcare360`.
2. In Xcode: target → Signing & Capabilities → **+ Capability → iCloud**
   → check **CloudKit** → check the container above. Xcode sets
   CODE_SIGN_ENTITLEMENTS to the shipped `PetCare360.entitlements`.
   (Optional: + Capability → Background Modes → Remote notifications, so
   silent pushes can trigger syncs while the app is backgrounded.)
3. First run on a signed-in device: watch Xcode Console for
   NSPersistentCloudKitContainer events; open the CloudKit Console
   (icloud.developer.apple.com) → the container → Development environment
   → confirm record types appear after saving a pet.
4. **Data migration warning:** the first launch AFTER enabling the
   capability opens the CloudKit-backed store, which is a different store
   location from the purely local one — existing on-device data will not
   appear automatically. Before enabling on a device with real data:
   Settings → Export full backup (JSON); after enabling: Import backup →
   Merge. The backup covers every model type (see docs/PHASE2... report).
5. Before App Store submission, deploy the schema in the CloudKit
   Console (Development → Production) — required, or sync fails for
   production users.

## Privacy note
With iCloud enabled, user data syncs through the USER's private iCloud
container; you (the developer) cannot read it. If the published privacy
policy says data "never leaves the device", update that page before
release — the policy must describe iCloud sync accurately.
