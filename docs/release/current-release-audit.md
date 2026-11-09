# Current production release audit

Updated 9 November 2026. Candidate: **রবের পথে 1.0.0+7**.

**Build 7 passes source/static checks, Android 8 / 16 KB startup and the complete
physical release suite. Received optional diagnostics verification also passed.
Public release is not approved; builds 5 and 6 are rejected.**

## Scope and constraints

Finish and verify the current production Android app. The full `gap.md` roadmap,
hidden productivity root and separate offline preview are outside this release.
Production: `lib/main.dart` → `AppBootstrap` → `AuthGate` → `HomeShell`.
Firebase remains Spark. Play Console stays manual. Support:
**teamframecipher@gmail.com**.

## Corrections and build provenance

- Daily reminders resolve the current device timezone for every enabled sync,
  independently of prayer calculations' global timezone initialization. Three
  regression cases cover changed zones, cross-module state and opt-out failure.
- Advanced prayer settings use a bottom safe area. The Save-button regression
  reproduces the 48-pixel navigation inset and verifies a successful form save.
- The external native driver parses locale-independent alarm epochs, settles
  input focus, and scrolls controls clear of observed Android navigation bounds.
- **Stale packaging was detected in builds 5/6.** Although their version and
  signature checks passed, both retained build 4's Dart snapshot. Its ARM64 hash
  was `33f42d4dfc0b672b069aad4e6f9dc396a34ea6deed27c449d68b0e5c323f864a`.
  The merged/stripped native intermediates were still dated 6 November.
  These builds did not include the intended Dart fixes and must not be used.
- Release builds now clean generated outputs first. Bundle validation compares
  every packaged Dart GNU build ID against the current compiler output. The
  old build 6 actually fails this guard. Four new regression tests protect it.
- **Build 7 passed this identity guard on ARM64, ARMv7 and x86_64.** Its packaged
  ARM64 snapshot is `c82c1f5ce3d873b19743b6e5c995948d79cc0f6164c73494d81fa0c9d03616e7`,
  with current build ID `b718850985217222f90d3cfa89f9a6c4`. This establishes the
  compiler-to-package match; native UI behavior is checked separately.

## Build 7 evidence

| Requirement | Result | Evidence / limit |
| --- | --- | --- |
| Source checkpoint | Recorded | `7cd3d349cc718f39e0f6c99fa6f5432ab1798703`; app fixes and build 7 release pipeline committed. |
| Release input checks | Passed | Branding, font/license inputs, policy, deletion inventory, Spark-only config, OAuth configuration and signing inputs. |
| Analyzer | Passed | Clean pipeline: no issues. |
| Flutter regression | Passed | 529 passed; two existing browser-only future migration tests skipped. |
| Python release tooling | Passed | 15 tests; real build 6 stale-AOT rejection reproduced. |
| Clean signed AAB | Passed | 1.0.0+7, API 36/minimum 24, ARM64, 64-bit ELF alignment, debug/test exclusion and compiled Dart build-ID match. |
| Signed universal APK | Passed | Exported from verified AAB; existing upload certificate, signature and 16 KB ZIP alignment verified. |
| Native 16 KB startup | Passed | Post-boundary matrix `matrix-1v4ft6yd9muzy`: exact installed APK hash, native 16 KB pages, login/privacy/Back, initialized Firebase and clean registrar logs. |
| Physical functional suite | Passed | Matrix `matrix-3df6vrt78lucs`: all six cases passed. Server reads confirmed the earlier native task save, nine absent roots, eight empty owned collections, deleted Auth identity, retained empty marker and unaffected other-account data. |
| Native screenshots | Prepared | Five inspected 720×1280 captures from successful complete matrix `matrix-3df6vrt78lucs`; pixel-preserving RGB exports and exact APK/AAB hashes recorded. |
| Received optional diagnostics | Passed within scope | Physical Pixel 8 matrix `matrix-2nvwkc87k5oas`: explicit opt-in, controlled shell crash, restart and opt-out; JUnit 1 test, zero failures/errors. Provider FAILURE is expected from the deliberate crash. Independently received report matches package/build/time, with no fixture identifiers/content or custom user fields. Both test accounts cleaned. |
| Older Android | Passed | Build 7 Android 8 matrix `matrix-2jpepjmsmorsb`: original installed hash, native 4 KB pages, login, bundled privacy and Back. Firebase initialization/log checks pass. |
| Existing review account | Live access passed | Normal SDK password login, nine own-document reads, eight owned collection queries, marker absent and legacy-log enumeration denied before deletion. No app records changed. |
| Backend and policy pages | Live readback passed | Five public HTML/script assets exactly match source; active default Firestore release source matches the tested rules. Billing remains disabled. No deployment or account change in this recheck. |
| Hosted CI | Externally blocked | Last inspected run [42594358975](https://github.com/Rakindotcom/assistUmmah/actions/runs/42594358975) had zero steps in all jobs; annotation confirms an account billing lock. |
| Play-installed build / Console | Manual gate | Owner requested manual Play work. |

## Historical tests and cleanup

The [build 4 audit](historical-build4-audit.md) is historical. Startup passes for
builds 5/6 prove those binaries' startup only; the stale snapshot discovery means
they do not verify the intended source changes. Their aggregate physical suites
failed in advanced location settings. The corrected driver avoided an accidental
Home tap but still exposed the stale app's obscured Save action. No failed suite
is reported as a release pass. All completed-run fixture identities and owned
records were cleaned through the normal deletion protocol before fresh fixtures.

## Remaining gates

The complete core suite, independent server persistence/deletion checks,
received diagnostics and disposable fixture cleanup are complete. The generated
packet passes its binary/startup/screenshot gates and remains preparation material.
A separate natural-clock/Doze observation was submitted as
`matrix-1162untmdq5yk`; it has no accepted delivery result yet. Its fresh
disposable fixtures remain active until the matrix is confirmed terminal.
The first Android 16 / 16 KB prayer exact-alarm audit
(`matrix-3bnkinvjl0m5f`) failed before completing its assertions. The capture
shows approximate alerts enabled; it does not establish the native queue check.
A diagnostic rerun, `matrix-35x58ea7wzbqq`, retains the original failure cause
and OS alarm dump. It uses account B on a separate device. Neither new audit
is counted as a native delivery/permission pass yet.

1. Verify remaining lifecycle/accessibility requirements: natural-clock latency,
   reboot/Doze, long sessions, TalkBack and applicable OEM behavior. Controlled
   clock delivery is a distinct, narrower check.
2. Manual Play gates: app-signing certificate, Play-installed password/Google
   login, internal-track/pre-launch reports, listing/declarations, content rating,
   audience, developer identity and applicable closed testing.
3. Resolve the hosted CI account lock before merging under a required-CI policy.

[Firebase's documented Spark quotas](https://firebase.google.com/docs/test-lab/usage-quotas-pricing)
are project-wide daily limits of ten virtual and five physical runs. No billing
upgrade or quota bypass is authorized. Exact reset time has not been established.

## Artifacts

[Artifact hashes and sizes](current-release-artifacts.json) identify:

- APK: `output/apk/rober-pothe-1.0.0-build7.apk`.
- AAB: `output/aab/rober-pothe-1.0.0-build7.aab`.
- SHA-256 sidecars accompany both; binaries remain outside Git.
- Prepared packet: `dist/play-store/rober-pothe-1.0.0-7.zip`. Its validation
  checks artifact identity and packet contents; it is not production approval.
- Replace the previously shared build 6 APK with build 7 for further testing.
