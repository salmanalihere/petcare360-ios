# PetCare 360 — Legal pages update draft for 1.2.8 (CloudKit restored)

Prepared 2026-11-06 ~13:50 IST, before the 1.2.8 / build 12 upload.
Status: DRAFT for Rukhsana's review — nothing published, nothing changed on the live site.

## Why this is needed now

- The live pages at salmanalihere.github.io/petcare360-legal/ (checked live
  2026-11-06 08:17 UTC) still say **"App version covered: 1.2.0"** and state
  that the app **"does not implement … CloudKit household synchronization"**
  (Privacy §2) and that **"CloudKit household sharing and cross-device
  synchronization are not implemented in this version"** (Terms §4).
- The 1.2.8 release corrections (2026-11-06) **restored CloudKit**:
  `cloudKitSyncEnabled = true`, container `iCloud.com.xenon-media.petcare360`.
  The app now syncs a user's records to **their own devices on the same
  Apple ID** via their private iCloud database.
- The privacy page's own footer already warned: "If a future release adds
  CloudKit … this policy … must be reviewed and updated **before that
  release**." That release is now 1.2.8 / build 12.
- The in-app wording was already corrected in the release package (3 places);
  the published pages are now the only place still claiming local-only.
- The in-repo draft `docs/PRIVACY_POLICY.md` already describes the correct
  behaviour ("If you enable iCloud, they sync through your private iCloud
  account") and carries an addendum flagging this exact reconciliation.

## What the corrected wording must — and must not — claim

- DO say: records sync via the user's **private iCloud / CloudKit container**,
  only to **their own devices signed in to the same Apple ID**.
- DO say: the developer operates **no PetCare 360 server** and cannot access
  the user's iCloud data.
- DO NOT say: household/family members on other accounts can see the data.
  Cross-account sharing (CKShare) is still **not implemented** — sync is
  private-database only.

## Exact replacement text (paste into the published pages)

### Privacy — header lines
- Effective date: **November 6, 2026**
- App version covered: **PetCare 360 1.2.8**

### Privacy — §2 "Where information is stored" (replaces the whole section)
> In version 1.2.8, PetCare 360 stores app records on your iPhone and
> synchronizes them to your other devices signed in to the same Apple ID
> using Apple's CloudKit, in your private iCloud container
> (`iCloud.com.xenon-media.petcare360`). Your records are stored in your
> private iCloud database; PetCare 360 operates no server of its own and
> the developer cannot access your iCloud data. Synchronization is limited
> to your own devices — it does not share records with another person's
> account or device.
>
> Apple may include app data in device backups according to the iOS and
> iCloud backup settings you control. Those backups are governed by Apple's
> services and settings.
>
> The app can create a JSON backup file when you choose Export. The file is
> shared or saved only through the iOS share interface you select. You are
> responsible for keeping exported backup files secure. Importing a backup
> stores its contents in the app on your device.

### Privacy — §7 "Analytics, advertising and tracking" (one sentence)
Replace "The app does not operate a PetCare 360 account or application
backend in version 1.2.0." with:
> The app does not operate a PetCare 360 account or application backend.
> Synchronization uses Apple's CloudKit service, under Apple's terms and
> privacy policy.

### Privacy — §9 "Retention and deletion" (first sentence)
Replace "Your app records remain on your device until you delete them or
remove the app, subject to any device backups you have enabled." with:
> Your app records remain on your devices and in your private iCloud
> database until you delete them or remove the app, subject to any device
> backups you have enabled.

### Privacy — footer note (replaces the "Important" paragraph)
> **Important:** This policy describes PetCare 360 version 1.2.8 as
> inspected on November 6, 2026. If a future release adds household sharing
> with other accounts, analytics, external AI processing, or other network
> services, this policy and the App Store privacy disclosures must be
> reviewed and updated before that release.

### Terms — header lines
- Effective date: **November 6, 2026**
- App version covered: **PetCare 360 1.2.8**

### Terms — §4 "Local storage and current limitations" (replaces the whole section)
> In version 1.2.8, app records are stored on your device and synchronized
> to your other devices signed in to the same Apple ID using Apple's
> CloudKit. Sharing with another person's account or device is not
> implemented in this version. A household member entry or
> invitation-pending label in the interface does not itself grant another
> person access to your data. Do not assume another device has received an
> update unless you have independently confirmed it.

## Also check before submission (not covered by the text above)

- App Store Connect **App Privacy** answers for PetCare 360 must match the
  new behaviour (data synced via Apple CloudKit; no data collected by the
  developer). Not verified here — the ASC account was not checked.
- The Developer App ID iCloud capability and the Codemagic Xenon signing
  profile including iCloud remain the separate blockers already flagged in
  the release report; this legal update does not clear them.

## Sources checked
- Live privacy page, crawled 2026-11-06 08:17 UTC:
  https://salmanalihere.github.io/petcare360-legal/privacy.html
- Live terms page, crawled 2026-11-06 08:17 UTC:
  https://salmanalihere.github.io/petcare360-legal/terms.html
- Release corrections: `workspace/petcare-360/docs/RELEASE_CORRECTIONS_REPORT.md`
  (CloudKit restored, container `iCloud.com.xenon-media.petcare360`).
- In-repo privacy draft: `workspace/petcare-360/docs/PRIVACY_POLICY.md`.
