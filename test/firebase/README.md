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
