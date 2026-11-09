# দ্বীন ও দুনিয়া — app identity

The public app name is **দ্বীন ও দুনিয়া**. Bengali text uses bundled Anek Bangla.
The existing emerald, cream and gold mark remains the app icon.

## Identity surfaces

- Flutter name: `lib/src/app_identity.dart`; headers, authentication, startup,
  privacy and settings use the shared identity.
- Android main and preview launcher labels, plus both iOS display-name fields.
- Web document title, Apple web-app title and PWA manifest names.
- Bundled privacy policy and generated public home/privacy/deletion pages.
- Play listing, release notes and generated feature graphic.
- New backup filenames use `deen-o-duniya`; the archive format is independent
  of the public name. Earlier archive versions remain readable after checksum,
  ownership and complete schema validation.

The application package, Firebase project, signing identity and saved account
records continue to support existing installations and accounts.

## Regeneration

```bash
python3 tool/generate_brand_assets.py --check
python3 tool/generate_release_assets.py
```

Name-change previews use the current source with fabricated data; they are
Flutter phone renders, not evidence from a Play-installed app:

- [Home](ui-screenshots/deen-o-duniya-mobile.png)
- [Sign in](ui-screenshots/deen-o-duniya-auth-mobile.png)
- [Sign up](ui-screenshots/deen-o-duniya-signup-mobile.png)

See `release/current-release-audit.md` for current build verification and limits.
