# Data safety preparation

Use this inventory when completing Play Console. It is a draft to reconcile with
SDK disclosures and the final artifact, not a submitted form.

| Data type to assess | Current use | Required/optional |
| --- | --- | --- |
| Name, email, user IDs | Firebase Auth, account/profile and sync | Email/UID for accounts; display name provided by user/provider |
| Political or religious beliefs | Prayer, growth, Quran and dhikr records | User-entered records; religious practices can reveal beliefs |
| Contacts | Manually entered contact names/groups | Optional; no device phonebook import |
| Other user-generated content | Tasks, checklists, goals and preferences | Optional content |
| Crash logs and diagnostics | Firebase Crashlytics technical reports | Optional, explicitly enabled in settings; off by default |
| Device or other IDs | SDK installation/report identifiers | Reconcile Auth/Crashlytics behavior; do not assume no SDK identifiers |
| Location | Prayer coordinates processed/stored locally by app code | Optional access; local-only access is distinct from off-device collection |

## Purpose and handling

- Account management and app functionality for Auth/Firestore data.
- Crash diagnosis for optional technical reporting. App error messages are reduced
  to error type and call stack; no custom names, email, UID or daily records are
  attached. Native SDK metadata still needs its own disclosure.
- Firebase Auth also processes IP addresses and user-agent information for
  security/abuse protection. Review the SDK's current definitions and purposes.
- No ads, sale of personal data, Analytics integration or tracking consent flow
  was added. Firebase service-provider processing is not automatically classified
  as sharing under every Data safety definition.
- Data uses encrypted Firebase connections in transit. Confirm final SDK behavior.
- Deletion removes all nine documented user-data paths, nested daily records and
  legacy owner-attributed activities before deleting the Firebase Auth identity.
- A minimal empty UID-keyed security marker remains to stop old sessions or queued
  writes from recreating deleted data. It contains no profile or activity fields;
  its retention has no fixed expiry and is explicitly disclosed in the policy.
- Interrupted deletion is not called successful. The user reauthenticates and
  resumes in the app or web page. This works on Spark without a background worker.
- Local location/alert preferences are removed best effort. Remaining Firestore
  disk cache is marked for clearing before listeners start on the next launch.
  Other devices may retain offline cache until app data is cleared/uninstalled.
- Previously submitted anonymous/installation-scoped crash reports are handled
  under Google's retention rules; disabling reporting discards unsent reports.

References: [Play Data safety](https://support.google.com/googleplay/android-developer/answer/10787469),
[Firebase SDK disclosures](https://firebase.google.com/docs/android/play-data-disclosure),
[Account deletion](https://support.google.com/googleplay/android-developer/answer/13327111).
