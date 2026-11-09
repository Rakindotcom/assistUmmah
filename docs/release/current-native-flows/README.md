# Current signed APK native flow captures

Unmodified device captures from `../current-native-flows.json`, virtual ARM64
Android 16 with 16 KB pages. Disposable synthetic Firebase accounts only.
Home, Quran tracking and tasbih were visually reviewed for font rendering and
layout. Original PNGs are retained at 1080 × 2400; these are QA evidence,
not a complete approved store screenshot set. No login credentials are shown.

`11-deletion-recovery.png` is the actual recovery screen from
`../current-native-deletion.json`, captured after the private dialog was revoked.
Both disposable identities and their owned records were removed afterward.

`12-native-notification-delivery.png` is the original Android notification-shade
capture from `../current-native-delivery.json`. The test advanced only the
disposable device clock, then restored it. Native alarms for the three daily
reminders fired; no notification or app broadcast was injected.

`physical-03-home.png` is the original physical Samsung Galaxy A15 home
capture from `../current-native-physical-flows.json`. The native test also
verified task server persistence, navigation, denial and account isolation.
