import 'dart:convert';

/// Decodes Firestore REST values without a platform SDK's DateTime/JS-number
/// conversion. Values JSON cannot represent exactly remain explicitly tagged.
Map<String, Object?> decodeFirestoreFields(Map<String, dynamic> fields,
    [int depth = 0]) {
  if (depth > 24) throw const FormatException('Firestore nesting is too deep.');
  return {
    for (final entry in fields.entries)
      entry.key:
          _value(Map<String, dynamic>.from(entry.value as Map), depth + 1)
  };
}

Object? _value(Map<String, dynamic> value, int depth) {
  if (depth > 24 || value.length != 1) {
    throw const FormatException('Invalid Firestore value.');
  }
  final type = value.keys.single;
  final data = value[type];
  switch (type) {
    case 'nullValue':
      if (data == null || data == 'NULL_VALUE') return null;
    case 'booleanValue':
      if (data is bool) return data;
    case 'stringValue':
      if (data is String) return data;
    case 'integerValue':
      if (data is String && RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(data)) {
        final integer = BigInt.parse(data);
        if (integer.abs() <= BigInt.from(9007199254740991)) {
          return integer.toInt();
        }
        return {'__firestoreType': 'integer', 'value': integer.toString()};
      }
    case 'doubleValue':
      if (data is num && data.isFinite) return data.toDouble();
      if (const ['NaN', 'Infinity', '-Infinity'].contains(data)) {
        return {'__firestoreType': 'double', 'value': data};
      }
    case 'timestampValue':
      if (data is String) {
        final match =
            RegExp(r'^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?Z$')
                .firstMatch(data);
        if (match != null) {
          final whole = DateTime.parse('${match[1]}Z');
          if (whole.toIso8601String().split('.').first != match[1]) {
            throw const FormatException('Invalid Firestore timestamp.');
          }
          return {
            '__firestoreType': 'timestamp',
            'seconds': whole.millisecondsSinceEpoch ~/ 1000,
            'nanoseconds': int.parse((match[2] ?? '').padRight(9, '0')),
          };
        }
      }
    case 'referenceValue':
      if (data is String) {
        final match = RegExp(r'^projects/[^/]+/databases/[^/]+/documents/(.+)$')
            .firstMatch(data);
        if (match != null) {
          return {
            '__firestoreType': 'reference',
            'path': match[1],
            'resource': data
          };
        }
      }
    case 'bytesValue':
      if (data is String) {
        return {
          '__firestoreType': 'bytes',
          'base64': base64Encode(base64Decode(data))
        };
      }
    case 'geoPointValue':
      if (data is Map && data['latitude'] is num && data['longitude'] is num) {
        final latitude = (data['latitude'] as num).toDouble();
        final longitude = (data['longitude'] as num).toDouble();
        if (latitude.isFinite &&
            longitude.isFinite &&
            latitude >= -90 &&
            latitude <= 90 &&
            longitude >= -180 &&
            longitude <= 180) {
          return {
            '__firestoreType': 'geoPoint',
            'latitude': latitude,
            'longitude': longitude
          };
        }
      }
    case 'mapValue':
      if (data is Map && (data['fields'] == null || data['fields'] is Map)) {
        return decodeFirestoreFields(
            Map<String, dynamic>.from(data['fields'] as Map? ?? {}), depth);
      }
    case 'arrayValue':
      if (data is Map && (data['values'] == null || data['values'] is List)) {
        return [
          for (final item in data['values'] as List? ?? [])
            _value(Map<String, dynamic>.from(item as Map), depth + 1)
        ];
      }
  }
  throw const FormatException('Unsupported Firestore value.');
}

/// Only the Firebase endpoint or an explicit disposable local emulator may
/// receive an account ID token. Redirects are disabled by the caller.
Uri legacySnapshotUri(
    {required String projectId,
    required String databaseId,
    required String uid,
    String? host,
    bool sslEnabled = true}) {
  if ([projectId, databaseId, uid].any((value) =>
      value.isEmpty || value.contains('/') || value.contains('\\'))) {
    throw const FormatException('Invalid Firestore snapshot identity.');
  }
  final origin = Uri.parse(
      '${sslEnabled ? 'https' : 'http'}://${host ?? 'firestore.googleapis.com'}');
  final production = !projectId.startsWith('demo-') &&
      origin.host == 'firestore.googleapis.com' &&
      origin.scheme == 'https' &&
      !origin.hasPort;
  final emulator = projectId.startsWith('demo-') &&
      const ['127.0.0.1', 'localhost', '10.0.2.2', '::1'].contains(origin.host);
  if ((!production && !emulator) ||
      origin.userInfo.isNotEmpty ||
      origin.hasQuery ||
      origin.hasFragment ||
      origin.path.isNotEmpty) {
    throw const FormatException('Untrusted Firestore snapshot endpoint.');
  }
  return origin.replace(pathSegments: [
    'v1',
    'projects',
    projectId,
    'databases',
    databaseId,
    'documents',
    'userTasks',
    uid,
  ]);
}
