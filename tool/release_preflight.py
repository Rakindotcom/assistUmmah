#!/usr/bin/env python3
"""Check reproducible release inputs without claiming device/Console approval."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-bundle',action='store_true')
    args=parser.parse_args()
    subprocess.run([sys.executable,str(ROOT/'tool/generate_brand_assets.py'),'--check'],check=True)
    policy=json.loads((ROOT/'assets/legal/privacy.bn.json').read_text())
    assert policy['supportEmail'] and '@' in policy['supportEmail'], 'Working contact required'
    assert 'Blaze' not in (ROOT/'firebase.json').read_text()
    assert 'functions' not in json.loads((ROOT/'firebase.json').read_text()), 'Spark-only deployment required'
    assert (ROOT/'assets/legal/account-data-paths.json').read_bytes()==(ROOT/'hosting/public/account-data-paths.json').read_bytes()
    assert all((ROOT/'hosting/public'/name).exists() for name in ['privacy.html','delete-account.html','delete-account.js','deletion-plan.mjs'])
    for name,size,mode in [('play-icon-512.png',(512,512),'RGBA'),('feature-graphic-1024x500.png',(1024,500),'RGB')]:
        path=ROOT/'docs/release/store-assets'/name
        with Image.open(path) as image: assert image.size==size and image.mode==mode,(name,image.size,image.mode)
        if name.startswith('play-icon'): assert path.stat().st_size<=1024*1024
    config=ROOT/'android/app/google-services.json'
    assert config.exists(),'Android Firebase configuration missing'
    clients=json.loads(config.read_text())['client']
    matching=[client for client in clients if client['client_info']['android_client_info']['package_name']=='com.rakindotcom.ummah_assist']
    assert len(matching)==1 and any(item.get('client_type')==3 for item in matching[0].get('oauth_client',[])), 'Google OAuth web client missing'
    signing=ROOT/'android/key.properties'
    assert signing.exists(),'Release signing missing'
    properties=dict(line.split('=',1) for line in signing.read_text().splitlines() if '=' in line)
    assert all(properties.get(key) for key in ['storeFile','storePassword','keyAlias','keyPassword'])
    assert (ROOT/'android'/properties['storeFile']).exists(),'Upload key file missing'
    if args.require_bundle:
        path=ROOT/'build/app/outputs/bundle/release/app-release.aab'
        assert path.exists(),'Signed bundle missing'
    print('PASS release inputs: branding, policy, Spark-only hosting, deletion inventory, store graphics, OAuth and private signing.')
    print('Device checks, store screenshots and Play Console approval are independent required gates.')


if __name__ == '__main__': main()
