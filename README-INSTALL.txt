PetCare360 diagnostic workflow update
Target branch: petcare360-clean-release
Base GitHub commit: be4401084384b61b653a15081cc7accaa0071111

Copy the contents of this package into your existing local repository folder,
preserving the folder paths. This package contains a FULL merged codemagic.yaml:
it retains petcare360-ios and petcare360-testflight and adds
petcare360-storage-diagnostics.

Files included:
- codemagic.yaml (merged; TestFlight workflow preserved)
- PetCare360/PetCare360App.swift
- PetCare360/Services/StorageDiagnostics.swift (new)
- PetCare360.xcodeproj/project.pbxproj
- PetCare360Tests/PetCare360StorageDiagnosticsTests.swift
- docs/DIAGNOSTIC_REPORT_BUILD13.md
- docs/DIAGNOSTIC_WORKFLOW.md

Do not replace .git, .gitignore, scripts/, or any other repository files.
Do not switch branches. Commit and push these changes to petcare360-clean-release.
No production build number change is included.
