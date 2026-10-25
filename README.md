# Ummah Assist

Flutter app inspired by the `muhasaba.org` accountability flow: tasks, prayer tracking, iman/life growth checklists, emergency contacts, settings, and report summaries.

## Run

Flutter platform runner files have been generated. Install Flutter and run:

```bash
flutter pub get
flutter run
```

## Firebase

The app uses these Firebase services:

- Firebase Authentication for email/password and Google sign-in.
- Cloud Firestore for user-scoped app data.

Firebase is configured against project ID `assistummah`. The web app uses
`lib/firebase_options.dart`. The Android and iOS Firebase config files are
ignored by Git and must be downloaded on each new checkout. After running
`firebase login`, use:

```powershell
./scripts/setup_firebase.ps1
```

On macOS or Linux, the equivalent commands are:

```bash
firebase apps:sdkconfig ANDROID '1:1077713975334:android:b93df4d24c8a1356e80ee7' --out android/app/google-services.json --project assistummah
firebase apps:sdkconfig IOS '1:1077713975334:ios:f367f1336f5c5acae80ee7' --out ios/Runner/GoogleService-Info.plist --project assistummah
```

Email/password authentication uses these files. Google sign-in is configured
for the registered Android debug certificate and the iOS app. Run the setup
script again after changing Firebase OAuth settings. Android release builds
need the release certificate's SHA-1 and SHA-256 fingerprints registered in
Firebase before Google sign-in works in those builds. Web Google sign-in uses
Firebase Auth's popup flow.

Firestore rules are included in `firestore.rules`.

## Reminders

On Android and iOS, the settings switch schedules local reminders for tasks at
8:00, the prayer log at 20:00, and growth at 21:00 in the device's local time.
The app requests notification permission when reminders are enabled. These are
check-in prompts, not calculated prayer-time alerts.

## Android release signing

Release builds no longer use the debug signing key. To sign a distributable
build, create `android/key.properties` with the following values and keep the
keystore backed up outside this repository:

```properties
storeFile=../path/to/upload-keystore.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

`storeFile` is relative to `android/`. Both the properties file and keystore
files are ignored by Git. Without these values, release output is unsigned.

## App Name

The Flutter and native app labels are `Ummah Assist`.
