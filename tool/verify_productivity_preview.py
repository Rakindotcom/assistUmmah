#!/usr/bin/env python3
"""Verify the offline preview's native package isolation and APK integrity."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apk', type=Path,
                        default=ROOT / 'build/app/outputs/flutter-apk/app-preview-release.apk')
    parser.add_argument('--output', type=Path,
                        default=ROOT / '.local/logs/productivity-preview-verification.json')
    args = parser.parse_args()
    sdk = Path(os.environ.get('ANDROID_HOME', ROOT / '.local/android-sdk'))
    tools = sdk / 'build-tools/36.0.0'
    badging = subprocess.run([str(tools / 'aapt'), 'dump', 'badging', str(args.apk)],
                             capture_output=True, text=True, check=True).stdout
    package = re.search(r"package: name='([^']+)'", badging)
    assert package and package.group(1) == 'com.rakindotcom.ummah_assist.preview', \
        'Preview must use its own Android package'
    assert 'Preview' in badging, 'Preview app label is missing'
    assert 'application-debuggable' not in badging, 'Release preview is debuggable'
    manifest = subprocess.run([str(tools / 'aapt'), 'dump', 'xmltree',
                               str(args.apk), 'AndroidManifest.xml'],
                              capture_output=True, text=True, check=True).stdout
    assert 'com.google.firebase.provider.FirebaseInitProvider' not in manifest, \
        'Native Firebase auto-initialization must be removed from preview'
    with zipfile.ZipFile(args.apk) as archive:
        for name in archive.namelist():
            if name.endswith('.dex'):
                assert b'Ldev/flutter/plugins/integration_test/' not in archive.read(name), \
                    'Native integration-test plugin leaked into preview'
    subprocess.run([str(tools / 'apksigner'), 'verify', str(args.apk)], check=True)
    subprocess.run([str(tools / 'zipalign'), '-c', '-P', '16', '4', str(args.apk)],
                   check=True)
    report = {
        'apk': str(args.apk),
        'sha256': hashlib.sha256(args.apk.read_bytes()).hexdigest(),
        'package': package.group(1),
        'entrypoint': 'lib/main_productivity_preview.dart',
        'signatureVerified': True,
        'zip16KbAlignmentVerified': True,
        'nativeFirebaseInitProviderAbsent': True,
        'nativeTestPluginAbsent': True,
        'nativeRuntimeVerified': False,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS: separate preview package, absent Firebase startup provider, signature and 16 KB ZIP alignment.')
    print(f'APK: {args.apk}')


if __name__ == '__main__':
    main()
