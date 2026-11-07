import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/productivity/data/firestore_portable_document.dart';

void main() {
  test('typed primitives and nested containers retain their values', () {
    expect(
        decodeFirestoreFields({
          'nothing': {'nullValue': null},
          'flag': {'booleanValue': true},
          'title': {'stringValue': 'বাংলা কাজ'},
          'count': {'integerValue': '42'},
          'ratio': {'doubleValue': 1.5},
          'nested': {
            'mapValue': {
              'fields': {
                'items': {
                  'arrayValue': {
                    'values': [
                      {'stringValue': 'one'},
                      {'integerValue': '-2'},
                    ]
                  }
                },
                'emptyMap': {'mapValue': {}},
                'emptyArray': {'arrayValue': {}},
              }
            }
          },
        }),
        {
          'nothing': null,
          'flag': true,
          'title': 'বাংলা কাজ',
          'count': 42,
          'ratio': 1.5,
          'nested': {
            'items': ['one', -2],
            'emptyMap': {},
            'emptyArray': []
          },
        });
  });

  test('timestamps retain sub-millisecond precision and pre-epoch seconds', () {
    final fields = decodeFirestoreFields({
      'precise': {'timestampValue': '1970-01-15T06:56:07.123456Z'},
      'before': {'timestampValue': '1969-12-31T23:59:59.999999Z'},
      'whole': {'timestampValue': '2026-11-06T00:00:00Z'},
    });
    expect(fields['precise'], {
      '__firestoreType': 'timestamp',
      'seconds': 1234567,
      'nanoseconds': 123456000
    });
    expect(fields['before'], {
      '__firestoreType': 'timestamp',
      'seconds': -1,
      'nanoseconds': 999999000
    });
    expect((fields['whole'] as Map)['nanoseconds'], 0);
  });

  test('64-bit integers and nonfinite doubles stay explicit portable values',
      () {
    expect(
        decodeFirestoreFields({
          'max': {'integerValue': '9223372036854775807'},
          'min': {'integerValue': '-9223372036854775808'},
          'nan': {'doubleValue': 'NaN'},
          'infinity': {'doubleValue': 'Infinity'},
        }),
        {
          'max': {'__firestoreType': 'integer', 'value': '9223372036854775807'},
          'min': {
            '__firestoreType': 'integer',
            'value': '-9223372036854775808'
          },
          'nan': {'__firestoreType': 'double', 'value': 'NaN'},
          'infinity': {'__firestoreType': 'double', 'value': 'Infinity'},
        });
  });

  test('bytes and cross-database reference provenance remain recoverable', () {
    final fields = decodeFirestoreFields({
      'binary': {'bytesValue': 'AAEC/w=='},
      'point': {
        'geoPointValue': {'latitude': 23.8, 'longitude': 90.4}
      },
      'ref': {
        'referenceValue': 'projects/other/databases/archive/documents/items/one'
      },
    });
    expect(
        fields['binary'], {'__firestoreType': 'bytes', 'base64': 'AAEC/w=='});
    expect(fields['point'],
        {'__firestoreType': 'geoPoint', 'latitude': 23.8, 'longitude': 90.4});
    expect(fields['ref'], {
      '__firestoreType': 'reference',
      'path': 'items/one',
      'resource': 'projects/other/databases/archive/documents/items/one'
    });
  });

  test('malformed typed values fail instead of silently changing source', () {
    for (final value in [
      {'stringValue': 'text', 'booleanValue': false},
      {'integerValue': '1.5'},
      {'timestampValue': '2026-02-30T00:00:00Z'},
      {'timestampValue': '2026-11-06T00:00:00+06:00'},
      {'doubleValue': 'unknown'},
      {
        'geoPointValue': {'latitude': 100, 'longitude': 0}
      },
      {'bytesValue': '??'},
      {'unknownValue': true},
    ]) {
      expect(
          () => decodeFirestoreFields({'bad': value}), throwsFormatException);
    }
    Map<String, Object?> nested = {'stringValue': 'leaf'};
    for (var i = 0; i < 30; i++) {
      nested = {
        'mapValue': {
          'fields': {'child': nested}
        }
      };
    }
    expect(
        () => decodeFirestoreFields({'deep': nested}), throwsFormatException);
  });

  test('snapshot tokens are restricted to Firebase HTTPS or demo loopback', () {
    final uri = legacySnapshotUri(
        projectId: 'assistummah', databaseId: '(default)', uid: 'owner');
    expect(uri.scheme, 'https');
    expect(uri.host, 'firestore.googleapis.com');
    expect(uri.pathSegments, [
      'v1',
      'projects',
      'assistummah',
      'databases',
      '(default)',
      'documents',
      'userTasks',
      'owner'
    ]);
    final emulator = legacySnapshotUri(
        projectId: 'demo-ummah',
        databaseId: '(default)',
        uid: 'owner',
        host: '127.0.0.1:8787',
        sslEnabled: false);
    expect(emulator.port, 8787);
    expect(emulator.scheme, 'http');
    expect(
        () => legacySnapshotUri(
            projectId: 'demo-ummah', databaseId: '(default)', uid: 'owner'),
        throwsFormatException);
    for (final host in [
      'evil.test',
      'firestore.googleapis.com@evil.test',
      'firestore.googleapis.com/path',
      'firestore.googleapis.com?x=1'
    ]) {
      expect(
          () => legacySnapshotUri(
              projectId: 'assistummah',
              databaseId: '(default)',
              uid: 'owner',
              host: host),
          throwsFormatException);
    }
    expect(
        () => legacySnapshotUri(
            projectId: 'assistummah',
            databaseId: '(default)',
            uid: 'owner',
            host: 'localhost:8787',
            sslEnabled: false),
        throwsFormatException);
    expect(
        () => legacySnapshotUri(
            projectId: 'demo-ummah', databaseId: '(default)', uid: '../other'),
        throwsFormatException);
  });
}
