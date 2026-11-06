# PetCare 360 — Xcode 26.6 Notification Sound API Fix

Date: 2026-11-06. Targeted API-compatibility correction only.

## Error

Codemagic (Xcode 26.6): `type 'UNNotificationSound' has no member
'Name'` at NotificationService.swift lines 63 and 367. The nested
`UNNotificationSound.Name` spelling is not available in that SDK;
the sound-name type is the standalone `UNNotificationSoundName`.

## Exact changes (2 lines, 1 file)

PetCare360/Services/NotificationService.swift, lines 63 and 367:

- was: `content.sound = soundName.map { UNNotificationSound(named: UNNotificationSound.Name($0)) } ?? .default`
- now: `content.sound = soundName.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default`

Line 63 is the shared scheduling funnel every reminder passes
through; line 367 is the Settings "Send Test Notification" path.
Both now use the corrected API. A project-wide search confirms
ZERO remaining uses of `UNNotificationSound.Name` in app or test
sources, and a diff against the previous package's file shows
these two lines are the ONLY change to it.

Unchanged behaviour: `soundName` still carries the resolved file
name (species sound, user default, or nil), nil still maps to
`.default`, and the whole sound-resolution layer
(NotificationSounds.swift), preferences, category gates and the
7 bundled WAV files are untouched. No changes to bundle ID
(com.xenon-media.petcare360), version 1.2.8 / build 11, platform
settings, CloudKit configuration, or any other functionality.

## Validation

- swiftc -parse on the changed file: PASS (syntax only)
- Xcode build: NOT performed (no Xcode in this environment) and
  not claimed. The next Codemagic build verifies compilation.
