# রবের পথে — app identity

The supplied emerald, cream, and gold artwork is the source of the app identity.
The original file is preserved at `assets/brand/source.png`. Flutter's visible
name and logo path are centralized in `lib/src/app_identity.dart`.

## Surfaces

- Flutter headers and authentication branding use the bundled artwork. Sign-up
  copy, the application title, and the settings footer use **রবের পথে**.
- Android has five legacy and round launcher sizes, five adaptive foreground
  sizes, Android 13 monochrome support, and branded light/dark launch screens.
- Android notifications use a white vector rendition of the arch, star, and
  path, rather than an opaque launcher image as a status-bar icon. Its resource
  is explicitly retained during release shrinking.
- iOS has the complete AppIcon catalog and three opaque launch-image sizes,
  with the new name in both native display-name fields.
- Web has the new document/PWA names, favicon, Apple touch icon, regular icons,
  maskable icons, and emerald manifest/theme colors.

Adaptive and maskable exports add padding to protect the mark from system
masks. The color artwork is resized from the supplied source without being
redrawn. Android's themed and notification vectors retain the mark's three
elements in monochrome. See Android's official
[adaptive-icon guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive)
and [launch-screen guidance](https://developer.android.com/develop/ui/views/launch/splash-screen).

## Regenerate and verify

```bash
# Python 3 with Pillow installed
python3 tool/generate_brand_assets.py
python3 tool/generate_brand_assets.py --check
```

The exporter regenerates 45 image assets, including every filename referenced
by the iOS AppIcon catalog. `--check` verifies each image's dimensions, mode,
and pixel contents against the source. Vector and platform XML resources live
alongside the generated images. The full-resolution source is not bundled as
a Flutter runtime asset.

Earlier UI-review screenshots retain the historical branding; the rebrand's
phone previews are recorded separately:

- [Phone dashboard](ui-screenshots/rober-pothe-mobile.jpg)
- [Sign in](ui-screenshots/rober-pothe-auth-mobile.jpg)
- [Sign up](ui-screenshots/rober-pothe-signup-mobile.jpg)

## Verification

- All 45 generated images pass the exporter's pixel/dimension/mode check.
- Android resource XML, manifest labels, iOS plist labels, and the launch
  storyboard parse successfully. Web manifest icon sizes match their files.
- A source scan finds no old visible app name in runtime code, native labels,
  web metadata, preview code, or the README.
- `flutter test --no-pub`: **246 passed**, including Android/iOS phone layouts.
- `flutter analyze --no-pub`: **no issues found**.
- `flutter build web --no-pub`: **release build succeeded**, including the new
  bundled icon and web identity. No deployment was performed.
- Phone dashboard, sign-in, and sign-up previews were visually checked at
  390×844 with the new name and supplied artwork.

Native launcher, launch-screen, and notification rendering still require a
device build. No Android/iOS device or emulator is available in this environment.
