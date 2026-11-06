# Task notification delivery - development checkpoint

This describes the new productivity root. The normal application still starts
the legacy shell, and the offline Android preview explicitly disables every
notification operation. This source work does not establish native delivery or
publishing readiness.

## User contract

- A task stores up to 20 explicit UTC reminder instants. Each date/time runs
  once. Rescheduling the task does not implicitly move those reminder instants.
- For a recurring task, a selected reminder targets the occurrence on that
  date in the configured workspace time zone. Pauses, exceptions, nonmatching
  recurrence days and completed occurrences suppress that date's reminder.
  The planner never creates an occurrence just to show or schedule it.
- Completed, archived and trashed tasks and disabled workspaces do not schedule
  future reminders. Independent task reminders are de-duplicated and ordered
  by instant, workspace and identity.
- Settings has an explicit device opt-in, permission-denial feedback, scheduled
  and deferred counts, and refresh/retry controls in Bengali and English.
  Titles appear in the device notification UI; the consent control says so.
- Consent defaults to off and belongs to the account on this device. It is
  retained on sign-out and removed during successful account deletion and its
  startup cleanup retry. Backup import and cloud settings cannot enable it on
  another device.

## Planning and native transport

`task_reminder_plan.dart` retains only the nearest 200 candidates while counting
all eligible reminders. This bounds the native planning window without
retaining a complete alarm list for a large backlog.

Task IDs occupy 3000 through 3199. ID 3199 is reserved for renewal when there
are deferred candidates; a renewal uses a real notification slot. Android
scheduling is bounded to 200 slots. iOS capacity is the remaining part of its
64 pending slots after other features. The nearest task reminders are selected
first; a deferred count and renewal make the finite scheduling window visible.
See the installed plugin's [iOS pending notification limit](https://pub.dev/packages/flutter_local_notifications/versions/19.5.0#ios-pending-notifications-limit).

Daily/prayer updates vacate pending task slots **before** adding notifications,
then refill the task window. Reallocating afterward could let iOS discard an
unrelated older notification as soon as the queue exceeds its limit. Pending
and displayed notifications are treated separately: foreground refilling keeps
already delivered messages; initial account activation, opt-out and scope
release clear displayed task notifications too.

The shared native service serializes operations and guards them with account
scope, plan revision and sign-out generation. A new account invalidates earlier
requests before native awaits. A late old schedule/release cannot replace the
new account's plan. A failed partial scheduling batch cancels the alarms it
already attempted. Global account cancellation uses native `cancelAll`, so
timezone initialization cannot prevent pending/displayed notification cleanup.
Task opt-out and scope-release cleanup also skip timezone initialization, so
device setup failures cannot leave those task notifications active.

Android uses exact alarms only when already permitted. It falls back to
inexact scheduling, including an exact-permission revocation between checking
and writing the alarm. Routine refresh does not prompt for notification or
exact-alarm permission. Notification permission is requested by the explicit
Settings action. Device scheduling uses UTC instants, preserving the dates the
owner selected across device timezone changes.

## Foreground ownership

`TaskReminderController` observes task/occurrence records and the account's
frozen flag, coalesces edits, and replaces native plans. It refreshes on resume
and after a due reminder while the app is active. Deferred windows are checked
at most one minute apart in the foreground. Pausing stops the Dart refill timer
while previously registered native alarms remain scheduled.

Database errors invalidate old plans, retain task records and expose retry.
Device permission revocation cancels pending task alarms and displays blocked
permission feedback. The root's notification opt-out prevents creating this
controller or reading/writing its device settings in the offline preview.

## Verification and remaining work

The protocol test double models iOS eviction at the 65th request, both native
cancel argument formats, permissions and partial scheduling failures. Domain,
controller and phone-widget tests cover these contracts. They are not native
OS delivery tests.

Run the domain, transport, controller and phone checks with the ordinary
`flutter test --no-pub` gate. To render the Bengali and English controls with
the bundled Anek Bangla font at 320 px and 1.6x text:

```sh
flutter test --no-pub --dart-define=CAPTURE_TASK_NOTIFICATION_PREVIEWS=true test/productivity/task_reminder_settings_test.dart
```

The synthetic captures are written to `.local/previews/task-notifications-{bn,en}-phone.png`.

Remaining gates include:

- Normal app entry/route cutover and live migration/rules/privacy deployment.
- Android/iOS delivery, permission UX, Doze, reboot, process death and exact
  alarm settings on real supported devices. The user has no physical test
  phone or Mac/iPhone environment available.
- Task-specific notification tap routing and cross-platform deep links.
  The current notification tap opens the app normally.
- Relative/automatically repeated reminder rules, snooze actions and durable
  background refill. Current reminders are the explicit one-off dates described
  above; renewal and Settings expose the finite window.

A-14, A-15, M-07, M-14 and N-17 stay open at their full required scope.
