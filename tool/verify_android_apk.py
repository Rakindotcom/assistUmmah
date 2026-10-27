#!/usr/bin/env python3
"""Generate a signed universal APK and verify its signature and 16 KB ZIP alignment.

Run after verify_android_bundle.py. Private signing passwords are passed through
temporary files in a private directory, never through command-line arguments.
This does not establish native runtime behavior or Play-generated APK behavior.
"""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile


def main():
    root = Path(__file__).resolve().parents[1]
    local = root / '.local'
    local.mkdir(exist_ok=True)
    props = dict(line.split('=', 1) for line in
                 (root / 'android/key.properties').read_text().splitlines()
                 if '=' in line)
    report_path = root / 'docs/release/bundle-verification.json'
    report = json.loads(report_path.read_text())
    bundle = root / report['bundle']
    assert hashlib.sha256(bundle.read_bytes()).hexdigest() == report['sha256'], 'Revalidate changed bundle first'
    with tempfile.TemporaryDirectory(dir=local) as temp_name:
        temp = Path(temp_name)
        for name, key in [('store-pass', 'storePassword'), ('key-pass', 'keyPassword')]:
            path = temp / name
            path.write_text(props[key])
            path.chmod(0o600)
        archive_path = temp / 'universal.apks'
        subprocess.run([
            'java', '-jar', str(local / 'bundletool.jar'), 'build-apks',
            '--bundle=' + str(bundle), '--output=' + str(archive_path),
            '--mode=universal', '--ks=' + str(root / 'android' / props['storeFile']),
            '--ks-key-alias=' + props['keyAlias'],
            '--ks-pass=file:' + str(temp / 'store-pass'),
            '--key-pass=file:' + str(temp / 'key-pass'),
        ], check=True)
        apk = local / 'app-release-universal.apk'
        with zipfile.ZipFile(archive_path) as archive:
            apk.write_bytes(archive.read('universal.apk'))
    sdk = Path(os.environ.get('ANDROID_HOME', str(local / 'android-sdk')))
    tools = sdk / 'build-tools/36.0.0'
    alignment = subprocess.run([str(tools / 'zipalign'), '-c', '-P', '16', '-v',
                                '4', str(apk)], capture_output=True, text=True, check=True)
    signature = subprocess.run([str(tools / 'apksigner'), 'verify', '--verbose',
                                str(apk)], capture_output=True, text=True, check=True)
    logs = local / 'logs'
    logs.mkdir(exist_ok=True)
    (logs / 'apk-zip-alignment.log').write_text(alignment.stdout)
    (logs / 'apk-signature.log').write_text(signature.stdout)
    report.update(
        apkZipAlignmentVerified=True,
        universalApkSignatureVerified=True,
        apkVerificationMethod='bundletool 1.18.3 universal; Android build-tools 36.0.0 zipalign -c -P 16 -v 4 and apksigner verify',
    )
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: generated universal APK signature and 16 KB ZIP alignment.')


if __name__ == '__main__':
    main()
