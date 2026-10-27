#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ANDROID_HOME="${ANDROID_HOME:-$PWD/.local/android-sdk}"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"
if [[ ! -x "$JAVA_HOME/bin/javac" ]]; then
  echo "Set JAVA_HOME to a full JDK 17 installation (javac is required)." >&2
  exit 1
fi
if [[ ! -d "$ANDROID_HOME/platforms/android-36" ]]; then
  echo "Install Android SDK Platform 36 and set ANDROID_HOME." >&2
  exit 1
fi
python3 tool/release_preflight.py
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub --concurrency=2
# Flutter 3.44 regenerates build-mode plugin registration only with pub enabled.
# Reusing the profile/test registrant would reference dev-only native plugins.
flutter build appbundle --release
python3 tool/verify_android_bundle.py
python3 tool/verify_android_apk.py
