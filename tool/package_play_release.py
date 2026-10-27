#!/usr/bin/env python3
"""Assemble public Play upload inputs; never include private signing credentials."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    docs = ROOT / 'docs/release'
    verification = json.loads((docs / 'bundle-verification.json').read_text())
    bundle = ROOT / verification['bundle']
    assert hashlib.sha256(bundle.read_bytes()).hexdigest() == verification['sha256'], 'Bundle changed: revalidate first'
    assert verification['signatureVerified'] and verification['apkZipAlignmentVerified']
    private_review = ROOT / '.local/play-reviewer-credentials.json'
    if private_review.exists():
        credentials = json.loads(private_review.read_text())
        literals = [credentials[key].encode() for key in ['email', 'password']]
        with zipfile.ZipFile(bundle) as archive:
            for member in archive.infolist():
                if member.is_dir():
                    continue
                data = archive.read(member)
                assert not any(value in data for value in literals), 'Review credential literal found in production bundle'
    version = f"{verification['versionName']}-{verification['versionCode']}"
    assert re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._+-]*', version), 'Unsafe output version'
    destination = ROOT / 'dist/play-store' / version
    # Only replace this tool's generated version folder.
    if destination.exists():
        shutil.rmtree(destination)
    destination.mkdir(parents=True)
    shutil.copy2(bundle, destination / 'app-release.aab')
    for name in ['README.md', 'console-handoff.md', 'store-listing.md',
                 'data-safety.md', 'release-notes-bn.txt',
                 'bundle-verification.json', 'bundle-verification.manifest.xml',
                 'verification-summary.json', 'upload-certificate.pem',
                 'upload-certificate.json', 'android-emulator-environment.json',
                 'deletion-web-verification.json', 'deletion-web-proof.jpg',
                 'signed-release-smoke.json']:
        shutil.copy2(docs / name, destination / name)
    shutil.copytree(docs / 'store-assets', destination / 'store-assets')
    native_report = docs / 'native-verification.json'
    if native_report.exists():
        report = json.loads(native_report.read_text())
        assert report['nativeStartup'] and report['screenCount'] >= 2
        images = sorted((docs / 'native-captures').glob('*.png'))
        assert len(images) >= 2
        for path in images:
            with Image.open(path) as image:
                width, height = image.size
                assert min(width, height) >= 320 and max(width, height) <= 3840
                assert max(width, height) <= min(width, height) * 2, path.name
        shutil.copytree(docs / 'native-captures', destination / 'native-captures')
        exports = []
        for path in images:
            target = destination / 'native-captures' / path.name
            with Image.open(path) as original:
                if original.mode == 'RGBA':
                    assert original.getextrema()[3] == (255, 255), 'Capture has non-opaque pixels'
                else:
                    assert original.mode == 'RGB', 'Unexpected capture format'
                rgb = original.convert('RGB')
                rgb.save(target, format='PNG', optimize=True)
                with Image.open(target) as exported:
                    assert exported.mode == 'RGB' and exported.tobytes() == rgb.tobytes()
            exports.append({
                'file': path.name,
                'sourceSha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'exportSha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                'mode': 'RGB', 'rgbPixelsUnchanged': True,
            })
        (destination / 'native-captures/export-verification.json').write_text(
            json.dumps(exports, indent=2) + '\n')
        shutil.copy2(native_report, destination / native_report.name)
    files = sorted(path for path in destination.rglob('*') if path.is_file())
    assert all(path.suffix not in ['.jks', '.keystore', '.p12'] for path in files)
    assert not any(path.name in ['key.properties', 'google-services.json'] for path in files)
    (destination / 'SHA256SUMS.txt').write_text(''.join(
        f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(destination).as_posix()}\n'
        for path in files))
    archive_path = destination.parent / f'rober-pothe-{version}.zip'
    with zipfile.ZipFile(archive_path, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(destination.rglob('*')):
            if path.is_file():
                archive.write(path, arcname=path.relative_to(destination))
    print(f'Release packet: {archive_path}')
    print('Private upload key and passwords excluded. Console work remains manual.')


if __name__ == '__main__':
    main()
