#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"
export ANDROID_HOME="${ANDROID_HOME:-$PWD/.local/android-sdk}"
export PATH="$JAVA_HOME/bin:$PATH"
android/gradlew -p test/native_release_harness --no-daemon --console=plain assembleDebug
