import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled policy has the fields used by the offline policy screen', () {
    final policy =
        jsonDecode(File('assets/legal/privacy.bn.json').readAsStringSync())
            as Map;
    for (final key in [
      'title',
      'appName',
      'developer',
      'updated',
      'supportUrl',
      'supportEmail',
    ]) {
      expect(policy[key], isA<String>(), reason: key);
      expect((policy[key] as String).trim(), isNotEmpty, reason: key);
    }
    expect(Uri.parse(policy['supportUrl'] as String).scheme, 'https');
    expect(policy['supportEmail'], 'teamframecipher@gmail.com');
    final sections = (policy['sections'] as List).cast<Map>();
    expect(sections, isNotEmpty);
    final headings = <String>{};
    for (final section in sections) {
      expect(section['heading'], isA<String>());
      expect(section['body'], isA<String>());
      expect((section['heading'] as String).trim(), isNotEmpty);
      expect((section['body'] as String).trim(), isNotEmpty);
      expect(headings.add(section['heading'] as String), isTrue,
          reason: 'Policy section headings must be unique.');
    }
  });

  test('public policy mirrors every bundled section and contact in order', () {
    final policy =
        jsonDecode(File('assets/legal/privacy.bn.json').readAsStringSync())
            as Map;
    final page = File('hosting/public/privacy.html').readAsStringSync();
    final sections = (policy['sections'] as List).cast<Map>();
    final actual =
        RegExp(r'<section><h2>(.*?)</h2><p>(.*?)</p></section>', dotAll: true)
            .allMatches(page)
            .map((match) => (match.group(1)!, match.group(2)!))
            .toList();
    expect(
        actual,
        sections
            .map((section) => (
                  _escape(section['heading'] as String),
                  _escape(section['body'] as String),
                ))
            .toList());
    expect(page, contains('হালনাগাদ: ${_escape(policy['updated'] as String)}'));
    expect(page, contains('href="${_escape(policy['supportUrl'] as String)}"'));
    expect(page,
        contains('href="mailto:${_escape(policy['supportEmail'] as String)}"'));
  });
}

// Match Python html.escape, used by the release asset generator.
String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#x27;');
