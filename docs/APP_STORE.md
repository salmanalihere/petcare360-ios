# App Store Submission Checklist (owner steps, Mac required)

1. Open `PetCare360.xcodeproj` in Xcode 15+, set your signing team; keep or
   change the bundle ID placeholder `com.petcare360.app` consistently.
2. Replace the PLACEHOLDER values in `PetCare360/Services/AppConfig.swift`:
   privacy policy URL, terms URL, support email — and host the privacy policy
   (draft in docs/PRIVACY_POLICY.md).
3. Create the 2 subscription products in App Store Connect (docs/STOREKIT_SETUP.md).
4. Run the unit tests (Cmd+U) and walk the manual checklist in docs/TEST_REPORT.md
   on a real iPhone and in the Simulator (notification scheduling, StoreKit
   sandbox purchase + restore, scanner on a real document photo).
5. Do NOT enable iCloud/CloudKit for this release: sync and cross-device household sharing are not implemented (household coordination is on-device only). See docs/CLOUDKIT_SETUP.md.
6. App Privacy answers: Data Not Collected (matches PrivacyInfo.xcprivacy).
7. Include the medical disclaimer in the App Store description: PetCare 360 is
   a record-keeping tool, not a veterinary diagnostic or treatment service.
