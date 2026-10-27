#!/usr/bin/env python3
"""Generate policy pages and Play artwork from the same app content and logo."""
import html
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, features

ROOT = Path(__file__).resolve().parents[1]
PUBLIC = ROOT / 'hosting/public'
STORE = ROOT / 'docs/release/store-assets'


def page(title, content, script=''):
    return f'''<!doctype html>
<html lang="bn"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="theme-color" content="#054639"><title>{html.escape(title)} — রবের পথে</title>
<link rel="icon" href="/assets/icon.png"><link rel="stylesheet" href="/site.css"></head>
<body><header><a class="brand" href="/"><img src="/assets/icon.png" alt="" width="44" height="44">রবের পথে</a>
<nav aria-label="মূল নেভিগেশন"><a href="/privacy">গোপনীয়তা</a><a href="/delete-account">অ্যাকাউন্ট মুছুন</a></nav></header>
<main>{content}</main><footer>রবের পথে · Rakindotcom · <a href="/privacy">গোপনীয়তা নীতি</a></footer>{script}</body></html>'''


def main():
    policy = json.loads((ROOT / 'assets/legal/privacy.bn.json').read_text())
    PUBLIC.mkdir(parents=True, exist_ok=True)
    (PUBLIC / 'assets').mkdir(exist_ok=True)
    STORE.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / 'assets/legal/account-data-paths.json', PUBLIC / 'account-data-paths.json')
    shutil.copyfile(ROOT / 'assets/fonts/AnekBangla.ttf', PUBLIC / 'assets/AnekBangla.ttf')
    shutil.copyfile(ROOT / 'assets/fonts/AnekBangla-OFL.txt', PUBLIC / 'assets/AnekBangla-OFL.txt')
    shutil.copyfile(ROOT / 'assets/brand/app_icon.png', PUBLIC / 'assets/icon.png')
    sections = ''.join(f'<section><h2>{html.escape(s["heading"])}</h2><p>{html.escape(s["body"])}</p></section>' for s in policy['sections'])
    contact = f'<p><a href="{html.escape(policy["supportUrl"], quote=True)}">সহায়তা ও যোগাযোগ</a></p>'
    if policy['supportEmail']:
        email = html.escape(policy['supportEmail'], quote=True)
        contact += f'<p><a href="mailto:{email}">{email}</a></p>'
    (PUBLIC / 'privacy.html').write_text(page('গোপনীয়তা নীতি',
        f'<h1>গোপনীয়তা নীতি</h1><p class="muted">হালনাগাদ: {policy["updated"]}</p>{sections}{contact}<p><a href="/delete-account">ওয়েব থেকে অ্যাকাউন্ট মুছে ফেলার অনুরোধ করুন</a></p>'))
    (PUBLIC / 'index.html').write_text(page('প্রতিদিনের আমল ও আত্মপর্যালোচনা', '''
<section class="hero"><img src="/assets/icon.png" alt="রবের পথে অ্যাপের প্রতীক" width="128" height="128">
<h1>প্রতিদিন রবের পথে</h1><p>কাজ, নামাজ, গ্রোথ, কুরআন ও যিকিরের হিসাব এক জায়গায়।</p>
<div class="actions"><a class="button" href="/privacy">গোপনীয়তা নীতি</a><a class="button secondary" href="/delete-account">অ্যাকাউন্ট মুছুন</a></div></section>'''))
    (PUBLIC / 'delete-account.html').write_text(page('অ্যাকাউন্ট মুছে ফেলার অনুরোধ', '''
<h1>অ্যাকাউন্ট মুছে ফেলার অনুরোধ</h1><p>অ্যাপ ইনস্টল না থাকলেও এখান থেকে রবের পথে অ্যাকাউন্ট ও সংশ্লিষ্ট তথ্য মুছে ফেলার অনুরোধ করতে পারেন।</p>
<section><h2>কী মুছে যাবে</h2><p>আপনার প্রোফাইল, কাজ, নামাজ ও জামাতের হিসাব, গ্রোথ চেকলিস্ট, কুরআন পড়া, যিকির, পরিচিতি, পছন্দ ও অ্যাকাউন্ট মুছে যাবে। মোছা শুরু হলে নতুন তথ্য রাখা বন্ধ হবে। এটি ফিরিয়ে নেওয়া যাবে না।</p>
<p>মোছা শেষ না হওয়া পর্যন্ত এই পৃষ্ঠা খোলা রাখুন। সংযোগ বিচ্ছিন্ন হলে আবার প্রবেশ করে মোছা সম্পন্ন করুন। আগের ধাপগুলো নিরাপদে আবার চলবে। পুরনো সেশন থেকে তথ্য আবার তৈরি ঠেকাতে শুধু অ্যাকাউন্ট পরিচিতির একটি খালি রোধচিহ্ন রাখা হয়; এতে প্রোফাইল বা আমলের তথ্য থাকে না। সেবা প্রদানকারীর নিরাপত্তা লগ ও প্রযোজ্য ব্যাকআপ তাদের সংরক্ষণ নীতির অধীন। অন্য ডিভাইসে অ্যাপের তথ্য পরিষ্কার করুন বা অ্যাপ সরিয়ে দিন। <a href="/privacy">পুরো নীতি পড়ুন</a>।</p></section>
<noscript><p role="alert">এই ফর্ম ব্যবহার করতে JavaScript চালু করুন। অ্যাপের সেটিংস থেকেও অনুরোধ করতে পারেন।</p></noscript>
<p id="status" role="status" aria-live="polite">নিরাপদ ফর্ম চালু হচ্ছে…</p>
<section id="login" hidden><h2>আপনার পরিচয় নিশ্চিত করুন</h2>
<form id="login-form"><label for="email">অ্যাকাউন্টের ইমেইল</label><input id="email" type="email" autocomplete="username" required>
<label for="password">বর্তমান পাসওয়ার্ড</label><input id="password" type="password" autocomplete="current-password" required>
<button id="email-login" type="submit">ইমেইল দিয়ে প্রবেশ করুন</button></form>
<button id="google-login" class="secondary" type="button">Google দিয়ে প্রবেশ করুন</button>
<button id="reset-password" class="text-button" type="button">পাসওয়ার্ড ভুলে গেছেন?</button></section>
<section id="confirmation" hidden><h2>শেষবার নিশ্চিত করুন</h2><p id="identity"></p>
<label class="checkbox"><input id="confirm" type="checkbox">আমি বুঝেছি, আমার অ্যাকাউন্ট ও সংশ্লিষ্ট তথ্য স্থায়ীভাবে মুছে ফেলা হবে।</label>
<button id="delete" class="danger" type="button" disabled>মুছে ফেলার অনুরোধ করুন</button>
<button id="logout" class="secondary" type="button">অন্য অ্যাকাউন্ট ব্যবহার করুন</button></section>
<section id="receipt" hidden><h2>অ্যাকাউন্ট মুছে ফেলা হয়েছে</h2><p>আপনার অ্যাকাউন্ট ও সংশ্লিষ্ট সক্রিয় তথ্য মুছে ফেলা হয়েছে। এই পৃষ্ঠা বন্ধ করতে পারেন।</p></section>''',
        '<script type="module" src="/delete-account.js"></script>'))
    (PUBLIC / '404.html').write_text(page('পৃষ্ঠা পাওয়া যায়নি', '<h1>পৃষ্ঠা পাওয়া যায়নি</h1><p><a href="/">মূল পৃষ্ঠায় ফিরুন</a></p>'))
    source = Image.open(ROOT / 'assets/brand/app_icon.png')
    source.convert('RGBA').save(STORE / 'play-icon-512.png', optimize=True)
    if not features.check('raqm'):
        raise RuntimeError('Pillow with RAQM is required to shape Bengali artwork correctly.')
    image = Image.new('RGB', (1024, 500), '#054639')
    image.paste(source.convert('RGB').resize((300, 300), Image.Resampling.LANCZOS), (56, 100))
    draw = ImageDraw.Draw(image)
    font = str(ROOT / 'assets/fonts/AnekBangla.ttf')
    draw.text((402, 147), 'রবের পথে', font=ImageFont.truetype(font, 86), fill='#FFF3DB')
    draw.text((408, 278), 'প্রতিদিনের আমল ও আত্মপর্যালোচনা',
              font=ImageFont.truetype(font, 30), fill='#E0C17B')
    image.save(STORE / 'feature-graphic-1024x500.png', optimize=True)
    print('Generated public pages, bundled font and Play icon/feature graphic.')


if __name__ == '__main__':
    main()
