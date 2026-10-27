# রবের পথে

Mobile-first Flutter app inspired by the `muhasaba.org` accountability flow: tasks, prayer tracking, iman/life growth checklists, emergency contacts, settings, and report summaries.

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
check-in prompts. Calculated prayer-time alerts are configured separately on
the prayer tab.

## Prayer times

Prayer times are calculated on the device with `adhan_dart`. In the prayer tab,
users can choose their current location or enter coordinates and an IANA time
zone (for example `Asia/Dhaka`). They can select a calculation method, choose
the Hanafi or Shafi Asr calculation, and adjust each prayer by minutes to match
a local mosque. The next calculated prayer also appears on the Today dashboard.

Location settings are saved per user on the device with shared preferences; they
are not sent to Firestore. Coordinates obtained from the device are rounded to
two decimal places before saving. The location permission is requested only
when the user chooses to use the device location. Calculated times should be
checked against a trusted local timetable, especially in high latitude regions.

On Android and iOS, prayer-time alerts can be enabled per prayer. Users can
choose an alert at the prayer time or 5, 10, 15, or 30 minutes before, use
silent notifications, and suppress alerts during a quiet-hours window. Alert
preferences stay on the device and are scoped to the signed-in user. The app
schedules up to ten days of alerts and refreshes them when it opens or resumes;
it prompts users to reopen the app before the schedule expires. Android uses
exact alarms when permission is available and otherwise schedules approximate
alerts. Notification permission is requested when alerts are enabled.

## Past-day logs

Open **More → Calendar** to select a day and review its prayer and growth
records. The calendar allows corrections to any past date. A missing record is
shown as unlogged, rather than treated as a missed prayer. Editing a historical
growth checklist leaves the current profile type unchanged. Tasks are still
stored in a rolling current-day document, so historical task edits are not
available in the calendar.

## Prayer record states

Each prayer can be marked **unlogged**, **prayed**, **missed**, or **made up**.
Jamaat applies only to a prayed prayer. The dashboard, calendar, and reports
count these states separately; a prayer without a record is never inferred to
be missed. Earlier records with `prayed: true` remain prayed. Earlier
`prayed: false` values are treated as unlogged because previous app versions
could write them as untouched defaults. Existing qaza completions are read as
made up. New corrections save an explicit state per prayer.

The prayer tab opens a full qaza backlog covering every date with an explicitly
missed prayer. It is loaded from the signed-in user's prayer records, newest
first, and can be refreshed by pulling down or reopening the app. Completing a
qaza prayer changes that record to **made up** only if it is still marked
**missed**, so a correction made elsewhere is not overwritten. Legacy unlogged
prayers never enter this backlog. The offline preview has no persistent
cross-date backlog.

## Recurring tasks

When adding a task, choose **once**, **daily**, or **weekly**. A weekly task
repeats on the weekday it was created. The task page creates one occurrence
when an eligible day is opened; completing it does not complete future
occurrences. Unfinished occurrences from an opened day move into missed tasks
when the next day is opened. Deleting today's recurring task confirms and
cancels the series; earlier missed occurrences remain available. Days on which
the app was never opened are not backfilled as missed tasks.

## Task dates

The add-task dialog accepts a future date. Future one-off tasks and the first
occurrence of a future recurring series appear under **Scheduled tasks**.
Each task's calendar button can move it to another date. A task due on a day
when the app was closed appears on the next day it is opened, with its original
due date shown. Rescheduling one recurring occurrence leaves the series intact.

## Custom growth checklists

The growth page lets signed-in users add, rename, remove, reorder, and restore
the default items in
the iman checklist and in each life-profile checklist. Changes are saved with
the current day's answers and synchronized through the user's Firestore
preferences. Each saved day includes the item definitions used for that day;
the dashboard, calendar, and reports score that snapshot so later checklist
edits do not change older scores. Existing days without a snapshot keep the
original built-in checklist for their profile. Historical days can be corrected
without changing the current checklist template.

The built-in five-prayer growth item can be linked to prayer tracking. Linked
days count it as complete when all five prayers are marked prayed or made up;
missed and unlogged prayers keep it incomplete. The link can be switched per
day. Older growth records remain manual unless linked explicitly. Returning to
Growth or Calendar refreshes the displayed prayer-linked score.

## Progress trends

Open **Settings & Reports → Progress trends** for a 7- or 30-day view. The
screen shows prayer and growth logging coverage, explicitly marked missed and
completed prayers, the average growth score on logged days, and a recent-week
comparison through yesterday when each week has enough growth records. A day grid separates
missing records from recorded zero progress; tapping a day shows its details
and opens that date in the calendar. The view reads only the selected user's
prayer and growth records for the last 30 days.

## Quran reading goals

Open **More → Quran reading** or use the link on the Growth page. Set a daily
goal in minutes or pages, record both measures for each day, and optionally
note the last place read. The page shows progress for the selected day and a
seven-day history with separate missing and logged-zero days. Past days can be
corrected. Each log keeps that day's goal so a later goal change does not
rewrite earlier results; changing the current goal also updates today's saved
log. Signed-in data is stored under the user's Firestore path. Preview-mode
entries remain in memory only until the page or app is closed.

## Dhikr goals

Open **More → Dhikr goals** or the Growth page to set up to 20 personal daily
targets. Count one at a time, add a batch, or subtract an accidental tap. The
counter updates immediately; signed-in changes are queued and applied as
relative changes in Firestore transactions so concurrent device counts are
preserved. Failed changes are reverted and remain available for retry or
explicit dismissal. Resolve pending changes before switching dates.

The first count saves a snapshot of that day's goals. Editing the template
applies to dates without a saved count; existing days keep their targets and
names. A seven-day history distinguishes unlogged days from saved zero counts.
Preview counts remain in memory until the page or app is closed. Offline
transaction support is still part of the remaining offline-use work.

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

The Flutter and native app labels are `রবের পথে`.

The supplied app artwork is used for in-app branding, Android/iOS launcher and
launch-screen assets, notifications, and web icons. See
[branding and asset generation](docs/branding.md) for the source and regeneration
commands.

## Interface and local UI preview

The interface uses a shared theme, bundled Anek Bangla typography, Bengali
native date controls, and responsive phone, tablet, and desktop navigation.
The font's SIL Open Font License is included in
`assets/fonts/AnekBangla-OFL.txt`.

To review the actual screens without a Firebase connection or real account:

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8766 -t tool/ui_preview.dart --no-pub
```

Open `http://127.0.0.1:8766/?data=sample`. Preview edits remain in memory.
Use `?screen=auth` for authentication layout or append `&scale=1.6` to the
sample URL for enlarged text. Production builds continue to use `lib/main.dart`.

See [the UI review](docs/ui-review.md) for the screen audit, screenshots, test
coverage, and verification limits.


## Play Store release preparation

See [release preparation](docs/release/README.md) for the Spark-only account
deletion flow, published privacy/deletion URLs, support contact, private signing
setup, verification commands, store assets and remaining Play Console/device gates.
Support: **teamframecipher@gmail.com**.
