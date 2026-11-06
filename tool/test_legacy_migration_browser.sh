#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="$PWD/.local/node24/bin:$JAVA_HOME/bin:$PATH"
if [[ -z "${CHROME_EXECUTABLE:-}" ]]; then
  for candidate in google-chrome chromium chromium-browser brave-browser /snap/bin/brave; do
    if command -v "$candidate" >/dev/null 2>&1; then
      export CHROME_EXECUTABLE="$(command -v "$candidate")"
      break
    fi
  done
fi
if [[ -z "${CHROME_EXECUTABLE:-}" || ! -x "$CHROME_EXECUTABLE" ]]; then
  echo 'Set CHROME_EXECUTABLE to an installed Chromium browser.' >&2
  exit 1
fi
flutter pub get --enforce-lockfile
npx --yes firebase-tools@15.20.0 emulators:exec \
  --project demo-ummah --only auth,firestore \
  'flutter test --no-pub --platform chrome --dart-define=RUN_FIREBASE_EMULATOR_TESTS=true test/emulator/legacy_firestore_migration_browser_test.dart'
