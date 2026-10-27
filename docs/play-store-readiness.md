# Play Store readiness audit — রবের পথে

> **Implementation update — 27 October 2026:** The original audit below is a
> historical baseline. Account deletion, privacy pages, sign-out recovery,
> signing setup, OAuth configuration, store graphics and release checks have
> since been implemented. See [current release preparation](release/README.md)
> for deployment evidence, completed verification and remaining device/Console gates.


**Audit date:** 26 October 2026 (Asia/Dhaka)
**Version:** `1.0.0+1`
**Android application ID:** `com.rakindotcom.ummah_assist`
**Decision:** **Not ready for production submission.**

The Flutter test suite is green, but required account/privacy flows are missing,
release authentication configuration needs attention, and no signed Android App
Bundle has been produced or tested. A successful web build or a polished phone
preview cannot establish Android release readiness.

## Scope and evidence

This audit covers the current working tree, Android and Flutter configuration,
authentication, Firestore rules, data storage, permissions, branding assets,
automated tests, and current official publishing guidance. Existing uncommitted
changes were preserved. No application fixes or production mutations were made.

There is no Android SDK, Android emulator, or physical Android device available
in this environment. Play Console and the production Firebase Console were not
accessible. Their settings, deployed rules, reviewer access, and testing status
are **unverified**, rather than presumed incorrect.

| Check | Result | What the evidence establishes |
| --- | --- | --- |
| `flutter test --no-pub` | **Pass: 246 tests** | Current unit/widget behavior, including phone layouts and editing flows. |
| `flutter analyze --no-pub` | **Pass: no issues** | Static Dart analysis, not native compilation. |
| `git diff --check` | **Pass** | No detected whitespace errors. |
| `python3 tool/generate_brand_assets.py --check` | **Pass: 45 assets** | Exported images match the supplied branding source. |
| Local Firestore authorization checks | **Pass** | Owner access and cross-user/anonymous denial across nine user-data paths; activity attribution and unmatched-path denial. |
| Android target configuration | **Pass at source level** | Installed Flutter SDK resolves compile/target API 36, minimum API 24. Final artifact remains unverified. |
| `flutter build appbundle --release --no-pub` | **Blocked** | Exits with `No Android SDK found`. No `.aab` available. |
| Release signing | **Missing locally** | `android/key.properties` absent; Gradle only enables signing when all four required properties exist. |
| Native installation, notifications, Google login, performance | **Unverified** | No release artifact or Android runtime available. |
| Play Console declarations and production access | **Unverified** | Requires the developer account and final release artifact. |

Toolchain inspected: Flutter 3.44.2, Dart 3.12.2, Java 17 configuration,
AGP 9.0.1, Gradle 9.1.0, Flutter NDK default 28.2.13676358.
API 36 matches the phone-app submission requirement effective 31 August 2026.
[Android target API requirements](https://developer.android.com/google/play/requirements/target-sdk)

The local rules audit used synthetic users and data in the isolated
`demo-ummah` Firestore emulator. It also checked bounded date queries for daily
collections; this is query behavior, **not schema or date validation in rules**.
The emulator was stopped after testing. Production rules were not queried.

## Required changes and release blockers

### 1. Account deletion is missing

**Confirmed source gap; submission blocker.**

[Email sign-up](../lib/src/auth/auth_screen.dart) creates Firebase accounts.
[Settings](../lib/src/pages/settings_page.dart) offers profile editing and sign-out
but no deletion request. No account-deletion implementation or external deletion
resource was found in the repository or supplied for this audit.

For apps supporting in-app account creation, Play requires an in-app deletion
path and a web resource for requesting account and associated-data deletion.
Signing out or disabling an account does not fulfill this requirement.
[Account deletion requirements](https://support.google.com/googleplay/android-developer/answer/13327111)

**Acceptance:** a discoverable Bengali settings action, identity verification
where needed, clear consequences and retention explanation, a working public web
request route, and verified removal of Auth and associated data. A completed
request must survive retries and avoid orphaning data. Cover all paths listed
below, including nested daily records and local preferences/notifications.

### 2. Privacy policy and disclosures are incomplete

**Confirmed in-app gap; Console status unverified.**

No in-app privacy link/text or supplied public policy URL was found. Publish a
policy naming the app/developer and contact, describing data handling, service
providers, security, retention, and deletion. Make it accessible in-app and in
Play Console. Google's policy requires a public, accessible policy URL and
does not accept a PDF policy.
[User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311)

Complete the Data safety form from the actual release's app and SDK behavior.
This app stores account details and religious activity in Firestore; declaring
that it collects no data would be inaccurate. See the inventory below.
[Data safety guidance](https://support.google.com/googleplay/android-developer/answer/10787469)

**Acceptance:** working public URLs, matching in-app disclosures, explicit
retention/deletion decisions, and a reviewed Console declaration consistent with
the final artifact. An external policy might exist elsewhere; this audit did not
receive or verify one.

### 3. No signed Android release artifact

**Confirmed build/signing gap in this environment.**

[Gradle configuration](../android/app/build.gradle.kts) reads a private
`android/key.properties` file and conditionally applies release signing. That
file is absent. The AAB attempt failed before native compilation because the
Android SDK is absent. This does not establish a source compilation defect;
Android compilation is currently unproven.

**Acceptance:** provision the SDK and required build tools, configure the upload
key securely, produce a signed release AAB, validate it, and upload it to an
internal test track. Inspect the resulting package ID, version, target/minimum
SDK, native architectures, signing and merged permissions. Enroll/verify Play
App Signing and securely retain the upload-key recovery material. Confirm
version code `1` is unused for this application in Console.

### 4. Google sign-in configuration needs correction and release verification

**Confirmed configuration gap; native failure not directly observed.**

The local Android Firebase configuration matches the app package, but its
matching client has **zero OAuth client entries**. Native
[Google sign-in](../lib/src/auth/auth_screen.dart) calls `GoogleSignIn().signIn()`
without an explicit server client ID. The Android plugin can derive this from
generated `default_web_client_id` resources; the inspected config provides no
OAuth entries to generate it.

Verify that Google authentication is enabled, register the appropriate certificate
fingerprints, and download the refreshed Firebase Android configuration containing
OAuth details. Include the **Play App Signing app-signing certificate**, because
Play-installed builds use that certificate, independently of the upload key.
[Firebase Android Google authentication setup](https://firebase.google.com/docs/auth/android/google-signin)

**Acceptance:** successful email and Google authentication on the Play-installed
release, including cancellation, account switching, logout, reset-password and
session restoration. The current native login path cannot be marked passed from
web or widget tests.

### 5. Release-blocking sign-out failure path

**Confirmed source defect; engineering release gate.**

In [settings_page.dart](../lib/src/pages/settings_page.dart), around lines 399–406,
`cancelAll()` is awaited before Firebase sign-out. Its catch block displays an
error and returns, so a notification plugin failure leaves the user signed in.

**Acceptance:** notification cleanup errors cannot prevent session termination;
report/retry cleanup appropriately and test the failure path. Verify that another
account does not inherit the previous user's reminders or visible data.

### 6. Store artwork is not ready in the repository

**Confirmed asset gaps; existing Console uploads unverified.**

- The current runtime icon is 512×512 **RGB**, 197,013 bytes. Create a separate
  32-bit PNG store export; keep platform-specific runtime formats appropriate.
- No 1024×500 feature graphic exists under `assets`, `docs`, or `web`.
- The three rebranded phone previews are 390×844. Their long/short ratio exceeds
  2:1, so they are unsuitable for direct screenshot upload under the documented
  dimensional limit. Capture at least two accurate release screenshots, for
  example 1080×1920, with the final branding and realistic data.

Play specifies a 512×512 32-bit PNG icon, a 1024×500 feature graphic, and screenshot
format/dimension constraints.
[Store preview asset requirements](https://support.google.com/googleplay/android-developer/answer/9866151)

**Acceptance:** final exports and a truthful Bengali listing with short/full
descriptions, category and support contact; verify the uploaded listing in Console.

## Data inventory and deletion coverage

This is an implementation inventory for preparing disclosures, not a completed
Console form. Collection, sharing, required/optional use and purposes must be
reconciled with the final SDK configuration. A service-provider transfer is not
automatically classified as sharing under every Data safety definition.

| Data | Current destination | Disclosure / deletion consideration |
| --- | --- | --- |
| Account email, display name, UID; login timestamps | Firebase Auth; `users/{uid}` | Personal information, user identifiers and account management. Delete both identity and profile data. |
| Tasks, recurrence and scheduling | `userTasks/{uid}` | User-generated content; clear associated task data. |
| Prayer records and jamaat state | `userPrayers/{uid}/dailyPrayers/{date}` | Religious-practice information; recursively delete daily records. |
| Growth checklists and profile choices | `userGrowth/{uid}/dailyGrowth/{date}` | May include religious practices and other user-generated content. |
| Quran reading and goals | `userQuran/{uid}/dailyReading/{date}` | Religious-practice information and progress. |
| Dhikr counts and goals | `userDhikr/{uid}/dailyDhikr/{date}` | Religious-practice information and progress. |
| Templates and user preferences | `userPreferences/{uid}` | Preferences linked to the account. |
| Manually entered contact names/groups | `userContacts/{uid}` | Contacts/other people's information; no phonebook import or permission found. |
| Profile and reminder preferences | `userSettings/{uid}` | Account-linked settings. |
| Prayer location and alert settings | Per-user local preferences | Inspect and remove `prayer_time_config_v1_<uid>` and `prayer_alert_settings_v1_<uid>`; cancel scheduled notifications. |

Play's taxonomy includes **political or religious beliefs**, contacts, and other
user-generated content. Religious tracking deserves an explicit classification
review rather than treating all records as generic app activity. Local-only
processing is distinguished from off-device collection.
[Data types and collection definitions](https://support.google.com/googleplay/android-developer/answer/10787469)

The application requests device location only through the user's location action,
rounds acquired coordinates to two decimal places and stores prayer configuration
locally. No application code sending these prayer coordinates to Firestore was
found. Still disclose access and purpose in the policy and examine SDK behavior
before choosing the location answer in Console.

Firebase SDK behavior also matters: Auth documents automatic IP address and
user-agent processing alongside account information. The absence of an Analytics
dependency does not imply zero SDK collection.
[Firebase Android SDK disclosure guidance](https://firebase.google.com/docs/android/play-data-disclosure)

Rules additionally permit owner-attributed creates in `userActivities`; no current
app writes were found. If legacy records exist, include them in deletion handling.
Clients cannot read or delete these records under the current rules, so cleanup
needs a trusted service. Removing a parent Firestore document alone must not
leave its daily subcollections behind.

## Security and permissions assessment

### Findings supported by source and local checks

- [Firestore rules](../firestore.rules) restrict the nine user-data paths to the
  authenticated owner; unmatched paths are denied. Local tests passed. Confirm
  these exact rules are deployed before release.
- Rules do not validate field schemas or constrain user-supplied document values.
  Add suitable validation and abuse/cost controls as production hardening.
- No App Check integration or crash reporting integration was found in app source.
  Console-side enforcement and operational monitoring remain unverified. These
  omissions are not independently automatic Play rejection reasons.
- Firebase client configuration is not a server credential. Its presence alone
  is not a secret leak; authorization must be enforced by rules and backend design.
- The source manifest requests internet, foreground coarse/fine location, boot
  completion and `SCHEDULE_EXACT_ALARM`. Notification permission comes from the
  local-notifications plugin manifest. Audit the final merged manifest as well.
- No background-location, contacts, SMS, advertising-ID or
  `USE_EXACT_ALARM` permission was found in the app's main source manifest.
- The reminder service checks exact-alarm access and selects an inexact fallback
  when unavailable. `SCHEDULE_EXACT_ALARM` must not be confused with the separately
  restricted `USE_EXACT_ALARM` permission.
  [Android alarm guidance](https://developer.android.com/develop/background-work/services/alarms)
- No advertising or billing implementation was found. Confirm this against the
  final dependency/merged-manifest inventory and answer the Console ads form
  accordingly. Free functionality does not require adding billing.

### Additional engineering risks to resolve

`main.dart` awaits Firebase initialization before showing the app without an
application-level recovery screen. Exercise configuration/service failures;
do not infer that normal offline startup always fails. Profile-document creation
also swallows errors in the auth gate, which reduces visibility of setup failures.

Some writes use Firestore transactions, so offline success is not established.
Check clear errors, retained drafts and recovery rather than advertising complete
offline support. Introduce release crash/error monitoring, reproducible CI builds
and an incident/rollback procedure before a broad launch.

## Native release verification still required

The existing phone coverage includes 100 Android/iOS widget layout cases across
320×720 with enlarged text and 390×844, plus 32 editing/recovery flows using
simulated keyboard space. Native notification and timezone channels are stubbed.
These are useful regressions; real platform behavior remains an open gate.

| Area | Evidence required from the signed Android release |
| --- | --- |
| Installation and startup | Fresh install, update, cold/warm start, killed process, offline start; no crash or blank screen. |
| Authentication | Email/Google login, reset, cancellation, session restore, account switching and logout; reviewer credentials work. |
| Data isolation | Two accounts and two devices; no prior-user data flashes, cross-account local preferences or stale reminders. |
| Deletion | Both request routes complete; nested records, identity and local data removed; retry/interruption handled. |
| Permissions | Deny/revoke location, notifications and exact alarms; service disabled and approximate location; useful manual/fallback behavior. |
| Reminders | Real delivery after backgrounding, OS process death, reboot and Doze; timezone/date changes; granted and denied exact access. |
| Prayer alerts | Correct times for chosen location/calculation settings; ten-day scheduling horizon and renewal behavior are understood and tested. |
| Android UI | System back/gestures, Android 16 edge-to-edge, actual keyboard, small display, large text, Bengali glyphs/digits, TalkBack, launch/themed/notification icons. |
| Data recovery | Slow/offline network, denied write, retry, reconnect, concurrent changes and day rollover without loss/duplicate progress. |
| Performance | Measure release startup and scrolling, repeated navigation, memory use, crashes/ANRs on a modest Android device. |
| Binary compatibility | Verify ARM64 and other intended ABIs, native ELF/ZIP alignment, and run on a 16 KB environment. |

Flutter ships native libraries. Modern AGP/NDK configuration alone does not prove
that the generated app and every native dependency support 16 KB pages. Check
the actual artifact and runtime environment.
[Android 16 KB compatibility guidance](https://developer.android.com/guide/practices/page-sizes)

## Play Console gates that could not be checked

- Developer identity/contact verification and applicable account requirements.
- Package ownership, unused version code, Play App Signing, upload validation,
  App Bundle Explorer compatibility and SDK warnings.
- Public privacy/deletion URLs and accurate Data safety answers.
- App access: provide controlled working reviewer credentials and instructions
  for the login-protected functionality; do not depend on a reviewer's own account.
- Content rating, target audience, ads declaration, countries and any applicable
  App content declarations. Confirm rights to submitted content and artwork.
- Final store listing, phone screenshots, feature graphic and support contact.
- Internal/closed-track installation and pre-launch report; investigate failures
  and document any justified findings before production submission.

App-access and content information must be supplied in Console.
[Prepare an app for review](https://support.google.com/googleplay/android-developer/answer/9859455)

**Conditional testing requirement:** personal developer accounts created after
13 November 2023 need at least 12 testers opted into a closed test continuously
for 14 days, followed by an application for production access. The account type,
creation date and completion status were unavailable, so this is a conditional
gate rather than an assumed delay for this app.
[Personal-account testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)

## Recommended completion order

1. Implement complete account deletion, including its external request resource.
2. Publish the privacy policy and reconcile the data inventory with Console forms.
3. Fix the sign-out failure path and refresh/verify Android Google auth setup.
4. Provision Android build tools and signing; produce and validate the release AAB.
5. Install through Play internal testing and complete the native matrix above.
6. Create compliant store exports and complete listing/reviewer declarations.
7. Complete applicable closed testing and resolve pre-launch/artifact warnings.
8. Re-audit the final release artifact and Console state before submitting.

**Release approval requires evidence for every required gate.** Current automated
test passes are a good foundation, but do not override the confirmed missing
privacy/deletion flows or the absent Android release evidence.
