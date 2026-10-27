#!/usr/bin/env python3
"""Export platform-sized icons from the supplied artwork without redrawing it.

Requires Pillow: python3 -m pip install Pillow
Run from any directory; --check verifies committed outputs without writing.
"""

import argparse
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = '#054639'
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def padded(source, size, fraction, transparent=False):
    canvas = Image.new('RGBA' if transparent else 'RGB', (size, size),
                       (0, 0, 0, 0) if transparent else BACKGROUND)
    side = round(size * fraction)
    image = source.resize((side, side), Image.Resampling.LANCZOS)
    canvas.paste(image, ((size - side) // 2, (size - side) // 2))
    return canvas


def exports(source):
    yield 'assets/brand/app_icon.png', source.resize((512, 512), Image.Resampling.LANCZOS)
    for density, scale in DENSITIES.items():
        prefix = f'android/app/src/main/res/mipmap-{density}'
        size = round(48 * scale)
        icon = source.resize((size, size), Image.Resampling.LANCZOS)
        yield f'{prefix}/ic_launcher.png', icon
        yield f'{prefix}/ic_launcher_round.png', icon
        # Keep the whole mark within Android's 66dp safe circle in a 108dp layer.
        yield f'{prefix}/ic_launcher_foreground.png', padded(
            source, round(108 * scale), 0.60, transparent=True)
        yield f'android/app/src/main/res/drawable-{density}/brand_splash.png', source.resize(
            (round(128 * scale), round(128 * scale)), Image.Resampling.LANCZOS)

    catalog = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    seen = set()
    for item in json.loads((catalog / 'Contents.json').read_text())['images']:
        filename = item['filename']
        if filename in seen:
            continue
        seen.add(filename)
        size = round(float(item['size'].split('x')[0]) * float(item['scale'][:-1]))
        # RGB is deliberate: iOS app icons must be opaque.
        yield str(catalog.relative_to(ROOT) / filename), source.resize(
            (size, size), Image.Resampling.LANCZOS)
    for scale in (1, 2, 3):
        suffix = '' if scale == 1 else f'@{scale}x'
        yield f'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage{suffix}.png', source.resize(
            (128 * scale, 128 * scale), Image.Resampling.LANCZOS)

    yield 'web/favicon.png', source.resize((32, 32), Image.Resampling.LANCZOS)
    yield 'web/apple-touch-icon.png', source.resize((180, 180), Image.Resampling.LANCZOS)
    for size in (192, 512):
        yield f'web/icons/Icon-{size}.png', source.resize((size, size), Image.Resampling.LANCZOS)
        # PWA masks use the central 80% safe circle.
        yield f'web/icons/Icon-maskable-{size}.png', padded(source, size, 0.80)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    source = Image.open(ROOT / 'assets/brand/source.png').convert('RGB')
    if source.width != source.height:
        raise SystemExit('The source icon must be square.')
    count = 0
    for relative, expected in exports(source):
        path = ROOT / relative
        if args.check:
            if not path.exists():
                raise SystemExit(f'Missing icon: {relative}')
            with Image.open(path) as actual:
                if actual.size != expected.size or actual.mode != expected.mode or actual.tobytes() != expected.tobytes():
                    raise SystemExit(f'Icon needs regeneration: {relative}')
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            expected.save(path, optimize=True)
        count += 1
    print(f'{"Verified" if args.check else "Generated"} {count} brand assets.')


if __name__ == '__main__':
    main()
