import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final output = Directory('docs/release/native-captures');
  await output.create(recursive: true);
  final evidence = File('docs/release/native-verification.json');
  if (await evidence.exists()) await evidence.delete();
  await integrationDriver(onScreenshot: (name, bytes, [args]) async {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) return false;
    await File('${output.path}/$name.png').writeAsBytes(bytes);
    return bytes.isNotEmpty;
  }, responseDataCallback: (data) async {
    final report = Map<String, dynamic>.from(data ?? {})..remove('screenshots');
    report['verifiedAtUtc'] = DateTime.now().toUtc().toIso8601String();
    report['buildMode'] = 'profile integration test';
    await evidence.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n');
  });
}
