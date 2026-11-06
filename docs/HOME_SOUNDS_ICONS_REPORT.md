# PetCare 360 — Home Dashboard, Smart Reminders, Sounds & Icons

Date: 2026-11-06. Version/build unchanged: 1.2.8 (11). Nothing
uploaded to GitHub (private repo, no credentials here).

## 1. Why appointments were missing from Home — root cause

The creation path is correct (the editor links the pet, inserts and
saves; the appointment shows in the pet's Appointments list). The
Home card filtered with an exact-instant comparison,
`appointment.date >= Date()`: an appointment stops being "upcoming"
the second its start time passes — so a 9:00 appointment created
for today is invisible by 9:05, and one saved with a time earlier
than the moment of saving never appears at all. The card also
showed only ONE appointment, with no pet name or avatar.

Fix: Home now builds from start-of-day semantics (today's
appointments show all day) through the new centralized schedule
(below), which lists appointments with pet avatar, title, clinic/
vet, date, time and status, sorted chronologically, with View All.

## 2. Centralized schedule — "Upcoming for Your Pets"

New `HomeSchedule` builder (Services/HomeSchedule.swift) derives
everything from the existing database — no sample data, no second
scheduling system, stable unique ids per record+day so an activity
can never appear twice:
- Appointments (not completed/cancelled, today → +30 days)
- Vaccination due dates by expiration date (overdue included)
- Feeding times from active schedules (today + tomorrow)
- Medication doses: tomorrow's on the Home card; today's live in
  Today's Care (with their Given state) so Home never lists the
  same dose twice. The View All screen shows the full list
  including today's doses and tasks.
- Care tasks (incomplete; overdue included)
- Insurance renewals, pet birthdays inside the horizon
Status buckets computed from the calendar: Overdue / Due today /
Tomorrow / This week / Later, shown as coloured chips. The View
All screen groups by bucket in urgency order. Because it is built
from @Query data, it refreshes automatically on launch, on
foreground, and the moment any record is created, edited,
completed, rescheduled or cancelled. CloudKit note: sync remains
disabled by configuration in this build, so there is no iCloud
data to refresh from — the schedule reads the local store only.

Appointment status: VetAppointment gained `isCancelled` (additive,
default false — existing data migrates untouched; backup format
carries it as an optional field so older backups still restore).
The editor has Completed/Cancelled toggles; the Appointments list
shows status and Complete/Cancel/Reopen actions (with save-error
handling); cancelled appointments lose their reminder centrally
(`shouldScheduleAppointmentReminder` now excludes them) and never
appear as upcoming.

## 3. Animal-specific notification sounds

How it works: every reminder the app schedules now resolves its
sound at schedule time from the pet's species (dose, feeding,
vaccination, refill, appointment and insurance paths all thread it
through the one NotificationService funnel): dog → woof, cat →
meow, bird → chirps, rabbit → soft thump; species without a
dedicated sound (and reminders with no pet) use the user's chosen
default. Settings → Notification Preferences: Animal-Specific
Sounds toggle (ON by default), Default Notification Sound picker
(including "iOS System Default"), an in-app preview button for
every sound, a "Send Test Notification" button (a real local
notification ~5s out using the sound your first pet's reminders
would use), and per-category switches (medications / appointments
/ vaccinations / feeding / insurance) enforced centrally —
switching one off also cancels that category's pending requests.

Audio files added (PetCare360/Sounds/, copied to the bundle root —
where iOS requires custom notification sounds):
petcare-dog.wav (0.82s), petcare-cat.wav (0.90s),
petcare-bird.wav (0.75s), petcare-rabbit.wav (0.80s),
petcare-reptile.wav (1.50s), petcare-horse.wav (1.10s),
petcare-chime.wav (0.95s) — all 22050 Hz 16-bit mono WAV,
durations measured from the final files on disk.
Licence note: these are ORIGINAL synthesized tones generated for
this app (a pitch-glide "meow", chirp sweeps, a tremolo "whinny"
etc.), not recordings of real animals and not downloaded audio —
pleasant and licence-clean, but they are stylised sounds, and the
report says so rather than pretending they are field recordings.
Honest iOS limits: sounds play only with notification permission
granted and are still subject to the silent switch, Focus modes
and iOS sound settings — the app cannot force a sound, and the
Settings screen says exactly that.

## 4. App icons

IMPORTANT: the artwork file ("Happy Pet Care Companions.png") has
still not arrived in this workspace — it was missing for the
previous brief too. Rather than block the whole feature again, the
complete icon system is implemented with an original generated
set in the described style (happy dog + cat with a heart on the
brand green gradient; the primary icon was visually checked).
When the real artwork is re-attached, replacing the 8 PNGs is a
drop-in swap — no code or configuration changes needed.

Configuration: primary = AppIcon.appiconset (Dog and Cat);
alternates AppIconDog / AppIconCat / AppIconBird / AppIconRabbit /
AppIconReptile / AppIconHorse / AppIconOther, each a single
1024×1024 RGB no-alpha PNG (all verified). The project sets
ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS=YES, which makes
Xcode generate the CFBundleAlternateIcons entries. Settings →
Choose Your App Icon shows the fixed bundled set in a grid (via
matching preview imagesets), marks the current icon (read from
UIApplication.alternateIconName, which iOS itself persists across
launches), and applies changes with
UIApplication.setAlternateIconName — the real Home Screen icon
changes, with iOS's own confirmation alert (expected system
behaviour). No uploads/custom icons anywhere, per the
clarification.

## 5. Tests

Added PetCare360HomeTests (14 methods): status buckets; future +
same-day-earlier appointment visibility (the bug regression);
completed/cancelled/past exclusions; chronological order + unique
ids; medication today/tomorrow placement; birthday horizon +
"Turns N"; cancelled-appointment reminder gate; backup round-trip
for isCancelled + legacy decode; species→sound mapping; sound
resolution under every preference combination; all sound files
present in the bundle; category keys/prefixes; the fixed icon set.
Totals: 130 tests written (122 unit + 8 UI), ZERO executed — no
Xcode here. Verification: swiftc -parse 44/44, tree-sitter 44/44,
per-struct state sweep ALL RESOLVE, pbx/asset/scheme/StoreKit
checks PASS, icons/PNGs verified programmatically, sounds verified
by header/duration/amplitude analysis.

Still requires a device/Xcode: actual notification delivery and
sound playback in background/closed states, the alternate-icon
system confirmation flow, and the first true compile (Codemagic).

## 6. Files changed / added

Added: Services/HomeSchedule.swift, Services/NotificationSounds.swift,
Features/AppIcons.swift, PetCare360/Sounds/*.wav (7),
Assets.xcassets: 7 alternate appiconsets + 8 preview imagesets,
PetCare360Tests/PetCare360HomeTests.swift,
docs/HOME_SOUNDS_ICONS_REPORT.md.
Modified: Models/HealthModels.swift (isCancelled),
Services/BackupService.swift (DTO round-trip),
Services/NotificationService.swift (sound funnel, species
threading, category gates/cleanup, test notification),
Features/HomeView.swift (schedule card + ScheduleView + row),
Features/RecordsView.swift (appointment status UI/editor),
Features/FamilyView.swift (Settings: Notification Preferences +
icon section), Assets.xcassets/AppIcon.appiconset (new primary
artwork), PetCare360.xcodeproj/project.pbxproj (regenerated:
sounds in Resources, INCLUDE_ALL_APPICON_ASSETS, new files).
