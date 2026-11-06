# Firebase deletion verification

These destructive checks refuse to run without local Auth and Firestore
emulators and use only the isolated `demo-ummah` project. They exercise the
same client SDK deletion protocol as the public page, with admin access used
only to seed fixtures and verify final state.

```sh
npm --prefix test/firebase ci
firebase emulators:exec --project demo-ummah --only auth,firestore 'npm --prefix test/firebase test'
```

Use Node 24.12 or later. The gRPC override applies the certificate-validation
fix to the Node-only Firestore test transport; no Node dependencies are deployed
or embedded in the public browser page. The browser imports the Firebase CDN SDK.

The actual Dart Firestore migration adapter has a separate browser check:

```sh
tool/test_legacy_migration_browser.sh
```

It starts disposable Auth/Firestore emulators for `demo-ummah` and opts into
`test/emulator/legacy_firestore_migration_browser_test.dart`. A Chromium browser
must be available through `CHROME_EXECUTABLE` or discovered on PATH.
The checks use two Firebase SDK clients to freeze/import a legacy snapshot,
sync later edits and tombstones, then re-import from a second local database.
They also exercise typed Firestore archive values, stale-client write rejection,
invalid source validation and account/deletion boundaries. Normal VM test runs
skip this browser-only check. Browser evidence does not establish Android
runtime behavior or production deployment state.
