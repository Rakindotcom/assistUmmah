# Product quality assessment

**Date:** 28 October 2026 (Asia/Dhaka)

**Scope:** `রবের পথে` Android and Flutter source at this checkout. Scores are
engineering judgments, not ratings from users or a claim that Play has approved
the app. They describe the verified product, including the limits of the tests.

| Area | Current rating | Evidence and main gap |
| --- | ---: | --- |
| Functionality | 8/10 | Tasks, prayers, growth, calendar, qaza, Quran, dhikr, contacts, reports and deletion are implemented. Long offline sessions and interrupted writes remain a data-loss risk for some flows. |
| Mobile UI | 8.5/10 | Six captures from the signed-in Android app and 320–390 px widget layouts show consistent Anek Bangla, Bengali digits and phone navigation. Physical screens, keyboard and TalkBack have not been reviewed. |
| UX | 8/10 | Explicit loading, retry, empty and save feedback exist. Task drafts and failed growth edits remain visible with a retry; reports retry in place and distinguish missing growth records from a true zero. Contacts can be refreshed by pulling on a phone without losing the prior list if the request fails. Bengali user research and end-to-end onboarding observation remain outstanding. |
| Performance | 7.5/10 | Unopened tabs now load on demand and monthly reports use two parallel bounded range queries, replacing up to 62 sequential document reads. The single API 36 emulator sample took 6.46 s from sign-in tap to ready dashboard and 0.83 s for a seven-day live report. It recorded 9 raster frames over budget out of 50 navigation frames. A low-end ARM device and repeated measurements remain outstanding. |
| Reliability | 8/10 | Flutter unit/widget tests and Firebase rules emulator tests cover core flows. Reminder operations are serialized across sign-out and explicit preference changes. Tasks refresh on re-entry and resume while retaining the last loaded list on failure. Long offline operation, OS kill/restart and notification delivery still need device exercises. |
| Privacy and security | 8/10 | Owner-scoped rules, account deletion, disabled-by-default diagnostics, private release credentials and account-scoped navigation are in place. A Play-installed sign-in check, privacy declaration review and abuse testing remain outstanding. |
| Accessibility | 7.5/10 | Contrast, labels, target size and large-text widget checks exist. Actual TalkBack/VoiceOver traversal and Bengali comprehension need testing with people. |
| Release readiness | 7/10 | The current signed Android bundle passes signature and 16 KB alignment checks. Fresh startup/login verification of this exact bundle is pending after a timeout on the dedicated emulator. Physical ARM64 devices, a Play-installed build, Play Console declarations and any closed-test requirement remain outstanding. |

**Overall: 8/10, provisionally.** This is a weighted engineering assessment of
the shipping experience. Raising the score requires proof from the remaining
device, user and release checks. Local changes in this pass do not
change the Play Store status by themselves.

## Changes in this quality pass

- Each tab initializes the first time it opens; visited tabs keep their state.
  Daily and prayer reminders refresh from a session service at startup/resume,
  independently of whether Settings or Prayer was opened. Notification work
  is serialized so sign-out cancellation finishes after in-flight work and
  discards queued work from the old session.
- Reports reuse the 7/30-day range query path. Month-end reads now require two
  parallel date-bounded queries. The UI retries failed reports in place and
  shows “হিসাব নেই” for absent growth records rather than a misleading ০%.
- The complete Navigator tree is keyed to the signed-in UID. Account changes
  discard detail routes and dialogs containing the previous account's data.
- Task creation waits for the repository write before closing the dialog. A
  failed save retains the draft and repeat choice, with an inline retry. The
  task ID stays stable across retries so a lost response after a successful
  commit does not duplicate the task. A 360 px test caught and fixed a
  dropdown overflow during the busy state.
- The Tasks tab now refreshes synced data when reopened or resumed. It keeps
  the last loaded list visible through refresh failures and ignores older
  responses that arrive after a newer refresh.
- Contacts now refresh on tab return, app resume and a phone pull gesture.
  They retain the last loaded list through failures and protect newer results
  from older requests. Preview contacts survive a refresh.
- Growth edits now retain their optimistic state and visible save status when a
  tab refresh arrives before the write finishes or after it fails. The failed
  state offers an inline retry, preserving the latest checklist values instead
  of silently replacing them with older server data.
- A profile-mode Android integration audit measures sign-in, first tab loads,
  a live seven-day report and navigation frames. The prior-build audit passes with
  dedicated synthetic reviewer records. The result is intended as a single-run
  baseline; it cannot establish device-wide percentiles.

The final Flutter analyzer found no issues and all 288 unit/widget tests passed
on 28 October 2026. The native audit uses an API 36 x86_64 emulator with 16 KB
pages; its [timing and functional record](release/native-verification.json)
includes a profile build from this quality pass. The task composer change was
made after that profile APK was built, so its mobile coverage currently comes
from widget tests rather than that APK. The signed release build includes the
task composer. The [signed release smoke](release/signed-release-smoke.json)
caught a release-only Firebase registrar startup error and then passed on the
prior bundle. The current bundle needs a new successful runtime check before
that evidence can be applied to this build.

## Evidence for the next rating

1. Run the full Flutter suite and analyzer after each source change; inspect
   the test scope rather than treating a pass count as a usability result.
2. Run the current profile integration audit and a signed release smoke on the
   16 KB emulator; inspect timing JSON, errors and mobile screenshots.
3. Test a Play-installed build on physical ARM64 phones, including system
   keyboard/autofill, Google sign-in, notifications, Doze, reboot, timezone
   changes, accessibility services, background/foreground and poor network.
4. Exercise offline edits and process death for every daily data type. Keep
   user-visible unsaved work durable or give a clear retry path before rating
   reliability at the top of the scale.
5. Observe Bengali-speaking users completing first-session, daily check-in,
   correction and account deletion tasks; fix the friction they encounter.
6. Complete the Play Console work manually, as requested by the owner, and
   review the live policy, Data safety answers, app access, signing identities,
   pre-launch report and any closed-test requirement before publication.

The build and release evidence is in [the release guide](release/README.md),
[native verification](release/native-verification.json) and
[the existing UI review](ui-review.md).
