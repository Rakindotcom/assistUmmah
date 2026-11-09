# Signed production APK audit harness

This standalone Android test APK uses AndroidJUnitRunner and UI Automator to
exercise the original, minified Flutter release. It adds no test plugin or
entry point to the production APK. The runner instruments its own package and
drives the production app from a separate process. This avoids class-loader
collisions between the runner's libraries and the app's minified Kotlin classes.
It uses the existing upload certificate; the target APK is not re-signed.
The harness is test-only and must never be distributed as the app.

## Build

From the repository root, with Android SDK 36 and a full JDK 17:

```sh
bash tool/build_native_release_harness.sh
```

Private signing inputs are read from ignored `android/key.properties` and its
existing keystore. No credentials are embedded in the test APK. Output:
`test/native_release_harness/build/outputs/apk/debug/SignedReleaseAudit-debug.apk`.

## Startup test arguments

- `expectedApkSha256`: required SHA-256 of the validated production APK.
- `expectedVersionCode`: required candidate version code.
- `expectedPageSize`: optional expected bytes per native memory page, e.g. 16384.

The test independently hashes the installed target APK, reads the native page
size through `Os.sysconf`, opens the normal launcher, verifies the Bangla login
screen, opens the bundled privacy policy, and returns using Android Back.
It writes `receipt.json`, original PNG captures and UI hierarchies under the
test package's external files directory, in `release-audit/`. The page-size
syscall runs in the on-device test process; the installed hash is read from the
production package's APK file.

Use a disposable emulator or a Test Lab device with fresh app data. Specify
`androidx.test.runner.AndroidJUnitRunner`, the class
`com.rakindotcom.ummah_assist.release_harness.SignedReleaseAuditTest`, and
disable automatic permission grants and orchestration. Pull
`/sdcard/Android/data/com.rakindotcom.ummah_assist.release_harness/files/release-audit` after the run.
The current automated cloud operator uses the existing Firebase CLI login,
checks that project billing is disabled, and submits an idempotent matrix.

The equivalent invocation with the official gcloud CLI is:

```sh
gcloud firebase test android run --project assistummah --type instrumentation \
  --app output/apk/rober-pothe-1.0.0-build7.apk \
  --test test/native_release_harness/build/outputs/apk/debug/SignedReleaseAudit-debug.apk \
  --device model=MediumPhone_ps16k.arm,version=36,locale=bn_BD,orientation=portrait \
  --environment-variables expectedApkSha256=5252f571ef3ad5a873f7690867a34f4532d5a0440c061f6eb790aa797126e8a6,expectedVersionCode=7,expectedPageSize=16384 \
  --directories-to-pull /sdcard/Android/data/com.rakindotcom.ummah_assist.release_harness/files/release-audit \
  --no-use-orchestrator --no-auto-google-login --timeout 3m
```

Check the project's current billing state and free quota before submission.
Do not link a billing account or upgrade this project's Spark plan.

Compilation alone is not a passing device test. Accept a receipt only when its
installed hash matches the exported APK, its required assertions passed, and
the server run is complete. Failure screenshots/hierarchies remain private;
never publish captures of entered credentials or account settings.

References: [AndroidJUnitRunner](https://developer.android.com/training/testing/instrumented-tests/androidx-test-libraries/runner),
[UI Automator](https://developer.android.com/training/testing/other-components/ui-automator).

## Signed-in and recovery tests

Select one method per fresh-device run:

- `SignedInReleaseAuditTest#signedInIsolationAndPermissions`: authenticates A,
  saves a task, navigates core screens, denies Android notification permission,
  signs out, then checks B's own task and absence of A's tasks.
- `SignedInReleaseAuditTest#remindersConsentAndNativeCaptures`: grants Android
  notification permission, verifies a pending OS alarm and cancellation on
  sign-out, checks diagnostics off/on/restart/off, and captures actual
  720×1280 device viewports. Alarm registration is not proof of timed delivery.
- `SignedInReleaseAuditTest#scheduledDeliveryAndOsRevocation`: grants daily
  reminder permission, backgrounds the app, advances the disposable device's
  wall clock past the next task reminder's inexact window, and checks the
  original app's notification in System UI. It restores wall clock/automatic
  time, revokes notification permission through Android, checks explicit opt-out
  cancellation, and captures the loaded tasbih view. No app broadcast or
  notification is injected. This establishes a controlled clock-change path,
  not natural-clock latency, reboot/Doze or all OEM behavior.
- `SignedInReleaseAuditTest#prayerExactAlarmPermissionTransitions`: uses the
  second disposable account on a separate device. It refuses the app's real
  Android exact-alarm request, checks approximate prayer scheduling, grants and
  revokes exact access through OS app-ops, and checks recovery to inexact
  scheduling after relaunch. Prayer opt-out must clear the native queue. The
  original app-op is restored. UI status plus registered alarms establish these
  transitions, not timed prayer delivery or reboot behavior.
- `SignedInReleaseAuditTest#naturalClockDeliveryInDoze`: selects a real device
  timezone with an upcoming existing 08:00/20:00/21:00 reminder, grants notification
  permission through Android, and verifies the matching epoch in Android's alarm
  queue. It backgrounds the unchanged app, unplugs the disposable device's battery
  simulation and confirms forced deep Doze using Android's documented test commands.
  It observes Notification Manager with the real clock until 12 minutes after due.
  A successful driver cleanup alone does not prove delivery: require
  `naturalClockNotificationPosted`, unchanged wall/elapsed clocks, and confirmed
  deep Doze at observation. No-arrival is inconclusive outside that bounded
  observation window because these reminders are intentionally inexact. The
  finally block restores battery/idle/timezone settings. This does not reboot the
  phone or establish delivery across all Android/OEM policies.
- `SignedInReleaseAuditTest#locationFallbackAndControlledCrash`: denies Android
  location permission, saves manual Dhaka coordinates/timezone in the app,
  captures calculated prayer views, explicitly enables optional diagnostics,
  asks Android to crash only the disposable app process, relaunches for upload,
  then disables diagnostics and signs out. A successful driver run alone is
  not proof of a received report; independently check Crashlytics afterward.
- `SignedInReleaseAuditTest#deletionRecoveryAndRouteRevocation`: opens an
  unsaved task dialog, creates A's deletion marker through the ordinary owner
  REST API, checks private-route revocation and recovery, completes deletion
  using the app's password confirmation, then cold-starts and checks B.

Signed-in methods require `expectedApkSha256` and runtime-only arguments `accountAEmail`,
`accountAPassword`, `accountATask`, `accountBEmail`, `accountBPassword`,
`accountBTask`. Deletion also requires `firebaseApiKey` and `accountAUid`.
The signed-in isolation case checks `expectedPageSize`, allowing the same
method to verify physical 4 KB and virtual 16 KB devices.
Only disposable `teamframecipher+native-` fixture aliases are accepted; deletion
checks that the authenticated UID matches the explicitly supplied fixture UID.
Never use a reviewer or real user's account. Credentials belong in private
runner inputs, never in source, artifacts or shell command arguments. The
operator must remove fixture identities and data after completed testing.

`flows-receipt.json` reports the assertions actually completed. A UI save must
also be confirmed through server reads before reporting persistence. Page
navigation does not establish every feature's mutation or OS behavior.

The delivery test uses Android's documented implementation of the
[`alarm` shell commands](https://android.googlesource.com/platform/frameworks/base/+/ff7e31ff9683287af050a9d96c431146017808e3/apex/jobscheduler/service/java/com/android/server/alarm/AlarmManagerService.java).
Run it only on a disposable test device. Finally blocks restore clock settings
and viewport, including on failure. Screenshots wait for accessibility idle and
an additional presentation frame interval because Flutter semantics can appear
before the rendered frame reaches the screenshot compositor.

## Current candidate suite

`ReleaseCandidateSuite#verifyCurrentRelease` runs startup, signed-in flows,
reminder consent/cancellation, manual location, controlled-clock delivery,
in-process device timezone changes and deletion last in one device allocation.
It clears only the disposable device's production app data between cases and
resets only fixture A's reminder preferences through its authenticated owner
API. No crash is injected by this suite. The opt-in crash-report case is run
separately so an expected crash cannot hide an unexpected suite failure.

The suite additionally requires `firebaseApiKey`, `accountAUid` and
`suiteVerifyPersistedTask=true`. Before deletion it checks the earlier native
task save through a fresh owner-authenticated server read. Each case writes its
own named receipt; a suite pass requires every case to return successfully.
`timezoneRefreshWithoutRestart` initializes prayer settings, then verifies the
pending native alarms retain local 08:00, 20:00 and 21:00 schedules after device
zone changes to New York and Dhaka while the original app process and Settings
screen remain alive. Automatic timezone settings are restored afterward.
