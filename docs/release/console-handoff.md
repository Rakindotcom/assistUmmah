# Play Console handoff

The owner chose to keep Console work manual. No Console settings, declarations,
tracks, terms or publishing actions have been submitted by Codex.

## Start with internal testing

1. Open the official [Play Console](https://play.google.com/console/) and select
   or create the app. Keep the package `com.rakindotcom.ummah_assist`.
2. Check whether version code **1** has already been used. If it has, rebuild
   with a new monotonically increasing code before uploading.
3. Configure Play App Signing. Back up the local upload key and credentials to
   your secure backup destination first. Do not upload those private files as
   store artwork or include them in this handoff packet.
4. Upload `app-release.aab` to an **internal** test release. Copy the release
   notes from `release-notes-bn.txt`. Inspect Play's bundle, SDK, permissions and
   16 KB warnings before distributing to testers.
5. From **App integrity → App signing**, download the **app-signing** certificate
   or copy its SHA-1 and SHA-256. Register both against the existing Android app
   in Firebase project `assistummah`. The upload certificate is already registered;
   it is a different certificate. This is necessary to verify Google sign-in in
   the Play-installed build. Do not change the Firebase billing plan.
6. Install through the test opt-in link and complete the native checks in
   `README.md`. Review the pre-launch report and fix actionable findings before
   promotion.

## Listing entries

| Field | Value/source |
| --- | --- |
| Name | রবের পথে |
| Default language | Bengali (Bangladesh) |
| Category | Lifestyle (suggested) |
| Price | Free |
| Ads | No ads in the current app |
| Contact email | teamframecipher@gmail.com |
| Website | https://assistummah.web.app/ |
| Privacy policy | https://assistummah.web.app/privacy |
| Account deletion | https://assistummah.web.app/delete-account |
| Short/full description | `store-listing.md` |
| Icon | `store-assets/play-icon-512.png` |
| Feature graphic | `store-assets/feature-graphic-1024x500.png` |

Use accurate phone captures, check their dimensions and preview every locale.
Read `native-captures/README.md` when captures are present; do not describe a
profile-mode integration capture as a Play-installed release capture.

## App access: do not leave this blank

The app requires authentication. A dedicated reviewer account with fabricated
starter records has been created, and client password sign-in, own-profile read
and sign-out have been verified. Its private credentials are stored locally at
`.local/play-reviewer-credentials.json` (mode 0600). Copy them into
**App content → App access/sign-in details**; they are excluded from this public
upload packet and Git. The provisioning tool did not request any verification
or password-reset email.
The account must remain usable throughout review. Keep its password out of Git,
screenshots and public release notes. No shared public credentials are supplied
by this packet, and no Google account or mailbox has been created. The app login
uses an alias of the support Gmail address, not a new Gmail account.

Suggested English instructions (fill the actual credentials in Console):

> Choose the email sign-in form. Enter the supplied email and password and select
> “লগইন”. Google sign-in is optional. No payment, membership, location,
> phone verification or invitation is required to review the core app. The bottom
> navigation opens Today, Tasks, Prayer, Growth and More. More contains Quran,
> Dhikr, Calendar, Contacts, and Settings. Device notifications and location are
> optional. Privacy and account deletion are in Settings; the external deletion
> page is https://assistummah.web.app/delete-account. Deletion permanently removes
> the reviewer account, so use a separate disposable account when testing it.

## Owner declarations

- Reconcile the form with `data-safety.md`, the live policy, SDK disclosures and
  the bundle permission inventory. This packet does not claim a submitted or
  approved Data safety form.
- Select the intended target audience and answer the IARC content questionnaire
  for the actual app. A religious app does not determine an age rating by itself.
- Complete developer identity/contact verification in the account. These details
  cannot be inferred from source code.
- Check whether the personal-account closed-test/production-access requirement
  applies to this developer account; if applicable, complete the required real
  tester period. A local emulator cannot satisfy it.

References: [app review preparation](https://support.google.com/googleplay/android-developer/answer/9859455),
[Data safety](https://support.google.com/googleplay/android-developer/answer/10787469),
[Google sign-in](https://firebase.google.com/docs/auth/android/google-signin).
