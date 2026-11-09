# Current production release audit

Updated 7 November 2026. Candidate: **রবের পথে 1.0.0+4**.

## Scope and decision

The owner selected **finish and verify the current app for release**. The full
`gap.md` roadmap, the hidden productivity root, general task migration and the
separate offline preview are outside this release. Production continues through
`lib/main.dart` → `AppBootstrap` → `AuthGate` → `HomeShell`.

**The signed candidate is prepared; public release approval remains open.**
Local checks establish source behavior, deployed backend compatibility and
artifact identity. They do not prove physical Android behavior, Play signing,
OS notification delivery or an approved Console configuration.

## Evidence by requirement

| Requirement | Current result | Evidence and limit |
| --- | --- | --- |
| Production entry and package | Verified | Normal entry, `production` flavor, `com.rakindotcom.ummah_assist`; preview remains a distinct package. |
| Reproducible source checkpoint | Verified | `fe768742b0b8fc4854e71f3d0138811f2a72af58`; no later app-source changes. |
| Static analysis | Passed | `flutter analyze --no-pub`: no issues. |
| Flutter regression suite | Passed | 525 passed, 2 browser-only future migration tests skipped. Includes phone layouts, enlarged Bangla text, semantics, core feature flows and account guards. |
| Release evidence tooling | Passed | 5 Python tests; mismatched APK/bundle hashes and resigning cloud modes cannot inherit startup proof. A Robo success cannot unlock the stronger direct-device packet gate; the separate-process driver now supplies that stronger proof. |
| Deletion and ownership rules | Passed locally | 14 Auth/Firestore emulator cases after the patched lockfile install; synthetic data only. |
| Test dependency advisories | Passed | Compatible lockfile resolution removes six moderate transitive advisories; fresh `npm ci` and audit report zero vulnerabilities. These Node packages are not shipped in the app. |
| Live backend and legal pages | Verified | Tested rules and Hosting deployed to `assistummah`; live privacy HTML, deletion inventory, JavaScript and deletion planner match source hashes. See [backend receipt](current-backend-verification.json). |
| Existing review account access | Verified through client SDK | Password login, nine own-document server reads, deletion marker and cleanup collection access, sign-out. No records changed; no credential values published. See [access receipt](current-reviewer-access.json). |
| Account session revocation | Passed | UID switch/sign-out clears pushed screens and dialogs; rapid A→B→A transitions still discard the old tree. Native scheduling is invalidated before replacement initialization. Cleanup failure cannot retain private routes. |
| Deletion status revocation | Passed | A remote marker or marker-listener failure closes private routes and dialogs. A named active deletion flow may finish. Recovery home replaces the old signed-in home. |
| Branding and support | Verified | Supplied icon exports, bundled Anek Bangla and Arabic font licenses, support `teamframecipher@gmail.com`. |
| APK and AAB signature | Passed | Existing upload certificate matches; hashes and sizes in [artifact receipt](current-release-artifacts.json). |
| API and ABI | Passed | Target API 36, minimum API 24, ARM64 included; debug and test flags absent. |
| 16 KB static compatibility | Passed | All 64-bit ELF load segments aligned; generated universal APK passes 16 KB ZIP alignment and signature validation. |
| Private/test material exclusion | Passed | Reviewer email/password literals and the native integration-test plugin are absent from the release bundle. |
| Exact candidate native startup | Passed in cloud | ARM64 Android 16 / 16 KB Test Lab run completed successfully. Login screenshot and Firebase logs inspected; no registrar errors or fatal crashes. Original uploaded checksum verified and no-resigning mode used. See [cloud startup receipt](current-testlab-startup.json) and [original captures](current-native-startup/README.md). |
| Independent installed hash / page-size syscall | Passed | The separate-process UI Automator driver measured the installed APK SHA-256 and 16 KB native pages on the device; both match this candidate. Production login, bundled privacy and Android Back passed in one JUnit case. See [controlled receipt](current-controlled-startup.json). The earlier injected runner failed from a test/app Kotlin class collision; the isolated driver avoids that collision without modifying the app. |
| Exact candidate signed-in native flows | Passed within scope | Real email/password login, own task read/save, server persistence, prayer/growth/Quran/tasbih navigation, Android notification permission denial, logout and A→B isolation passed on virtual ARM64 Android 16. Two disposable accounts only. See [native flow receipt](current-native-flows.json). This does not establish every native edit, OS delivery, Google OAuth or Play-installed behavior. |
| Older Android startup | Passed within scope | Original installed APK hash, login, bundled privacy and Android Back passed on ARM64 Android 8/API26 with 4 KB pages. [Receipt](current-native-legacy.json). This is not an authenticated-feature audit on Android 8. |
| Native deletion and interrupted recovery | Passed | Remote deletion marker closed an unsaved private dialog; Back did not restore private home. Native password confirmation finished deletion, then a cold restart allowed the other account. Server checks found nine root documents absent, eight owned collections empty, no activities, deleted Auth identity absent and only an empty anti-resurrection marker retained. Both synthetic fixtures were cleaned afterward. See [deletion receipt](current-native-deletion.json). |
| Play-installed build and Google OAuth | Manual gate | Register the Play app-signing certificate in Firebase and test the Play-installed app. Upload-key verification alone does not prove this. |
| Store declarations and listing | Prepared, unsubmitted | [Console handoff](console-handoff.md), [listing](store-listing.md), [Data safety](data-safety.md), artwork and release notes. Console stays manual by owner choice. |
| Current store screenshots | Open | Current signed-out and signed-in QA captures exist. The complete changed-screen set still needs re-capture from the candidate; widget renders and old profile captures are not current store artwork. |
| GitHub hosted CI | Blocked externally | Latest observed jobs never started because the GitHub account is locked for billing. [Run 42255887870](https://github.com/Rakindotcom/assistUmmah/actions/runs/42255887870) had zero steps in all jobs. Local checks passed; no hosted CI pass is claimed. |
| Firebase billing | Constraint preserved | Spark deployment only; no Cloud Functions or billing-plan upgrade. |
| iOS | Unverified, outside Android publishing | No Mac/iPhone testing setup is available; do not describe this as an iOS release audit. |

The complete local analyzer, Flutter, Python, Firebase and certificate logs are
under ignored `.local/logs/current-release-*`. The tracked JSON receipts contain
public evidence without private credentials. Historical local/profile native evidence remains available but belongs to an
earlier bundle. The current cloud startup receipt is independently scoped and
does not itself claim authenticated-home or physical-device coverage. The separate native flow receipt covers the listed authenticated checks.

## Delivered artifacts

- APK: `output/apk/rober-pothe-1.0.0-build4.apk` — installable signed production
  candidate for testing, not the offline productivity preview.
- AAB: `output/aab/rober-pothe-1.0.0-build4.aab` — signed candidate; do not promote
  until the remaining gates pass.
- SHA-256 sidecars accompany both files. Binaries remain outside Git.
- The strict Play upload packager was checked to reject stale native proof.
  The current independent installed-hash/page-size receipt now satisfies its
  startup gate. The resulting packet is for manual internal-test preparation;
  it is not public release approval. Historical native
  captures are exported into a separate reference folder, never as current
  store screenshots.

## Remaining publishing checks

1. Finish OS notification checks, then install the Play-generated build
   from an internal track. Check email and Google login, logout/account switch,
   core edits and reloads, deletion and interrupted deletion recovery.
2. Test notification/location denial and revocation, approximate scheduling,
   reboot/Doze, timezone/day changes, keyboard/back navigation, large text,
   TalkBack, edge-to-edge layout, launcher/splash and modest-phone performance.
3. Verify optional diagnostics off/on/off and a controlled Crashlytics receipt.
4. Re-capture changed store screens. Complete app access, Data safety, content
   rating, target audience, ads and developer identity in Console. Confirm code
   **4** is greater than every previously used code before uploading.
5. Inspect Play's SDK/ABI/pre-launch reports and complete the applicable closed
   testing and production-access requirements. Do not infer account eligibility
   from source code.
6. Resolve the GitHub account lock and rerun hosted checks before merging the
   draft PR under a CI-required workflow.

Current official references: [target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878),
[16 KB compatibility](https://developer.android.com/guide/practices/page-sizes),
[personal-account testing](https://support.google.com/googleplay/android-developer/answer/14151465).
