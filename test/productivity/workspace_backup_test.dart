import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ummah_assist/src/productivity/core/records.dart';
import 'package:ummah_assist/src/productivity/data/productivity_database.dart';
import 'package:ummah_assist/src/productivity/data/task_repository.dart';
import 'package:ummah_assist/src/productivity/data/workspace_backup.dart';
import 'package:ummah_assist/src/productivity/domain/task.dart';

void main() {
  var sequence = 0;
  Future<ProductivityDatabase> memory() => ProductivityDatabase.open(
      uid: 'alice',
      factory: databaseFactoryMemory,
      path: 'backup-ui-${sequence++}');
  String altered(String source, void Function(Map<String, dynamic>) alter) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    alter(data);
    data.remove('checksum');
    data['checksum'] =
        sha256.convert(utf8.encode(canonicalJson(data))).toString();
    return canonicalJson(data);
  }

  test(
      'native gateway receives a portable backup and restore keeps pending work',
      () async {
    final source = await memory(), restored = await memory();
    addTearDown(source.close);
    addTearDown(restored.close);
    await TaskRepository(source).createTask(ProductivityTask(
        id: 'proposal', workspaceId: 'personal', title: 'বাংলা task'));
    final files = _Files();
    expect(await WorkspaceBackup(source, files: files).export(), isTrue);
    expect(files.name, endsWith('.json'));
    expect(utf8.decode(files.content!), contains('বাংলা task'));
    expect(await WorkspaceBackup(restored, files: files).restore(), 1);
    expect((await restored.get(RecordKind.task, 'proposal'))!.fields['title'],
        'বাংলা task');
    expect(await restored.pending(), hasLength(1));
    expect(await WorkspaceBackup(restored, files: files).restore(), 0);
  });

  test('cancelled file dialogs do not report success or change the database',
      () async {
    final db = await memory();
    addTearDown(db.close);
    final backup = WorkspaceBackup(db, files: _Files()..cancel = true);
    expect(await backup.export(), isFalse);
    expect(await backup.restore(), isNull);
    expect(await db.list(), isEmpty);
    expect(await db.pending(), isEmpty);
  });

  test(
      'recomputed checksum cannot bypass field validation or cause partial restore',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await TaskRepository(db).createTask(ProductivityTask(
        id: 'proposal', workspaceId: 'personal', title: 'Original'));
    final raw = await db.exportArchive();
    final empty = await memory();
    addTearDown(empty.close);
    final invalid = altered(
        raw,
        (data) =>
            ((data['records'] as List).single['fields'] as Map)['title'] = 42);
    final files = _Files()..content = Uint8List.fromList(utf8.encode(invalid));
    await expectLater(
        WorkspaceBackup(empty, files: files).restore(), throwsFormatException);
    expect(await empty.list(), isEmpty);
    expect(await empty.pending(), isEmpty);
  });

  test('malformed history is rejected before any live record is imported',
      () async {
    final db = await memory();
    addTearDown(db.close);
    await TaskRepository(db).createTask(ProductivityTask(
        id: 'proposal', workspaceId: 'personal', title: 'Original'));
    await TaskRepository(db).editTask('proposal', {'title': 'Edited'});
    final raw = await db.exportArchive();
    final empty = await memory();
    addTearDown(empty.close);
    final invalid = altered(raw, (data) {
      final history = data['history'] as List;
      final edit = history.firstWhere((item) => item['before'] != null);
      edit['before']['id'] = 'unrelated-task';
    });
    final files = _Files()..content = Uint8List.fromList(utf8.encode(invalid));
    await expectLater(
        WorkspaceBackup(empty, files: files).restore(), throwsFormatException);
    expect(await empty.list(), isEmpty);
  });
}

class _Files implements BackupFileGateway {
  Uint8List? content;
  String? name;
  bool cancel = false;
  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async {
    if (cancel) return false;
    name = suggestedName;
    content = bytes;
    return true;
  }

  @override
  Future<Uint8List?> open() async => cancel ? null : content;
}
