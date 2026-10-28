# Release preparation — রবের পথে

Updated 28 October 2026 (Asia/Dhaka).

## Current decision

The current signed Android bundle passes static artifact checks. Its fresh
runtime smoke is pending: the last attempt on an earlier bundle did not reach
the login screen within the test window, and emulator diagnostics could not
yet be read.
Production approval also requires Android device testing and the Play Console
gates below. A browser or widget pass does not establish native delivery.
The older generated upload packet has been moved into the ignored `.local`
archive; no packet for the current bundle will be issued until its runtime
smoke passes.

Verified locally through 28 October 2026:

- Flutter analyzer: no issues; full Flutter suite: **288 passed**.
- Firebase emulator integration suite: **7 passed**, covering complete deletion,
  interrupted recovery, multiple batches, owner isolation, recent authentication,
  immutable markers, legacy records and anonymous denial.
- Release input checks: 45 brand exports, store graphics, support contact,
  Spark configuration, deletion inventory, OAuth and signing inputs pass.
- Signed AAB: `1.0.0+1`, API 36, minimum API 24, ARM64 present. Bundletool and
  upload signature validation pass; all nine native libraries were inspected.
- Generated universal APK: signature and `zipalign -c -P 16 -v 4` pass. All
  64-bit native ELF load segments have at least 16 KB alignment. Startup of
  this exact bundle needs a successful repeat smoke; Play-generated APK tests
  remain open.
- Live policy and deletion form load successfully; the form initializes without
  browser console errors. Browser deletion was verified using synthetic emulator
  data only.
- Native Android 16 (API 36, x86_64, 16 KB pages) audit: startup, bundled policy,
  diagnostics initially off, notification initialization/cancellation, zero
  scheduling without notification permission, preference save/load/removal,
  reviewer password login, own-profile server read and sign-out pass.
- Six native 720×1280 phone captures use the normal signed-in production widgets
  and repository with fabricated review-account records. They are profile-mode
  captures, not captures of a Play-installed build. See
  [capture provenance](native-captures/README.md) and
  [native audit evidence](native-verification.json).
- The updated profile audit also exercised live seven-day Firestore reporting and
  recorded one emulator timing sample. Sign-in tap to ready dashboard took
  6.46 s, the live report took 0.83 s, and 9 of 50 navigation frames exceeded
  the raster budget. These numbers are not physical-device benchmarks. The
  task composer was changed after this profile APK was built; its retry and
  360 px layout are covered by widget tests.
- A prior signed production APK was installed independently: its bytes matched
  that prior bundle, Firebase initialized, and the login controls appeared in
  Android's accessibility tree on API 36 / 16 KB. An earlier release attempt
  exposed an R8 reflection bug: Firebase's manifest registrars had lost their
  public constructors. A targeted keep rule fixed it. The
  [prior signed release evidence](signed-release-smoke.json) is not evidence for
  the current bundle; the release packager checks matching hashes.
- A dedicated reviewer account is provisioned and its private credentials are
  stored at `.local/play-reviewer-credentials.json` (0600). They are excluded
  from Git and the upload packet. No Google account/mailbox was created and no
  verification/reset-email API was requested.
- Task filters use one horizontally scrollable row on small screens. Priority
  choices and the task-card heading are more compact, keeping task content
  visible sooner. Narrow-screen scheduling still works through a tested swipe.
- New task drafts stay open until the write succeeds; a failed write can be
  retried without losing text or recurrence. The task identity remains stable
  across retries, preventing duplicates when a committed write loses its
  response.
- The Tasks tab refreshes server data when reopened or when the active app
  resumes. A failed refresh keeps the last loaded list and offers retry;
  delayed older responses cannot replace newer task data. Preview mode skips
  the unnecessary server refresh.
- Contacts refresh when reopened or when the active app resumes. Phone users
  can pull to refresh without leaving the screen. A failed refresh retains
  the previous list and offers retry; preview contacts survive a refresh.
- Growth checklist edits show pending or failed save status. A tab refresh
  preserves an unsaved draft, and failed changes can be retried in place.

See [bundle evidence](bundle-verification.json) and
[merged manifest](bundle-verification.manifest.xml). The signed bundle is at
`build/app/outputs/bundle/release/app-release.aab`; a locally installable universal
APK is at `.local/app-release-universal.apk`.

## Completed implementation

- Bengali in-app policy available before login and from settings, backed by the
  same source content as the public page.
- In-app and external account deletion with identity verification, explicit
  irreversible-action acknowledgement, paged deletion and interrupted recovery.
- Nine account-owned document paths, four nested daily collections and legacy
  owner-attributed activity records are removed before the Auth identity.
- An empty UID-keyed marker freezes new writes during deletion and prevents old
  sessions or queued writes from recreating records. Its retained security purpose
  and absence of profile/activity fields are disclosed in the policy.
- Spark-compatible client APIs throughout; no Cloud Functions, Blaze upgrade,
  subscription, domain purchase or paid backend was introduced.
- Notification errors cannot prevent Firebase sign-out. Google session cleanup is
  independent; changed account UIDs get distinct home/widget state.
- Refreshed Android Firebase OAuth configuration and explicit server client ID.
  The new upload-key SHA-1/SHA-256 fingerprints are registered in Firebase.
- Startup failure recovery, retry and an accessible policy/contact route.
- Optional native Crashlytics reporting, disabled by default, with a settings
  opt-in and rollback on preference-save failure. App reports strip exception
  messages and attach no custom account/profile/activity content.
- Store icon and feature graphic exported from the supplied artwork with Anek
  Bangla shaping. Native store screenshots remain an independent gate.
- Quality and manually dispatched Android release workflows prepared locally.
  They become active after the repository changes and required secrets are set
  up on GitHub; no remote workflow run is claimed.

## Published pages and contact

- [Privacy policy](https://assistummah.web.app/privacy)
- [Account deletion](https://assistummah.web.app/delete-account)
- Support: **teamframecipher@gmail.com**

Hosting and the tested Firestore rules were deployed to `assistummah`. No billing
plan change was made. Firebase's daily Spark quotas still apply; interrupted
operations expose retry/resume rather than pretending to succeed.

## Deletion semantics

Deletion starts only after password/Google reauthentication and confirmation.
The empty Firestore marker is created transactionally. Normal creates/updates
are then denied for this UID. The owner can still enumerate/delete its records,
including legacy activities, for cleanup. The marker cannot be forged for
another UID, edited or removed by a client. Auth is deleted last.

Keep the app/page open until success. If connectivity or a quota interrupts the
operation, the account remains available for reauthentication and resumption;
the app blocks normal use once it sees the marker. The public page repeats the
same bounded, idempotent cleanup. There is no background worker on the free plan.

Local prayer/location and alert preferences are removed best effort. Remaining
Firestore disk cache is scheduled for clearing before listeners start on the
next launch. Other devices can retain offline cache until their app data is
cleared or the app is removed; the policy explains this limitation.

See [browser verification](deletion-web-verification.json) and
[mobile receipt](deletion-web-proof.jpg). This proof uses only the `demo-ummah`
emulator project and synthetic data. No real account was deleted during testing.

## Reproduce quality gates

```sh
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --concurrency=2
python3 tool/generate_brand_assets.py --check
python3 tool/generate_release_assets.py
python3 tool/release_preflight.py
```

For authorization/deletion integration tests, install Node 24.12+ and Java,
then run from the repository root:

```sh
npm --prefix test/firebase ci
firebase emulators:exec --project demo-ummah --only auth,firestore 'npm --prefix test/firebase test'
```

These tests refuse to run without emulator endpoints. The Node-only gRPC
transport override fixes the certificate-validation advisory in the test SDK.
It is not deployed or included in the browser page.

## Build and validate Android

Use a full JDK 17 with `javac`, Android SDK Platform 36 and NDK 28.2.13676358.
The local SDK is in the ignored `.local/android-sdk` directory. Gradle worker
count and memory are bounded for this development machine.

```sh
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME="$PWD/.local/android-sdk"
export PATH="$JAVA_HOME/bin:$PATH"
tool/build_android_release.sh
```

The official bundletool 1.18.3 archive is expected at `.local/bundletool.jar`.
Its SHA-256 is
`a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29`.
The workflow downloads and checks this digest before use.

`tool/verify_android_bundle.py` validates the bundle, upload signature, package,
API target, ARM64 presence and 64-bit ELF load alignment. It writes a manifest
and a JSON result. `tool/verify_android_apk.py` then generates a signed universal
APK using temporary private password files, checks its signature and 16 KB ZIP
alignment, and adds those results to the report. A 16 KB device run and testing
the Play-generated APKs are separate checks.

Bundle verification invalidates native runtime claims when the AAB hash changes.
A successful signed smoke records that exact hash in the bundle, emulator and
summary evidence. The upload packager requires all four records to agree.

With the dedicated `rober_pothe_audit_16k` emulator running as `emulator-5556`,
run `python3 tool/smoke_android_release.py`. The script clears only that
emulator's app data, compares the installed APK hash, and requires a ready
login screen, Firebase initialization, and no registrar error in the log.

## Private signing material

The upload key and credentials were created locally once, with mode 0600:

- `android/upload-keystore.jks`
- `android/key.properties`

Both are ignored by Git. **Back them up securely before the first Play upload.**
Do not regenerate the key for routine releases, commit it, attach it to an issue,
or paste passwords into logs. The public certificate/fingerprints in this folder
are safe to use for registration and do not contain the private key.

The manual GitHub release workflow expects these repository/environment secrets:
`FIREBASE_ANDROID_JSON_BASE64`, `ANDROID_UPLOAD_KEY_BASE64`, and
`ANDROID_KEY_PROPERTIES_BASE64`. The properties must reference
`storeFile=upload-keystore.jks`. The workflow does not publish to Play automatically.

## Required owner/device gates

The owner has chosen to keep Play Console work manual. Use the prepared
[Console handoff](console-handoff.md) and [release notes](release-notes-bn.txt).
`python3 tool/package_play_release.py` assembles the validated AAB, public
artwork and instructions under the ignored `dist/play-store/` folder. Private
signing credentials are excluded from that packet.

1. Install the signed release through a Play internal test track. Test email and
   Google login, cancellation, reset, logout, switching accounts and restoration.
2. Register the **Play App Signing app-signing certificate** SHA-1/SHA-256 in
   Firebase. This is distinct from the upload certificate already registered.
3. Exercise location/notification/exact-alarm permission denial and revocation,
   manual location, approximate alarms, reboot, Doze and timezone/date changes.
4. Test deletion and interrupted resumption from both app and web, and verify
   another account remains isolated. Confirm local/cache behavior on two devices.
5. Verify Android 16 edge-to-edge, actual IME, system back, large text, TalkBack,
   launcher/splash/themed/status icons, and modest-device performance/ANRs.
6. Confirm optional diagnostic reporting off/on/off behavior and receipt of a
   controlled test report in Crashlytics. Do not crash a real user's session.
7. Inspect Play's native SDK/ABI/16 KB warnings and pre-launch report. Emulator
   16 KB profile flows passed on an earlier build; the current signed APK startup,
   physical ARM64 and Play-signed builds remain unverified. No physical Android
   device is connected here.
8. Review the six prepared native captures. Recapture any screen that differs
   in the final Play-installed build. Browser previews are not store screenshots.
9. Complete [Data safety preparation](data-safety.md), app-access credentials,
   content rating, target audience, ads declaration, developer verification and
   the [store listing](store-listing.md) in Console. Confirm version code `1`
   is unused for this app.
10. If the personal developer account was created after 13 November 2023, complete
    the applicable 12-tester/14-day closed test and production-access application.

Play Console and a native runtime are required to close these gates. App Check
configuration, field validation and quota/abuse monitoring should be reviewed
before a broad rollout; no unverified enforcement was enabled against users.
