# Historical build 7 audit — rejected as final candidate

Build 7 (1.0.0+7) is retained for provenance. It must not be published.
Its source checkpoint was `7cd3d349cc718f39e0f6c99fa6f5432ab1798703`.

- APK SHA-256: `5252f571ef3ad5a873f7690867a34f4532d5a0440c061f6eb790aa797126e8a6`.
- AAB SHA-256: `33ef4cd734f9a163c42823ffff09d81af1da493dfba044ef45dfeddaefa8aa1b`.
- Analyzer clean; 529 Flutter tests passed, two future browser-only tests skipped.
- Clean packaging, compiler/packaged Dart identities, signing and 16 KB alignment passed.
- Android 8 startup: `matrix-2jpepjmsmorsb`; Android 16 / 16 KB startup:
  `matrix-1v4ft6yd9muzy`.
- Physical six-case suite: `matrix-3df6vrt78lucs`, SUCCESS. Core flows,
  reminders, location, controlled-clock delivery, timezone and deletion passed.
- Opt-in synthetic crash/restart/opt-out: `matrix-2nvwkc87k5oas`; JUnit passed,
  expected deliberate-crash matrix failure, independently received correlated report.

## Release blocker found by additional testing

Exact-alarm refusal audits `matrix-3bnkinvjl0m5f` and
`matrix-35x58ea7wzbqq` failed on original build 7 / Android 16 / 16 KB.
The second run captured the cause and Alarm Manager state: the UI displayed
45 approximate prayer alerts, but the native queue had no active app alarms.
Foreground refresh loaded the still-disabled local preference while the explicit
permission/scheduling/save operation was in flight, then cancelled its new alarms.

A phone widget regression reproduced enabled persisted preferences with an empty
native pending set. The source fix protects the entire explicit operation through
persistence and invalidates earlier refresh reads; the regression and 19 related
tests passed. Replacement build 8 requires its own binary-bound native proof.

The original public receipt snapshot is retained locally in
`.local/build7-public-evidence-before8/`. Current evidence filenames may advance
to later binaries. The separate build 7 natural-clock/Doze observation remains
pending at this snapshot and cannot verify build 8.
