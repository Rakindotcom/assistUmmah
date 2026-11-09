# Release preparation — রবের পথে

Updated 6 November 2026 (Asia/Dhaka).

## Current release scope and decision

The owner confirmed on 6 November 2026: **finish and verify the current app for
release**. The full `gap.md` productivity roadmap is outside this release.
The production entry is `lib/main.dart` → `AppBootstrap` → `AuthGate` →
`HomeShell`. The new productivity root remains hidden and the separate preview
package must not be uploaded as this app.

The current candidate is **1.0.0+4**, package
`com.rakindotcom.ummah_assist`, target API 36 and minimum API 24. See the
[release audit](current-release-audit.md) and the machine-readable
[verification summary](verification-summary.json) for current results and
remaining gates. Earlier native screenshots, profile measurements and startup
receipts are historical evidence and do not establish this candidate's runtime.

The signed production AAB is
`build/app/outputs/bundle/productionRelease/app-production-release.aab`.
Its signed universal APK is `.local/app-release-universal.apk`; a user-facing
copy is exported under `output/apk/`. [Bundle verification](bundle-verification.json)
binds static checks to the exact AAB hash. The current APK passed a signed-out
ARM64 / 16 KB [Test Lab startup check](current-testlab-startup.json). Its login
screen and Firebase logs were inspected. The separate-process [controlled
startup test](current-controlled-startup.json) then verified the installed APK
hash, measured 16 KB pages, opened bundled privacy and returned with Android
Back. Scoped [signed-in native checks](current-native-flows.json) also passed.
Native deletion/recovery, alarm registration/cancellation and diagnostics consent
also passed. Timed OS delivery and manual Play gates remain open; the
stronger startup evidence now permits a manual internal-test upload packet.

Current functionality includes the prayer-first home with offline prayer and
fasting calculations, prayer and Qaza tracking, tasks and recurrence, Quran
reading goals, ready-made and custom tasbih, sourced duas, growth checklists,
calendar history, reports and trends, manually entered contacts, settings,
optional device reminders, authentication, privacy and account deletion.
Bangla uses the bundled Anek Bangla font and Bangla numerals. Native Arabic
content uses bundled Noto Naskh Arabic. Both font licenses are included.

Account changes remove the entire previous navigation tree and invalidate
notification scheduling before a replacement account can initialize. A remote
deletion marker or marker-listener failure removes pushed private screens and
dialogs and cancels native reminders. An active named deletion route may finish;
it cannot restore the signed-in home after deletion is marked. Optional native
cleanup failures cannot veto sign-out or keep private screens accessible.

Current phone widget captures and their scope are documented in
[UI review](../ui-review.md). They cover the redesigned home, daily prayer
status, dua library, fasting sheet and tasbih. They are not Play-installed
screenshots or proof of notification delivery on a phone.

## Completed implementation

- Bengali in-app policy available before login and from settings, backed by the
  same source content as the public page.
- In-app and external account deletion with identity verification, explicit
  irreversible-action acknowledgement, paged deletion and interrupted recovery.
- Nine account-owned document paths, four nested daily collections, four
  additional workspace collections and legacy owner-attributed activity records
  are removed before the Auth identity. Workspace cleanup is defensive and does
  not enable the hidden productivity UI.
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
  Bangla shaping. Current native screenshots are documented separately in
  `current-store-captures/README.md`.
- The GitHub quality workflow runs Flutter checks and Firebase account-lifecycle
  emulator tests on pushes. A separate manually dispatched Android release
  workflow requires the configured release secrets for remote signing. Local
  release signing uses ignored private credentials.

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
A successful direct signed smoke records that exact hash in the bundle, emulator and
summary evidence. Cloud startup receipts are separate: upload checksum, no-resigning
mode and visual/log checks are required and their claims invalidate when either
artifact hash changes. A Robo success does not satisfy the installed-hash gate. The separate-process
UI Automator driver can supply an independent installed-file hash and native
page-size measurement without modifying the production APK. The upload packager requires all four records to agree.

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
7. Inspect Play's native SDK/ABI/16 KB warnings and pre-launch report. The current
   APK has matching ARM64 Android16/16 KB, Android8/4 KB and physical Pixel8
   Android14 startup receipts. Physical authenticated/OS flows and the
   Play-signed build still require verification.
8. Review the four current `current-store-captures/` phone images. Recapture any screen that differs
   in the final Play-installed build. Browser previews are not store screenshots.
9. Complete [Data safety preparation](data-safety.md), app-access credentials,
   content rating, target audience, ads declaration, developer verification and
   the [store listing](store-listing.md) in Console. Confirm candidate version code `4`
   is greater than every code already used for this app.
10. If the personal developer account was created after 13 November 2023, complete
    the applicable 12-tester/14-day closed test and production-access application.

Play Console and a native runtime are required to close these gates. App Check
configuration, field validation and quota/abuse monitoring should be reviewed
before a broad rollout; no unverified enforcement was enabled against users.
