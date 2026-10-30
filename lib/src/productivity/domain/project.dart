import 'package:characters/characters.dart';

import '../core/records.dart';

class ProductivityProject {
  ProductivityProject({
    required this.id,
    required this.workspaceId,
    required String name,
    this.description = '',
    this.color = 0xFF087568,
    this.archived = false,
    Iterable<String> columns = const ['To do', 'In progress', 'Done'],
  })  : name = name.trim(),
        columns = List.unmodifiable(columns.map((value) => value.trim())) {
    validateRecordId(id);
    validateRecordId(workspaceId);
    if (this.name.isEmpty ||
        this.name.characters.length > 200 ||
        description.length > 100000 ||
        color < 0 ||
        color > 0xFFFFFFFF ||
        this.columns.isEmpty ||
        this.columns.length > 20 ||
        this.columns.toSet().length != this.columns.length ||
        this.columns.any((column) => column.isEmpty || column.length > 80)) {
      throw const FormatException('Invalid project details.');
    }
  }
  final String id, workspaceId, name, description;
  final int color;
  final bool archived;
  final List<String> columns;

  Map<String, Object?> toFields() => {
        'workspaceId': workspaceId,
        'name': name,
        'description': description,
        'color': color,
        'archived': archived,
        'columns': columns,
      };

  factory ProductivityProject.fromRecord(WorkspaceRecord record) {
    if (record.kind != RecordKind.project) {
      throw const FormatException('Not a project.');
    }
    return ProductivityProject(
      id: record.id,
      workspaceId: record.workspaceId,
      name: record.fields['name'] as String,
      description: record.fields['description'] as String? ?? '',
      color: record.fields['color'] as int? ?? 0xFF087568,
      archived: record.fields['archived'] == true,
      columns: List<String>.from(record.fields['columns'] as List? ??
          ['To do', 'In progress', 'Done']),
    );
  }
}
