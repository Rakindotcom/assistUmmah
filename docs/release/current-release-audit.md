# Current production release audit

Updated 9 November 2026. Candidate: **রবের পথে 1.0.0+5**.

**Verification is in progress; public release is not approved.**

## Scope

Finish and verify the current production app for Android release. The full
`gap.md` roadmap, hidden productivity root and separate offline preview remain
outside this release. Production starts at `lib/main.dart` → `AppBootstrap` →
`AuthGate` → `HomeShell`. Firebase must remain Spark; Play Console stays manual.

## Current evidence

- Source checkpoint: `5c88292f2eb91c1e899b0d811073125e782b0e00`.
- Fixed two reproduced daily reminder defects: device timezone changes were
  cached, and prayer timezone initialization could reset global scheduling to UTC.
  Daily scheduling now resolves the device zone explicitly for every enabled sync.
- Flutter: **528 passed**, two browser-only future migration tests skipped.
  Analyzer: no issues. Three new regression cases cover timezone changes,
  cross-module initialization and opt-out when timezone lookup fails.
- Signed APK/AAB: version 1.0.0+5, target API 36, minimum API 24; signatures,
  existing upload certificate, ARM64, 16 KB ELF and ZIP alignment verified.
  Artifact hashes are in [the current receipt](current-release-artifacts.json).
- Cloud virtual Android 16 / 16 KB matrix `matrix-iu0sqm17mwmaa`: installed
  APK hash, startup/privacy/Back, authentication, native task creation, account
  isolation, reminder permission/cancellation, diagnostics consent, manual
  location fallback and controlled-clock notification delivery passed their
  individual cases. **The aggregate suite failed** at the timezone assertion
  because its test parser expected `origWhen=` rather than Android's epoch
  header `origWhen <millis>`. Deletion was not reached. This run does not unlock
  the complete-suite release gate.
- The parser is corrected in `9fdac0e`. A full physical Galaxy A15/API 36 run
  (`matrix-39fdcivgv0dor`) and a separate Android 8 startup check are pending.
- Existing backend/rules and legal-page evidence is unchanged. Support:
  **teamframecipher@gmail.com**. No billing plan change was made.

## Remaining work

1. Complete current-binary native timezone, deletion, physical and older-Android
   checks; verify server persistence/deletion and clean disposable fixtures.
2. Verify optional diagnostics receipt against this build; refresh current
   screenshots and binary-bound evidence, then generate the upload packet.
3. Test remaining OS/accessibility/lifecycle requirements within available
   devices. Controlled clock delivery does not establish natural-clock latency,
   reboot/Doze, long sessions or all OEM behavior.
4. Manual Play gates: Play app-signing certificate, Play-installed password and
   Google login, internal-track/pre-launch reports, listing/declarations,
   content rating, audience, developer identity and any closed-testing rules.
5. Hosted GitHub checks previously could not start because of the account
   billing lock. Local checks do not establish a hosted CI pass.

## Artifacts

- Installable test APK: `output/apk/rober-pothe-1.0.0-build5.apk`.
- Signed AAB: `output/aab/rober-pothe-1.0.0-build5.aab`.
- SHA-256 sidecars accompany both. No approved build 5 upload packet yet.
- [Historical build 4 audit](historical-build4-audit.md) and its native receipts
  do not verify build 5. Build 4 must not be published.
