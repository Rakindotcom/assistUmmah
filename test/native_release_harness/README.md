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
  --app output/apk/rober-pothe-1.0.0-build4.apk \
  --test test/native_release_harness/build/outputs/apk/debug/SignedReleaseAudit-debug.apk \
  --device model=MediumPhone_ps16k.arm,version=36,locale=bn_BD,orientation=portrait \
  --environment-variables expectedApkSha256=61a3109b27a344ee40167a2f705f38587dad50b11f812a597cc624ad7dfd279b,expectedVersionCode=4,expectedPageSize=16384 \
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
