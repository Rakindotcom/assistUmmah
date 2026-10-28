#!/usr/bin/env python3
"""Fresh-start the signed APK on the dedicated disposable 16 KB emulator.

This clears only that emulator's app data. It never runs on a physical device.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from datetime import datetime, timezone


ROOT = Path(__file__).resolve().parents[1]
SDK = Path(os.environ.get('ANDROID_HOME', ROOT / '.local/android-sdk'))
ADB = SDK / 'platform-tools/adb'
DEVICE = 'emulator-5556'
AVD = 'rober_pothe_audit_16k'
APK = ROOT / '.local/app-release-universal.apk'
DOCS = ROOT / 'docs/release'


def adb(*args: str) -> str:
    result = subprocess.run(
        [str(ADB), '-s', DEVICE, *args],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=40,
    )
    return result.stdout.strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    verification = json.loads((DOCS / 'bundle-verification.json').read_text())
    package = verification['package']
    bundle = ROOT / verification['bundle']
    assert bundle.is_file() and sha256(bundle) == verification['sha256']
    assert verification['signatureVerified'] and verification['apkZipAlignmentVerified']
    assert APK.is_file()
    apk_hash = sha256(APK)

    assert adb('emu', 'avd', 'name').splitlines()[0] == AVD, 'Wrong emulator; refusing to clear app data'
    assert adb('shell', 'getprop', 'sys.boot_completed') == '1'
    assert adb('shell', 'getconf', 'PAGESIZE') == '16384'
    assert adb('shell', 'getprop', 'ro.build.version.sdk') == '36'
    assert adb('shell', 'getprop', 'ro.product.cpu.abi') == 'x86_64'

    assert 'Success' in adb('install', '-r', str(APK))
    assert adb('shell', 'pm', 'clear', package) == 'Success'
    installed_path = adb('shell', 'pm', 'path', package)
    assert installed_path.startswith('package:/data/app/') and installed_path.endswith('/base.apk')
    device_hash = adb('shell', 'sha256sum', installed_path.removeprefix('package:')).split()[0]
    assert device_hash == apk_hash, 'Installed APK differs from validated artifact'

    adb('logcat', '-c')
    launch = adb('shell', 'monkey', '-p', package, '-c', 'android.intent.category.LAUNCHER', '1')
    assert 'Events injected: 1' in launch

    ready = False
    for _ in range(5):
        time.sleep(3)
        adb('shell', 'uiautomator', 'dump', '/sdcard/rober-pothe-smoke.xml')
        ui = adb('shell', 'cat', '/sdcard/rober-pothe-smoke.xml')
        if 'লগইন' in ui and 'রবের পথে' in ui:
            ready = True
            break
    assert ready and 'অ্যাপ চালু করা যায়নি' not in ui, 'Signed app did not reach its login screen'

    pid = adb('shell', 'pidof', package)
    assert pid.isdigit(), 'Release process is not running'
    activities = adb('shell', 'dumpsys', 'activity', 'activities')
    assert f'topResumedActivity=ActivityRecord' in activities and f'{package}/.MainActivity' in activities
    logs = adb('logcat', '-d', '-s', 'ComponentDiscovery:V', 'FirebaseApp:V',
               'FirebaseCrashlytics:V', 'FirebaseInitProvider:V', 'flutter:I')
    assert 'Invalid component registrar' not in logs, 'Firebase registrar failed in release mode'
    assert 'FirebaseCrashlytics component is not present' not in logs
    assert 'FirebaseApp initialization successful' in logs
    assert 'Initializing Firebase Crashlytics' in logs

    report = {
        'verifiedAtUtc': datetime.now(timezone.utc).isoformat(),
        'package': package,
        'versionName': verification['versionName'],
        'versionCode': verification['versionCode'],
        'sourceBundleSha256': verification['sha256'],
        'universalApkSha256': apk_hash,
        'installedApkHashMatches': True,
        'androidApi': 36,
        'pageSize': 16384,
        'architecture': 'x86_64',
        'productionReleaseBinary': True,
        'activityResumed': True,
        'processRunning': True,
        'loginScreenVisibleInAccessibilityTree': True,
        'firebaseInitialized': True,
        'firebaseCrashlyticsInitialized': True,
        'firebaseRegistrarErrorsAbsent': True,
        'scope': 'Fresh signed APK startup/login smoke on dedicated 16 KB emulator. Full app flow, physical ARM64 and Play-signed builds remain unverified.',
    }
    (DOCS / 'signed-release-smoke.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print('PASS: signed APK hash, Firebase startup and login UI on the 16 KB emulator.')


if __name__ == '__main__':
    main()
