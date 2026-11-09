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


def elf_build_id(data):
    """Read the GNU build ID retained by Android's native symbol stripping."""
    if data[:4] != b'\x7fELF':
        raise ValueError('Not an ELF library')
    endian = '<' if data[5] == 1 else '>'
    if data[4] == 2:
        offset = struct.unpack_from(endian + 'Q', data, 32)[0]
        entry_size, count = struct.unpack_from(endian + 'HH', data, 54)
        offset_field, size_field, number = 8, 32, 'Q'
    elif data[4] == 1:
        offset = struct.unpack_from(endian + 'I', data, 28)[0]
        entry_size, count = struct.unpack_from(endian + 'HH', data, 42)
        offset_field, size_field, number = 4, 16, 'I'
    else:
        raise ValueError('Unknown ELF class')
    for index in range(count):
        header = offset + index * entry_size
        if struct.unpack_from(endian + 'I', data, header)[0] != 4:  # PT_NOTE
            continue
        start = struct.unpack_from(endian + number, data, header + offset_field)[0]
        end = start + struct.unpack_from(endian + number, data, header + size_field)[0]
        if end > len(data):
            raise ValueError('Truncated ELF note segment')
        while start + 12 <= end:
            name_size, value_size, kind = struct.unpack_from(endian + 'III', data, start)
            start += 12
            name = data[start:start + name_size].rstrip(b'\0')
            start += (name_size + 3) & ~3
            value = data[start:start + value_size]
            start += (value_size + 3) & ~3
            if start > end:
                raise ValueError('Truncated ELF note')
            if name == b'GNU' and kind == 3 and value:
                return value.hex()
    raise ValueError('Missing GNU build ID')


def verify_compiled_aot(packaged, compiled):
    packaged_id, compiled_id = elf_build_id(packaged), elf_build_id(compiled)
    assert packaged_id == compiled_id, (
        'Stale packaged Dart library: GNU build ID differs from current compiler output. '
        'Run the clean release build before exporting or testing this bundle.')
    return packaged_id


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
    parser.add_argument('--bundle',type=Path,default=Path('build/app/outputs/bundle/productionRelease/app-production-release.aab'))
    parser.add_argument('--bundletool',type=Path,default=Path('.local/bundletool.jar'))
    parser.add_argument('--output',type=Path,default=Path('docs/release/bundle-verification.json'))
    parser.add_argument('--aot-dir', type=Path,
                        default=Path('build/app/intermediates/flutter/productionRelease'))
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
    dart_libraries = []
    with zipfile.ZipFile(args.bundle) as archive:
        assert any(name.startswith('META-INF/') and name.endswith('.RSA') for name in archive.namelist()), 'Missing upload signature'
        for name in archive.namelist():
            if name.endswith('.dex'):
                assert b'Ldev/flutter/plugins/integration_test/' not in archive.read(name), 'Native integration-test plugin leaked into production release'
            if not name.endswith('.so') or '/lib/' not in name: continue
            if name.endswith('/libapp.so'):
                abi = name.split('/')[-2]
                compiled = args.aot_dir / abi / 'app.so'
                assert compiled.is_file(), f'Current compiled Dart library missing: {compiled}'
                dart_libraries.append({'abi': abi, 'buildId': verify_compiled_aot(
                    archive.read(name), compiled.read_bytes()), 'compilerOutput': str(compiled)})
            alignments = elf_load_alignments(archive.read(name))
            is_64bit = '/arm64-v8a/' in name or '/x86_64/' in name
            assert alignments and (not is_64bit or all(value >= 16384 for value in alignments)), f'16 KB ELF alignment failed: {name}'
            libraries.append({'path':name,'loadAlignments':alignments})
    assert any('/arm64-v8a/' in item['path'] for item in libraries), 'ARM64 missing'
    assert any(item['abi'] == 'arm64-v8a' for item in dart_libraries), 'ARM64 Dart library missing'
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
        'compiledDartLibraryBuildIdsVerified': True, 'compiledDartLibraries': dart_libraries,
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
