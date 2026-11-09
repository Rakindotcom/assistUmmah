# Current production phone screenshots

Five reviewed captures of build 4: home, prayer tracking, growth, Quran
tracking and tasbih. See `../current-native-reminders.json` for the completed device run.
The original signed APK ran on virtual ARM64 Android 16 with 16 KB pages.
The actual device viewport was set to 720×1280 pixels / density 320 before
launch. These are native captures, not browser/widget renders or mockups.

Screens show synthetic starter data. Home and prayer show the calculated
Dhaka schedule after actual manual UI setup, sourced from
`../current-native-location-diagnostics.json`. They contain no passwords or account email addresses. Each selected
screen was visually reviewed after download. The original tasbih transition frame was rejected. Its accepted replacement
comes from `../current-native-delivery.json`, after waiting for the Flutter frame
to reach the compositor. Per-screen provenance identifies that separate run.

Exports are opaque 24-bit RGB PNGs. Only the opaque alpha channel was removed;
RGB pixels, dimensions and content are unchanged. Source/export hashes are in
`export-verification.json`. Final Play-installed behavior and the locale's
Console preview still require manual review before publication.
