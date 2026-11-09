# Current release audit — দ্বীন ও দুনিয়া

Updated 10 November 2026 (Asia/Dhaka). Candidate: **1.0.0+9**.

## Name change

The public name is updated across Flutter, Android/iOS launcher metadata, web
and PWA metadata, bundled/public privacy pages, support pages, store listing,
release notes and feature artwork. Anek Bangla and the existing icon are retained.
New export filenames use the current name. The backup archive format is now
independent of branding; versions 1 and 2 remain importable with checksum,
account ownership, schema and transactional validation.

Account data, package ID `com.rakindotcom.ummah_assist`, Firebase project,
permissions and release signing identity are unchanged. The production entry
remains `lib/main.dart` → `AppBootstrap` → `AuthGate` → `HomeShell`.

## Verification

| Check | Result |
| --- | --- |
| Analyzer | Passed, no issues. |
| Affected app/bootstrap/privacy/backup checks | 51 passed, including earlier archive import. |
| Mobile sign-in layout checks | Five passed. |
| Phone branding previews | Home, sign-in and sign-up rendered and visually reviewed at 390×844; preview renderer passed. |
| Source scan | No previous app-name references in tracked text files. |
| Platform names | Android main/preview, iOS display/bundle names, and web/PWA names checked. |
| Signed production AAB | API 36, ARM64, no native test plugin; 16 KB ELF alignment and compiler-to-packaged Dart identities verified. |
| Universal APK | Signature, existing upload certificate and 16 KB ZIP alignment verified. |
| Packaged identity | Actual AAB launcher label and bundled privacy name checked. Anek Bangla retained. |
| Public website | Home, privacy, deletion and not-found pages deployed and read back with the requested name. Firebase billing verified disabled. |

Source checkpoint: `59e09371a4fe9c31bb0c0b360b87e760ef3e52af`.
The full Flutter suite was not rerun for this name change; the 56 affected/layout
checks above and one preview-render check are the current verification scope.

## Current downloads

- APK: `output/apk/deen-o-duniya-1.0.0-build9.apk`.
- AAB: `output/aab/deen-o-duniya-1.0.0-build9.aab`.

SHA-256 sidecars accompany both files. Hashes, sizes and source identity are in
`current-release-artifacts.json`. Older download files and screenshots displaying
the previous name are archived locally. No approved Play upload packet exists.

Build 8 previously passed all seven physical Galaxy A15 release cases in
`matrix-dhm0jqrx3qsqa`, including independent server persistence, isolation and
deletion checks. Those binary-bound receipts are historical for build 9 and
must not be presented as a native pass for the renamed binary. Existing native
screenshots also show the previous name; they are not current store artwork.

Fresh native verification is blocked by exhausted free Test Lab quota
(`matrix-h8nwgv9phl5pa`, `INVALID / TEST_QUOTA_EXCEEDED`). No paid run or billing
upgrade is authorized. No device test is running. All disposable accounts from
completed and rejected runs are cleaned.

## Remaining release gates

- Native startup/UI and diagnostics verification for the exact renamed binary
  when free device testing is available. Current-name phone widget renders are
  previews, not Play store/device evidence.
- Lifecycle/accessibility checks: natural-clock latency, reboot/Doze, long
  sessions, TalkBack and applicable device behavior.
- Manual Play Console: signing certificate registration, Play-installed password
  and Google login, internal/pre-launch tests, listing/declarations, content
  rating, audience, developer identity and any required closed testing.
- Hosted CI account lock: the last inspected run had zero job steps and an
  explicit account billing-lock annotation. No hosted CI pass is claimed.

Firebase remains Spark with billing disabled. Support: **teamframecipher@gmail.com**.
Play Console work stays manual. Public release is not approved.
