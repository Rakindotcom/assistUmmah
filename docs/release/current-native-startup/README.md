# Current signed production APK startup captures

Captured by Firebase Test Lab on 6 November 2026 from the APK identified in
`../current-testlab-startup.json`. The device is a virtual ARM64 Android 16
(API 36) phone configured with 16 KB pages and Bangla (Bangladesh) locale.

- `device-details.png` is the provider's device metadata screen.
- `sign-in.png` is the actual production APK's initial signed-out screen.

Original PNG bytes are preserved. No private account credentials were supplied.
The captures prove startup/branding, not an authenticated dashboard, OS alert
delivery, physical-device behavior or a Play-installed build. This is not the
older profile integration APK. Raw run logs and the full action trace remain
private under `.local/testlab-results/`.

The configured Robo mode uses UIAutomator without app resigning. The uploaded
APK checksum was verified against the exported candidate. Its installed file
hash and an in-app page-size syscall were not independently read. The stricter
local upload-packet gate remains unsatisfied; do not describe this as that proof.
