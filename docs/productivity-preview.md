# Offline productivity preview

`lib/main_productivity_preview.dart` is a separate Flutter entrypoint for the
new workspace while production cutover remains gated. It does not initialize
Firebase or call the migration fence. Its local database uses the
`productivity-preview` account namespace. The Android `preview` flavor uses
`com.rakindotcom.ummah_assist.preview`, removes the native Firebase startup
provider and disables notification operations. A visible `PREVIEW` banner and
preview app label identify it. Gradle rejects a preview entrypoint built under
the production flavor or a preview package built with the normal entrypoint.

Build with the Android SDK and a full JDK 17:

```sh
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME="$PWD/.local/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
tool/build_productivity_preview.sh
```

The preview installs alongside the normal app and has its own Android storage
and notification namespace. Its data remains local and does not sync to the
production account. Export any preview work you need before uninstalling it.
The earlier 5 November preview built under the production package has been
superseded; use the isolated flavor build.

This build is for native UI review, not Play Store publication. The new root
still needs live rules, migration and route cutover, privacy/deletion checks,
and physical-device and iOS verification. The APK's package metadata,
signature and ZIP alignment were checked locally. No Android emulator was
configured on the build host and `/dev/kvm` was absent, so launch and
interaction on Android hardware remain unverified.
