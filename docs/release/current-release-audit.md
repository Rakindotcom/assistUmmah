# Current production release audit

Updated 9 November 2026. Candidate: **রবের পথে 1.0.0+7**.

**The corrected signed binaries pass source/static checks. Native verification
is pending; public release is not approved. Builds 5 and 6 are rejected.**

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
| Python release tooling | Passed | 13 tests; real build 6 stale-AOT rejection reproduced. |
| Clean signed AAB | Passed | 1.0.0+7, API 36/minimum 24, ARM64, 64-bit ELF alignment, debug/test exclusion and compiled Dart build-ID match. |
| Signed universal APK | Passed | Exported from verified AAB; existing upload certificate, signature and 16 KB ZIP alignment verified. |
| Native 16 KB startup | Pending | Must identify this exact APK/AAB. Build 6 startup is historical. |
| Physical functional suite | Pending | Login, task save/server persistence, account isolation, permission flows, location fallback, controlled delivery, in-process timezone changes and interrupted deletion. |
| Native screenshots | Pending | Current-binary captures must be visually inspected and exported. |
| Received optional diagnostics | Pending | Explicit opt-in, controlled crash, restart/opt-out and a server event correlated to this build. |
| Older Android | Pending / free quota | Previous Android 8 submission was rejected with `TEST_QUOTA_EXCEEDED`; no build 7 pass claimed. |
| Backend and policy pages | Unchanged | Existing rule/Hosting receipts apply to unchanged backend sources. |
| Hosted CI | Externally blocked | Last inspected run [42576553855](https://github.com/Rakindotcom/assistUmmah/actions/runs/42576553855) had zero steps in all jobs; annotation confirms an account billing lock. |
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

1. Complete build 7 native checks, independently verify server persistence and
   deletion, then clean disposable fixtures.
2. Inspect/export current screenshots and update all binary-bound receipts;
   generate the strict upload packet after its gates pass.
3. Verify remaining lifecycle/accessibility requirements: natural-clock latency,
   reboot/Doze, long sessions, TalkBack and applicable OEM behavior. Controlled
   clock delivery is a distinct, narrower check.
4. Manual Play gates: app-signing certificate, Play-installed password/Google
   login, internal-track/pre-launch reports, listing/declarations, content rating,
   audience, developer identity and applicable closed testing.
5. Resolve the hosted CI account lock before merging under a required-CI policy.

[Firebase's documented Spark quotas](https://firebase.google.com/docs/test-lab/usage-quotas-pricing)
are project-wide daily limits of ten virtual and five physical runs. No billing
upgrade or quota bypass is authorized. Exact reset time has not been established.

## Artifacts

[Artifact hashes and sizes](current-release-artifacts.json) identify:

- APK: `output/apk/rober-pothe-1.0.0-build7.apk`.
- AAB: `output/aab/rober-pothe-1.0.0-build7.aab`.
- SHA-256 sidecars accompany both; binaries remain outside Git.
- No approved build 7 upload packet exists yet. Replace the previously shared
  build 6 APK with build 7 for further testing.
