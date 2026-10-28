# Native capture provenance

Captures are produced by `integration_test/native_audit_test.dart` and the
official Flutter integration driver, running Android on an isolated emulator.
They are not browser renderings, generated mockups or images of real user data.

- `01-sign-in.png` uses the app's normal Firebase startup and signed-out screen.
  No account is created and no production record is written.
- `02-dashboard.png` through `06-dhikr.png` use the normal signed-in app,
  production widgets and real Firestore repository. The dedicated review account
  contains fabricated records; no real person's activity is shown. The preview
  badge is explicitly checked to be absent. The production entry point is used.
- The audit runs in **profile mode**, allowing the official Flutter driver to
  verify assertions and export screenshots. It is not a Play-installed build.
- `../native-verification.json` is written only after a successful test run.
  Its presence and the six captures are checked when packaging a release.

The six captures are 720×1280. The release packager verifies Play-compatible pixel
dimensions and aspect ratio.
Original SDK captures in the workspace retain their opaque alpha channel. The
upload packet contains lossless 24-bit RGB PNG exports, with unchanged dimensions
and RGB pixels, as required by the [Play screenshot format](https://support.google.com/googleplay/android-developer/answer/9866151).
`export-verification.json` in the packet records both hashes. Upload the packet's
copies; no visual content is edited or resized.
Review the screenshots visually before uploading. Recheck important screens
after installing the actual Play-signed internal build; the capture test does
not prove Google login, notification delivery, permissions, reboot recovery,
TalkBack or behavior on a physical device.

To reproduce on an isolated emulator with no signed-in app account:

```sh
flutter drive --profile --no-dds \
  --dart-define-from-file=.local/play-reviewer-credentials.json \
  --driver=test_driver/native_audit.dart \
  --target=integration_test/native_audit_test.dart \
  --device-id=emulator-5556
```

Set `ANDROID_HOME` to the SDK and use JDK 17 as described in the release guide.
The private credential file is used only for the dedicated review identity's
native password form, own-profile read and sign-out checks. It is never copied
to the upload packet or passed to a production build. No password is captured
in the screenshots.
Form text is entered through Flutter's simulated text-input channel on the
headless emulator. Actual system keyboards and autofill still need device QA.

The helpers `tool/provision_play_reviewer.cjs` and
`tool/seed_review_history.cjs` prepare this dedicated identity and its sample
history using ordinary account-scoped client permissions. They require the
Node test SDK dependencies. The history helper checks the expected fixture UID
and display name before writing; do not repurpose it for real user accounts.

Always use a disposable emulator with notification permission ungranted and an
explicitly cleared app state. On this small-memory host, compile first with the
emulator stopped, stop Gradle, boot the emulator, then run the driver with
`--use-application-binary=.local/native-audit.apk`. Do not compile and run the
emulator concurrently if the host is nearly out of RAM/swap.
