# Ummah Assist

Flutter app inspired by the `muhasaba.org` accountability flow: tasks, prayer tracking, iman/life growth checklists, emergency contacts, settings, and report summaries.

## Run

Flutter platform runner files have been generated. Run the app with:

```bash
flutter pub get
flutter run
```

This workspace used Flutter from `/home/rakin-shahriar/development/flutter/bin/flutter`.

## Firebase

The app uses these Firebase services:

- Firebase Authentication for email/password and Google sign-in.
- Cloud Firestore for user-scoped app data.

Firebase is configured against project ID `assistummah`. Firebase project display names can use mixed case, but project IDs are lowercase, so `assistUmmah` maps to `assistummah` here.

FlutterFire generated:

- `lib/firebase_options.dart`
- `android/app/google-services.json`

For Android Google sign-in, add your debug/release SHA-1 and SHA-256 fingerprints in Firebase Console so `google-services.json` includes OAuth clients.

Firestore rules are included in `firestore.rules`.

## App Name

The Flutter app title is `Ummah Assist`. After platform runners are generated, verify the native app labels are also `Ummah Assist` in Android/iOS runner files.
