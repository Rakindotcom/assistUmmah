# Current production release audit

Updated 9 November 2026. Candidate: **রবের পথে 1.0.0+6**.

**Builds 5 and 6 are rejected: their packaged Dart snapshots were stale.
Build 7 is being prepared from a clean build. Public release is not approved.**

The three build 4/5/6 AABs contain the same ARM64 Dart library SHA-256
`33f42d4dfc0b672b069aad4e6f9dc396a34ea6deed27c449d68b0e5c323f864a`.
The current compiler output has GNU build ID
`b718850985217222f90d3cfa89f9a6c4`, but the packaged library has older ID
`b7188509789f8b14f90d3cfa8a2d9fee`. Merged/stripped native intermediates were
still dated 6 November. Thus the APK version/signature checks passed while the
new Dart fixes were absent. The previous claimed source commit was an intended
checkpoint, not proof of packaged source identity.

The verifier now rejects this mismatch for every ABI, and the release script
cleans generated build outputs before compiling. The new identity guard and its
regressions pass; all 13 Python release-tool tests pass. **Do not install or
publish the previously shared build 6 APK as the corrected candidate.**

The results below describe build 6 only and do not establish build 7.

## Scope

Finish and verify the current production app for Android release. The full
`gap.md` roadmap, hidden productivity root and separate offline preview remain
outside this release. Production starts at `lib/main.dart` → `AppBootstrap` →
`AuthGate` → `HomeShell`. Firebase stays Spark; Play Console stays manual.
Support: **teamframecipher@gmail.com**.

## Fixes established by release testing

1. Daily reminders now resolve the device timezone for every enabled sync,
   independently of the global timezone state used by prayer calculations.
   Tests reproduced a cached device zone and cross-module reset to UTC before
   the fix. Three new regression cases pass.
2. The advanced prayer-settings Save button now respects the bottom safe area.
   A physical Galaxy A15 test tapped Android Home because the button was behind
   its three-button navigation bar. A widget regression reproduced the overlap
   at a 48-pixel bottom inset and passes after the fix, including actual Save.
3. The native audit driver now parses the locale-independent epoch in Android's
   alarm header, rather than its localized date field. The corrected parser
   reads all three expected daily times from the actual Bangla device dump.

## Evidence for build 6

| Requirement | Result | Scope |
| --- | --- | --- |
| Production source | Committed | `9df46cd`, including the timezone and bottom-safe-area fixes. |
| Flutter regression | Passed | 529 passed, two existing browser-only future migration tests skipped. |
| Analyzer | Passed | No issues. |
| Release evidence tooling | Passed | Nine unit tests bind functional claims to current APK/AAB identities; superseded-version packet rejection verified separately. |
| Signed AAB | Passed | Version 1.0.0+6, target API 36, minimum API 24, ARM64, all 64-bit ELF load segments aligned for 16 KB; test/debug flags absent. |
| Universal APK | Passed | Exported signed APK; existing upload certificate matches, 16 KB ZIP alignment and signature verification pass. |
| Current native startup | Passed | Build 6 16 KB matrix `matrix-32b6xdgx7d0ed`: independently measured installed APK hash, page size, login, privacy and Back; Firebase initialization/log checks pass. |
| Physical functional suite | Incomplete | First build 6 run passed core flows/reminder consent, then failed when the driver clicked a Flutter scroll child over Android Home. Driver corrected to scroll actions above the observed system-navigation bounds; full rerun pending. |
| Current screenshots | Pending | Must be generated from this candidate and inspected. |
| Optional received diagnostics | Pending | Opt-in, controlled crash, restart, opt-out and independently correlated server event must identify this build. |
| Existing backend and policy pages | Unchanged | Tested rules/Hosting deployment evidence remains valid; no backend source changes in builds 5/6. |
| Hosted CI | Externally blocked | Current run [42576553855](https://github.com/Rakindotcom/assistUmmah/actions/runs/42576553855): all three jobs have zero steps. Annotation: account locked due to a billing issue. |
| Play-installed app / Console | Manual gate | Owner requested manual Console work. |

## Historical evidence and failures

Build 4 is superseded; see [its historical audit](historical-build4-audit.md).
Build 5 passed signed-out startup on Android 8 (4 KB) and Android 16 (16 KB).
Its virtual suite passed core cases but failed at the alarm test parser; deletion
was not reached. Its physical suite passed core flows and reminders but failed
at the real prayer-settings navigation-bar overlap. **Neither failed aggregate
suite is a release pass.** Their disposable identities and owned app records
were cleaned using the normal deletion protocol before new fixtures were made.

## Remaining release gates

- Finish current-binary native checks, confirm server task persistence/deletion,
  and clean the new disposable fixtures.
- Export and inspect current phone screenshots; refresh binary-bound evidence
  and generate the upload packet only after its strict gates pass.
- Verify remaining lifecycle/accessibility/device requirements. Controlled clock
  delivery does not establish natural-clock latency, reboot/Doze, long sessions,
  TalkBack or all OEM behavior.
- Manual Play checks: app-signing certificate, Play-installed password and Google
  login, internal-track/pre-launch reports, listing/declarations, content rating,
  audience, developer identity and applicable closed-testing requirements.
- Resolve the hosted CI account lock before merging under a required-CI policy.
- The build 6 Android 8 submission (`matrix-2miug650jbzvy`) was rejected with
  `TEST_QUOTA_EXCEEDED`. No test ran. Wait for the free quota reset; build 5
  startup on Android 8 does not verify build 6. No billing upgrade is allowed. [Firebase documents](https://firebase.google.com/docs/test-lab/usage-quotas-pricing)
  separate daily Spark limits of ten virtual and five physical test runs;
  these are project-wide across test types. The exact reset time has not been
  established from the documented quota response.

The APK/AAB paths and hashes are recorded in
[the artifact receipt](current-release-artifacts.json). Binaries
remain outside Git. No approved build 6 upload packet exists yet.
