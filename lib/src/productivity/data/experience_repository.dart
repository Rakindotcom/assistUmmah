import '../core/records.dart';
import '../domain/experience_options.dart';
import 'productivity_database.dart';

class ExperienceRepository {
  const ExperienceRepository(this.database);
  final ProductivityDatabase database;
  static const optionsId = 'experience_options_v1';

  Stream<ExperienceOptions?> watchOptions() => database
          .watch(kind: RecordKind.workspace, workspaceId: 'system')
          .map((records) {
        for (final record in records) {
          if (record.id == optionsId) {
            return ExperienceOptions.fromRecord(record);
          }
        }
        return null;
      });

  Future<void> completeOnboarding(ExperienceOptions options) async {
    if (!options.completedOnboarding) {
      throw ArgumentError('Complete onboarding first.');
    }
    await database.changeRecords(
        kinds: {RecordKind.workspace},
        plan: (records) {
          // Repeated submits/another tab must not overwrite established preferences.
          if (records.any((record) =>
              record.id == optionsId &&
              !record.deleted &&
              record.fields['completedOnboarding'] == true)) {
            return [];
          }
          return [
            for (final module in options.modules)
              RecordMutation(
                  kind: RecordKind.workspace,
                  id: module.name,
                  workspaceId: module.name,
                  ifAbsent: true,
                  patch: {
                    'type': 'workspace',
                    'module': module.name,
                    'name': module.name,
                    'archived': false
                  }),
            RecordMutation(
                kind: RecordKind.workspace,
                id: optionsId,
                workspaceId: 'system',
                ifAbsent: true,
                patch: options.toFields()),
          ];
        });
  }

  /// Patch only user-edited settings so unrelated fields from another device
  /// retain their clocks. Disabling a module never deletes its data.
  Future<void> updateOptions(Map<String, Object?> patch) async {
    await database.changeRecords(
        kinds: {RecordKind.workspace},
        plan: (records) {
          final previous = records
              .where((record) => record.id == optionsId && !record.deleted)
              .firstOrNull;
          if (previous == null) {
            throw StateError('Workspace setup is incomplete.');
          }
          final allowed = ExperienceOptions.fromRecord(previous)
              .toFields()
              .keys
              .toSet()
            ..removeAll(['workspaceId', 'type', 'completedOnboarding']);
          if (patch.keys.any((key) => !allowed.contains(key))) {
            throw ArgumentError('Invalid preference.');
          }
          final fields = {...previous.fields, ...validatedFields(patch)};
          final options = ExperienceOptions.fromRecord(WorkspaceRecord(
              ownerId: previous.ownerId,
              kind: previous.kind,
              id: previous.id,
              fields: fields,
              clocks: {
                for (final key in fields.keys) key: previous.clocks.values.first
              },
              modifiedAtMillis: previous.modifiedAtMillis));
          final changes = <String, Object?>{
            for (final entry in patch.entries)
              if (canonicalJson(previous.fields[entry.key]) !=
                  canonicalJson(entry.value))
                entry.key: entry.value,
          };
          return [
            for (final module in options.modules)
              if (!records.any((record) => record.id == module.name))
                RecordMutation(
                    kind: RecordKind.workspace,
                    id: module.name,
                    workspaceId: module.name,
                    ifAbsent: true,
                    patch: {
                      'type': 'workspace',
                      'module': module.name,
                      'name': module.name,
                      'archived': false
                    }),
            if (changes.isNotEmpty)
              RecordMutation(
                  kind: RecordKind.workspace,
                  id: optionsId,
                  workspaceId: 'system',
                  patch: changes),
          ];
        });
  }
}
