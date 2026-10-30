import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../core/records.dart';
import '../domain/experience_options.dart';
import '../domain/project.dart';
import '../domain/task.dart';
import '../domain/task_occurrence.dart';
import 'productivity_database.dart';

abstract interface class BackupFileGateway {
  Future<bool> save(String suggestedName, Uint8List bytes);
  Future<Uint8List?> open();
}

class NativeBackupFiles implements BackupFileGateway {
  const NativeBackupFiles();
  static const maxBytes = 25 * 1024 * 1024;
  @override
  Future<bool> save(String suggestedName, Uint8List bytes) async =>
      await FilePicker.saveFile(
          fileName: suggestedName,
          bytes: bytes,
          mimeType: 'application/json') !=
      null;
  @override
  Future<Uint8List?> open() async {
    final file = await FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: ['json']);
    if (file == null) return null;
    final length = await file.length();
    if (length != null && length > maxBytes) {
      throw const FormatException('Backup exceeds the 25 MB import limit.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (builder.length + chunk.length > maxBytes) {
        throw const FormatException('Backup exceeds the 25 MB import limit.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

class WorkspaceBackup {
  const WorkspaceBackup(this.database,
      {this.files = const NativeBackupFiles()});
  final ProductivityDatabase database;
  final BackupFileGateway files;

  Future<bool> export() async {
    final archive = await database.exportArchive();
    final bytes = Uint8List.fromList(utf8.encode(archive));
    // A file we export must fit the import path in this app version.
    if (bytes.length > NativeBackupFiles.maxBytes) {
      throw const FormatException('Backup exceeds this version’s file limit.');
    }
    final date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    return files.save('rober-pothe-workspace-$date.json', bytes);
  }

  Future<int?> restore() async {
    final bytes = await files.open();
    if (bytes == null) return null;
    if (bytes.length > NativeBackupFiles.maxBytes) {
      throw const FormatException('Backup is too large.');
    }
    return database.importArchive(utf8.decode(bytes),
        validateRecords: validateRecords);
  }

  /// An integrity checksum alone does not validate domain data. A file with a
  /// recomputed checksum still cannot introduce mistyped task fields into UI.
  static void validateRecords(List<WorkspaceRecord> records) {
    try {
      for (final record in records) {
        switch (record.kind) {
          case RecordKind.task:
            ProductivityTask.fromRecord(record);
          case RecordKind.taskOccurrence:
            TaskOccurrence.fromRecord(record);
          case RecordKind.project:
            ProductivityProject.fromRecord(record);
          case RecordKind.workspace:
            if (record.fields['type'] == 'experienceOptions') {
              ExperienceOptions.fromRecord(record);
            }
          case RecordKind.note:
            if (record.fields['body'] is! String ||
                (record.fields['title'] != null &&
                    record.fields['title'] is! String)) {
              throw const FormatException('Invalid note in backup.');
            }
          default:
            throw const FormatException(
                'This backup needs a newer version of the app.');
        }
      }
    } on TypeError {
      throw const FormatException('Invalid field types in backup.');
    } on ArgumentError {
      throw const FormatException('Invalid field values in backup.');
    }
  }
}
