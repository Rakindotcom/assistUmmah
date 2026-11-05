# Offline productivity preview

`lib/main_productivity_preview.dart` is a separate Flutter entrypoint for the
new workspace while production cutover remains gated. It does not initialize
Firebase or call the migration fence. Its local database uses the
`productivity-preview` account namespace; production account records are not
imported or modified. A visible `PREVIEW` banner distinguishes it from the
normal application.

Build with the Android SDK and a full JDK 17:

```sh
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_HOME="$PWD/.local/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$PATH"
flutter build apk --release -t lib/main_productivity_preview.dart
```

The APK uses the same Android package ID and signing key as the existing
release. Installing it replaces the installed app binary; reinstalling the
normal APK restores the normal entrypoint. The two experiences keep separate
local account namespaces, but an uninstall can erase all local app data. Use
the app's export before uninstalling either build. Preview data is local-only
and does not sync to the production account.

This build is for native UI review, not Play Store publication. The new root
still needs live rules, migration and route cutover, privacy/deletion checks,
and physical-device and iOS verification. The APK's package metadata,
signature and ZIP alignment were checked locally. No Android emulator was
configured on the build host and `/dev/kvm` was absent, so launch and
interaction on Android hardware remain unverified.
