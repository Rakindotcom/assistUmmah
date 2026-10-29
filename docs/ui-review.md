# UI review

## Current benchmark correction — 29 October 2026

The earlier 9/10 assessment below over-weighted layout and engineering checks.
It does not establish competitive product quality. The supplied competitor
screens show clearer prayer-first utility and broader Islamic content. The old
numeric score is withdrawn; no replacement usability score is claimed without
user observation and physical-device review.

The current home adds a local prayer countdown and five-prayer strip, nine
working shortcuts, prayer status, a daily Quranic dua and compact personal
progress. New offline screens include eight searchable duas with sources and
copy, a location picker and today/tomorrow fasting times. Quran remains a reading
tracker; a complete reader, hadith library and Qibla compass are not implemented.

Current production-widget renders at 390×844 logical pixels with fabricated
preview data:

- [Home and shortcuts](ui-screenshots/home-phone.png)
- [Prayer status and daily dua](ui-screenshots/home-daily-phone.png)
- [Offline dua library](ui-screenshots/dua-library-phone.png)
- [Fasting times](ui-screenshots/fasting-phone.png)

These are widget renders, not physical-device or Play Store screenshots.
Reproduce with `flutter test --no-pub tool/home_preview_test.dart`. The rendered
home passed labeled-target and Android 48px target guidelines. Configured-home,
fasting and dua-detail flows pass at 320px with 1.6× text. Countdown tests cover
prayer boundaries, sunrise, midnight, inactive screens and unchanged account-read
counts while the timer advances. Formal religious review and physical-device
validation remain outstanding. See [dua content sources](dua-content-review.md).

Verification for the current home: full Flutter suite **322 passed**, analyzer
**no issues**, and release-tool Python suite **3 passed** on 29 October 2026.
Native startup of this exact signed build remains unverified.

## Historical interface assessment

This is a design and engineering judgment of the implemented interface, not a
user-research score or certification. The starting desktop view was constrained
to a fake phone with a simulated status bar. Inconsistent headings, controls,
spacing, and text sizes weakened the hierarchy.

The redesign follows the clarity, consistency, and accessibility priorities in
[Microsoft Fluent's design principles](https://fluent2.microsoft.design/design-principles)
and [layout guidance](https://fluent2.microsoft.design/layout), adapted to a
Bengali daily planner using Flutter Material components.

| Criterion | Rating | Evidence |
| --- | --- | --- |
| Hierarchy and navigation | 9/10 | Left-aligned headings, focused dashboard action, labeled persistent navigation, contextual back actions. |
| Typography and consistency | 9/10 | Bundled Bengali font, shared type scale, neutral surfaces, consistent spacing and controls. |
| Responsive layout | 9/10 | Phone bottom navigation, compact tablet rail, desktop drawer, adaptive cards and calendar. |
| Feedback and recovery | 9/10 | Explicit loading, empty, error, validation, busy, and retry states; failed text saves retain drafts. |
| Accessibility | 9/10 | Contrast checks, dashboard labels and 48px targets, keyboard focus checks, localized date picker, enlarged-text coverage. |

The remaining gap to 10/10 is evidence from Bengali-speaking users and a
physical-device assistive-technology study. Browser and widget checks do not
establish usability on every supported device.

## Screen audit

All 14 groups received visual review. Browser captures use synthetic data at
1280×900 on desktop and 390×844 on phone. The tablet shell was checked at
900×900. No real accounts or Firestore data were used for this UI review.

| Screen / flow | Reviewed evidence |
| --- | --- |
| Navigation and shell | [Desktop](ui-screenshots/dashboard-desktop.jpg), [tablet](ui-screenshots/dashboard-tablet.jpg), [phone](ui-screenshots/dashboard-mobile.jpg). Real responsive shell replaces the fake phone frame. |
| Sign in, sign up, reset | [Validation](ui-screenshots/auth-validation-mobile.jpg), [signup with keyboard inset](ui-screenshots/signup-keyboard-large.png), [reset feedback](ui-screenshots/password-reset-feedback-large.png). Keyboard order checked. |
| Dashboard | [Current home](ui-screenshots/home-phone.png), [prayer status and daily dua](ui-screenshots/home-daily-phone.png). Earlier browser images below are historical. |
| Tasks and scheduling | [Desktop](ui-screenshots/tasks-desktop.jpg), [phone](ui-screenshots/tasks-mobile.jpg), [add dialog](ui-screenshots/task-dialog-keyboard-large.png), [date picker](ui-screenshots/date-picker-large.png). Add, recurrence, scheduling, rescheduling regressions covered. |
| Prayers, location, alerts | [Desktop](ui-screenshots/prayers-desktop.jpg), [phone](ui-screenshots/prayers-mobile.jpg), [location](ui-screenshots/prayer-location-keyboard-large.png), [native alert controls](ui-screenshots/prayer-alerts-large.png). |
| Qaza backlog | [Desktop](ui-screenshots/qaza-desktop.jpg), [phone](ui-screenshots/qaza-mobile.jpg). Completion/retry covered by qaza tests; shell push/pop covered separately. |
| Growth and checklist editor | [Desktop](ui-screenshots/growth-desktop.jpg), [phone](ui-screenshots/growth-mobile.jpg), [item dialog](ui-screenshots/checklist-item-keyboard-large.png). Profile choices and historical scores covered by tests. |
| More navigation | [Desktop](ui-screenshots/more-desktop.jpg), [phone](ui-screenshots/more-mobile.jpg). All destinations have labels and descriptions. |
| Calendar and historical editors | [Desktop](ui-screenshots/calendar-desktop.jpg), [phone](ui-screenshots/calendar-mobile.jpg), [localized picker](ui-screenshots/date-picker-large.png). Historical edits covered by calendar tests. |
| Contacts and add dialog | [Desktop](ui-screenshots/contacts-desktop.jpg), [phone](ui-screenshots/contacts-mobile.jpg). Failed save retains draft; retry inserts once. |
| Settings, profile, reports | [Desktop](ui-screenshots/settings-desktop.jpg), [phone](ui-screenshots/settings-mobile.jpg), [report](ui-screenshots/report-large.png). Profile, load retry, and scrolling checked. |
| Trends and details | [Desktop](ui-screenshots/trends-desktop.jpg), [phone](ui-screenshots/trends-mobile.jpg), [day sheet](ui-screenshots/trend-day-large.png). Grid adapts to enlarged text; missing records remain distinct from zero progress. |
| Quran and reading goals | [Desktop](ui-screenshots/quran-desktop.jpg), [phone](ui-screenshots/quran-mobile.jpg), [goal editor](ui-screenshots/quran-goal-keyboard-large.png). Goal and reading edits covered. |
| Dhikr and goals | [Tasbih phone](ui-screenshots/tasbih-phone.png), [phrase picker](ui-screenshots/tasbih-picker-phone.png). Arabic, Bengali reading and meaning, a large tap ring, per-day target changes, confirmed reset and immediate custom phrases. Rapid taps, remote increments, failure/retry and account/day boundaries are covered. |

The tasbih captures were rendered on 29 October 2026 with production Flutter
widgets at 390×844 logical pixels and fabricated preview data. They are widget
renders, not physical-device captures. Reproduce with
`flutter test tool/tasbih_preview_test.dart`; images are written to `.local/previews`.
The picker and target dialog also have 320 px / 1.6× text / keyboard-inset tests.

## Defects fixed during review

- Enlarged-text overflow in prayer rows and the trends grid.
- Clipped date-picker year; a localized abbreviated month keeps the full year visible.
- Dialog controllers disposed during closing animations in Contacts and Profile.
- Initial-load errors presented as empty editable data in Tasks, Prayer, Contacts,
  and Settings; each now offers an explicit retry state.
- Conflicting floating-action-button Hero animations from retained inactive tabs;
  only the visible tab participates in route transitions.
- Weak heading, progress-card, and prayer-control semantics.

## Verification

- `test/ui_layout_test.dart`: 125 layout cases. There are 100 Android/iOS phone
  cases across 320×720 at 1.6× text and 390×844 at default text, including empty
  and populated screens with 44px top and 34px bottom safe-area insets. The
  remaining 25 cases cover desktop at 1280×900.
- `test/ui_flow_layout_test.dart`: 16 editing and recovery flows on each of
  Android and iOS (32 cases), with the bundled font, Bengali localization,
  enlarged text, and simulated keyboard insets.
- `test/ui_accessibility_test.dart`: tested text contrast pairs ≥4.5:1, dashboard
  labels and touch targets, authentication focus order, contact-save recovery.
- The route-transition regression reproduced the duplicate-Hero assertion before
  the fix and checks both opening and returning from the backlog.
- Widget captures with a keyboard inset simulate available space; they do not
  render an operating-system keyboard. Native-only alert controls are captured
  in widget tests.

UI redesign baseline gates passed on 2026-10-26, before the Anek Bangla update:

- `flutter test --no-pub`: **154 passed**, including the route-transition regression.
- `flutter analyze --no-pub`: **no issues found**.
- `flutter build web --no-pub`: **release build succeeded** for `lib/main.dart`;
  the WebAssembly dry run also succeeded.
- `git diff --check`: **clean**.

### Reproduce

```bash
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8766 -t tool/ui_preview.dart --no-pub
```

Open `http://127.0.0.1:8766/?data=sample` for synthetic data. Omit the query for
empty states, use `?screen=auth` for authentication layout, or append `&scale=1.6`
to the sample URL for enlarged text. The preview never initializes Firebase;
its writes remain in memory. Auth checks use local validation without submitting
credentials.

```bash
flutter test --no-pub
flutter test --no-pub --dart-define=CAPTURE_UI=true test/ui_flow_layout_test.dart
flutter analyze --no-pub
flutter build web --no-pub
git diff --check
```

The release build uses `lib/main.dart`. No deployment was performed. Native
notification delivery and physical-device screen-reader behavior were not
established by this UI review.

## Font

Anek Bangla is bundled from the
[official Google Fonts source](https://github.com/google/fonts/tree/main/ofl/anekbangla).
Its [SIL Open Font License](../assets/fonts/AnekBangla-OFL.txt) is included
as an application asset. Rendering needs no runtime font download.

The 2026-10-26 typography update applies Anek Bangla to both Bengali and English.
All 70 existing UI layout, editing-flow, and accessibility checks passed with
the new font, including 320px layouts at 1.6× text. Static analysis found no
issues. The PNG editing-flow captures were regenerated with Anek Bangla; the
earlier browser screenshot gallery records the preceding UI review.

[Current dashboard with Anek Bangla](ui-screenshots/dashboard-bangla-numbers.jpg).

## Bengali number formatting

App-generated counts, scores, date labels, and prayer times use shared Bengali
digit formatting. This fixes the mixed-script prayer ratio (`2/৫` → `২/৫`) and
the same issue in summaries, histories, reports, and trends. Storage keys and
calculations remain numeric or ISO-formatted; user-entered text and numeric
editing fields retain their original contents.

After this update, all 154 tests passed and static analysis found no issues.
The dashboard accessibility test explicitly checks Bengali prayer/task ratios,
supporting counts, and percentages. The earlier screenshot gallery predates
this digit-localization update; the current dashboard is captured in
[this updated preview](ui-screenshots/dashboard-bangla-numbers.jpg).

## Mobile-first follow-up

The primary product target is the phone app. Review phone flows before tablet
and desktop layouts when changing the interface.

The 2026-10-26 follow-up expanded widget coverage to Android/iOS platform
behavior and safe areas. The 390×844 browser preview was reviewed again with
Anek Bangla and Bengali numbers across Today, Tasks, Prayer, Growth, More,
Quran, and Dhikr. See the refreshed phone captures in the audit table and
[the phone progress cards](ui-screenshots/dashboard-progress-mobile.jpg).

Two mobile issues were addressed:

- Android system Back now returns from an in-shell detail screen to its caller,
  then from a main tab to Today. The regression test reproduced the old failure
  before the fix and passes after it.
- Native prayer-alert configuration now follows the daily prayer log and qaza
  link, keeping daily tracking ahead of settings.

Native widget-flow captures include
[Android alert controls](ui-screenshots/prayer-alerts-large-android.png),
[iOS signup with a keyboard inset](ui-screenshots/signup-keyboard-large-iOS.png),
and [iOS location editing](ui-screenshots/prayer-location-keyboard-large-iOS.png).
Notification and timezone channels are stubbed in widget tests; queued work is
drained and service state is isolated between cases.

Final follow-up gates: `flutter test --no-pub` passed **246 tests**,
`flutter analyze --no-pub` reported **no issues**, and `git diff --check` was
clean. This supersedes the earlier 154-test count; no native release build was
claimed for this follow-up.

**Native-device validation remains pending.** `flutter devices` found Linux and
Chrome only, and `flutter emulators` found no emulator sources. These checks do
not establish Android/iOS installation, real keyboard behavior, notification
delivery, permission prompts, or physical-device screen-reader behavior.
