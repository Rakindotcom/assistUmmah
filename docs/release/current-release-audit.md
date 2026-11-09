# Current production release audit

Updated 9 November 2026. Candidate: **রবের পথে 1.0.0+8**.

**Build 8 passes clean source/build/signing checks. Native verification of this
exact binary is pending. Public release is not approved. Builds 5, 6 and 7 must
not be published.**

## Scope and constraints

Finish and verify the current production Android app. The full `gap.md` roadmap,
hidden productivity root and offline preview remain outside this release.
Production: `lib/main.dart` → `AppBootstrap` → `AuthGate` → `HomeShell`.
Firebase remains Spark with billing disabled. Play Console stays manual.
Support: **teamframecipher@gmail.com**.

## Build 8 correction

Additional Android 16 / 16 KB testing exposed a build 7 race: while native
exact-alarm permission UI was returning, a foreground refresh read the old
locally disabled prayer preference, then cancelled the new alarms. The UI still
showed 45 alerts enabled. Both native failures are preserved; the second includes
Android's alarm dump. A phone widget regression reproduced enabled stored
preferences with an empty pending set before the fix.

Explicit prayer edits now protect the entire native permission, scheduling and
local persistence operation. Revision checks invalidate earlier refresh reads.
The regression and 19 related tests pass. The full native suite now requires
exact access refusal, grant, revocation, approximate fallback and prayer opt-out;
it checks actual OS alarm windows. Previous six-case passes cannot satisfy the
expanded suite or verify this changed binary.

See the [historical build 7 audit](historical-build7-audit.md). Its public evidence
snapshot is retained locally. Build 7's separate natural-clock/forced-Doze
observation (`matrix-1162untmdq5yk`) completed without seeing delivery within
12 minutes after due. This bounded result is inconclusive for intentionally
inexact alarms under Doze and cannot prove build 8. See the
[historical observation](historical-build7-natural-clock.json). The shared
disposable cohort for that observation and the build 8 permission check was cleaned.

## Current evidence

| Requirement | Result | Evidence / limit |
| --- | --- | --- |
| Source checkpoint | Recorded | `6de9e852ff272cfed3610196017e2d5166939d57`. |
| Release preflight | Passed | Branding, fonts/licenses, policy, Spark-only configuration, deletion inventory, OAuth and private signing inputs. |
| Analyzer | Passed | Clean pipeline, no issues. |
| Flutter regression suite | Passed | 530 passed; two existing browser-only future-migration skips. |
| Release tooling | Passed | 16 tests, including stale binary/clock, unobserved notification, OS alarm-window and incomplete-suite rejection. |
| Signed AAB | Passed | API 36/minimum 24, ARM64, 64-bit alignment, no native test plugin/debug flags, and packaged Dart identities matching compiler outputs for all three ABIs. |
| Universal APK | Passed | Existing upload certificate, signature and 16 KB ZIP alignment verified. |
| Current native startup / legacy | Passed | Android 16 / 16 KB `matrix-w0p1lhvwpdtda` and Android 8 / 4 KB `matrix-53rtwv399shda`: original installed hash, syscall measurement, login/privacy/Back and clean Firebase initialization. |
| Reproduced prayer permission path | Passed | `matrix-3gexv8paqgp1v`, Android 16 / 16 KB: refusal preserves 46 inexact alarms, grant yields 45 exact plus renewal, OS revocation restores approximate scheduling, opt-out clears queue. JUnit passed; disposable accounts cleaned. |
| Current complete native suite | Submitted | Physical matrix `matrix-3q1unykrabi8f`, fresh accounts. Requires all seven cases and independent server persistence/deletion checks; no suite pass yet. |
| Current optional diagnostics | Pending | Requires explicit opt-in/crash/restart/opt-out and a correlated received build 8 server report. |
| Current screenshots | Pending | Build 7 images cannot satisfy the build 8 packet provenance gate. |
| Backend / reviewer access | Prior live readback retained | Rules, public assets and authentication setup are unchanged by this local scheduling fix. No new backend deployment is required. |
| Hosted CI | Externally blocked | Last inspected run 42594358975 had zero job steps and an explicit account billing-lock annotation. No hosted CI pass is claimed. |
| Play-installed build / Console | Manual | Owner requested manual Play work. |

## Artifacts

The APK is `output/apk/rober-pothe-1.0.0-build8.apk`.
The AAB is `output/aab/rober-pothe-1.0.0-build8.aab`.
Both have SHA-256 sidecars; [artifact metadata](current-release-artifacts.json)
records hashes and sizes. No approved build 8 upload packet exists yet.
The earlier build 7 packet is preserved under `dist/play-store/historical/` and
must not be uploaded. Native evidence is invalidated when binary identity changes.

## Remaining gates

1. Verify original build 8 startup, all seven suite cases, received diagnostics,
   fresh captures, server cleanup and disposable fixture cleanup, then package.
2. Verify remaining lifecycle/accessibility scope: natural-clock latency,
   reboot/Doze, long sessions, TalkBack and applicable OEM behavior. A bounded
   forced-Doze observation or controlled-clock pass is narrower than these gates.
3. Manual Play: app-signing certificate, Play-installed password/Google login,
   internal track/pre-launch, listing/declarations, content rating, audience,
   developer identity and applicable closed testing.
4. Resolve the hosted CI account lock before merging under a required-CI policy.
