#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export ANDROID_HOME="${ANDROID_HOME:-$PWD/.local/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export PATH="$JAVA_HOME/bin:$PATH"
if [[ ! -x "$JAVA_HOME/bin/javac" ]]; then
  echo "Set JAVA_HOME to a full JDK 17 installation." >&2
  exit 1
fi
flutter build apk --release --flavor preview -t lib/main_productivity_preview.dart
python3 tool/verify_productivity_preview.py
