#!/usr/bin/env python3
"""Create a local upload key once. Never prints passwords or overwrites a key."""
import os
from pathlib import Path
import secrets
import subprocess

ROOT = Path(__file__).resolve().parents[1]
KEY = ROOT / 'android/upload-keystore.jks'
PROPERTIES = ROOT / 'android/key.properties'


def main():
    if KEY.exists() or PROPERTIES.exists():
        if KEY.exists() and PROPERTIES.exists():
            print('Existing Android signing files retained.')
            return
        raise SystemExit('Only one signing file exists. Restore its matching file before proceeding.')
    os.umask(0o077)
    password = secrets.token_urlsafe(36)
    # Save recovery information before keytool creates the private key.
    with PROPERTIES.open('x') as stream:
        stream.write(f'storeFile=upload-keystore.jks\nstorePassword={password}\nkeyAlias=upload\nkeyPassword={password}\n')
    environment = {**os.environ, 'ROBER_UPLOAD_KEY_PASSWORD': password}
    result = subprocess.run([
        'keytool', '-genkeypair', '-keystore', str(KEY), '-storetype', 'JKS',
        '-alias', 'upload', '-keyalg', 'RSA', '-keysize', '3072', '-validity', '10000',
        '-dname', 'CN=Rober Pothe Upload',
        '-storepass:env', 'ROBER_UPLOAD_KEY_PASSWORD', '-keypass:env', 'ROBER_UPLOAD_KEY_PASSWORD',
    ], env=environment, capture_output=True)
    if result.returncode:
        raise SystemExit('Key generation failed. Preserve the private properties file and inspect keytool locally.')
    KEY.chmod(0o600)
    PROPERTIES.chmod(0o600)
    print('Created private Android upload key and signing properties (mode 0600).')
    print('Back up both ignored files securely before uploading a release.')


if __name__ == '__main__':
    main()
