#!/usr/bin/env python3
"""Validate an AAB's identity, signature and native 16 KB ELF alignment.

Use official bundletool 1.18.3 (SHA-256 documented in the release guide).
APK ZIP alignment and a 16 KB runtime remain separate checks.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile

from release_runtime_evidence import reconcile_runtime_evidence

ANDROID = '{http://schemas.android.com/apk/res/android}'


def elf_load_alignments(data):
    if data[:4] != b'\x7fELF': raise ValueError('Not an ELF library')
    endian = '<' if data[5] == 1 else '>'
    if data[4] == 2:
        offset = struct.unpack_from(endian+'Q', data, 32)[0]
        entry_size, count = struct.unpack_from(endian+'HH', data, 54)
        alignment_offset, fmt = 48, 'Q'
    elif data[4] == 1:
        offset = struct.unpack_from(endian+'I', data, 28)[0]
        entry_size, count = struct.unpack_from(endian+'HH', data, 42)
        alignment_offset, fmt = 28, 'I'
    else: raise ValueError('Unknown ELF class')
    return [struct.unpack_from(endian+fmt,data,offset+i*entry_size+alignment_offset)[0]
            for i in range(count) if struct.unpack_from(endian+'I',data,offset+i*entry_size)[0] == 1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle',type=Path,default=Path('build/app/outputs/bundle/release/app-release.aab'))
    parser.add_argument('--bundletool',type=Path,default=Path('.local/bundletool.jar'))
    parser.add_argument('--output',type=Path,default=Path('docs/release/bundle-verification.json'))
    args = parser.parse_args()
    subprocess.run(['java','-jar',str(args.bundletool),'validate','--bundle',str(args.bundle)],check=True,stdout=subprocess.DEVNULL)
    manifest = subprocess.run(['java','-jar',str(args.bundletool),'dump','manifest','--bundle',str(args.bundle),'--module','base'],capture_output=True,text=True,check=True).stdout
    root = ET.fromstring(manifest)
    assert root.attrib['package'] == 'com.rakindotcom.ummah_assist', 'Unexpected package ID'
    application = root.find('application')
    assert application is not None
    for attribute in ['debuggable', 'testOnly', 'usesCleartextTraffic']:
        assert application.attrib.get(ANDROID+attribute, 'false') != 'true', f'Unexpected release flag: {attribute}'
    uses_sdk = root.find('uses-sdk')
    assert int(uses_sdk.attrib[ANDROID+'targetSdkVersion']) >= 36, 'Target SDK below 36'
    signature = subprocess.run(['jarsigner','-verify',str(args.bundle)],capture_output=True,text=True,check=True)
    assert 'jar verified.' in signature.stdout, 'Bundle signature not verified'
    libraries = []
    with zipfile.ZipFile(args.bundle) as archive:
        assert any(name.startswith('META-INF/') and name.endswith('.RSA') for name in archive.namelist()), 'Missing upload signature'
        for name in archive.namelist():
            if name.endswith('.dex'):
                assert b'Ldev/flutter/plugins/integration_test/' not in archive.read(name), 'Native integration-test plugin leaked into production release'
            if not name.endswith('.so') or '/lib/' not in name: continue
            alignments = elf_load_alignments(archive.read(name))
            is_64bit = '/arm64-v8a/' in name or '/x86_64/' in name
            assert alignments and (not is_64bit or all(value >= 16384 for value in alignments)), f'16 KB ELF alignment failed: {name}'
            libraries.append({'path':name,'loadAlignments':alignments})
    assert any('/arm64-v8a/' in item['path'] for item in libraries), 'ARM64 missing'
    output = {
        'bundle':str(args.bundle),'sha256':hashlib.sha256(args.bundle.read_bytes()).hexdigest(),
        'package':root.attrib['package'],'versionName':root.attrib[ANDROID+'versionName'],
        'versionCode':int(root.attrib[ANDROID+'versionCode']),
        'minSdk':int(uses_sdk.attrib[ANDROID+'minSdkVersion']),
        'targetSdk':int(uses_sdk.attrib[ANDROID+'targetSdkVersion']),
        'signatureVerified':True,'nativeLibraries':libraries,
        'nativeTestPluginAbsent':True,'debuggable':False,'testOnly':False,
        'cleartextTrafficExplicitlyAllowed':False,
        'permissions':sorted(node.attrib[ANDROID+'name'] for node in root.findall('uses-permission')),
        'runtime16KbVerified':False,'apkZipAlignmentVerified':False,
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(output,indent=2)+'\n')
    args.output.with_suffix('.manifest.xml').write_text('\n'.join(line.rstrip() for line in manifest.splitlines()) + '\n')
    release_report = Path(__file__).resolve().parents[1] / 'docs/release/bundle-verification.json'
    if args.output.resolve() == release_report:
        reconcile_runtime_evidence(args.output.parent, output['sha256'])
    print(f'Validated signed bundle, API {output["targetSdk"]}, ARM64 and {len(libraries)} native libraries.')
    print('Still required: generated APK ZIP alignment and native runtime verification.')


if __name__ == '__main__': main()
