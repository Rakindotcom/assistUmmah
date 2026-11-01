import '../core/records.dart';
import 'task.dart';

class TaskGraphConflict implements Exception {
  TaskGraphConflict(this.code, Iterable<String> taskIds)
      : taskIds = Set.unmodifiable(taskIds);
  final String code;
  final Set<String> taskIds;
  @override
  String toString() => 'TaskGraphConflict($code)';
}

/// The minimal structure needed by local validation and the cloud revision
/// guard. Task bodies and attachments do not belong in a graph snapshot.
class TaskGraphNode {
  TaskGraphNode(
      {required this.id,
      required this.workspaceId,
      this.parentId,
      Iterable<String> dependencies = const [],
      this.deleted = false})
      : dependencies = Set.unmodifiable(dependencies) {
    validateRecordId(id);
    validateRecordId(workspaceId);
    if (parentId != null) validateRecordId(parentId!);
    for (final id in this.dependencies) {
      validateRecordId(id);
    }
    if (this.dependencies.length > 200) {
      throw const FormatException('Too many prerequisites.');
    }
  }
  factory TaskGraphNode.fromTask(ProductivityTask task,
          {bool deleted = false}) =>
      TaskGraphNode(
          id: task.id,
          workspaceId: task.workspaceId,
          parentId: task.parentId,
          dependencies: task.dependencies,
          deleted: deleted);
  final String id, workspaceId;
  final String? parentId;
  final Set<String> dependencies;
  final bool deleted;

  Map<String, Object?> toProjection() => {
        'id': id,
        'workspaceId': workspaceId,
        'parentId': parentId,
        'dependencies': dependencies.toList(growable: false),
        'deleted': deleted,
      };

  factory TaskGraphNode.fromProjection(Map<String, dynamic> value) {
    final dependencies = value['dependencies'];
    if (value['id'] is! String ||
        value['workspaceId'] is! String ||
        (value['parentId'] != null && value['parentId'] is! String)) {
      throw const FormatException('Invalid task graph identity.');
    }
    if (dependencies is! List ||
        dependencies.any((item) => item is! String) ||
        dependencies.toSet().length != dependencies.length) {
      throw const FormatException('Invalid task graph dependencies.');
    }
    if (value['deleted'] is! bool) {
      throw const FormatException('Invalid task graph deletion state.');
    }
    return TaskGraphNode(
      id: value['id'] as String,
      workspaceId: value['workspaceId'] as String,
      parentId: value['parentId'] as String?,
      dependencies: List<String>.from(dependencies),
      deleted: value['deleted'] as bool,
    );
  }
}

class TaskGraph {
  TaskGraph(Iterable<TaskGraphNode> values) : nodes = _index(values);
  final Map<String, TaskGraphNode> nodes;
  static Map<String, TaskGraphNode> _index(Iterable<TaskGraphNode> values) {
    final nodes = <String, TaskGraphNode>{};
    for (final value in values) {
      if (nodes.containsKey(value.id)) {
        throw const FormatException('Duplicate task graph identity.');
      }
      nodes[value.id] = value;
    }
    return Map.unmodifiable(nodes);
  }

  TaskGraph replacing(TaskGraphNode node) => TaskGraph([
        for (final existing in nodes.values)
          if (existing.id != node.id) existing,
        node,
      ]);

  /// Missing/deleted references remain unresolved blockers while an offline
  /// queue arrives. Adding the referenced node later still checks the full DAG.
  void validate({bool allowMissing = true}) {
    final active = {
      for (final entry in nodes.entries)
        if (!entry.value.deleted) entry.key: entry.value
    };
    final prerequisites = <String, Set<String>>{
      for (final id in active.keys) id: {}
    };
    void reference(TaskGraphNode source, String id) {
      final target = active[id];
      if (target == null) {
        if (!allowMissing) {
          throw TaskGraphConflict('missing-reference', [source.id, id]);
        }
      } else if (target.workspaceId != source.workspaceId) {
        throw TaskGraphConflict('different-workspace', [source.id, id]);
      }
    }

    for (final node in active.values) {
      for (final id in node.dependencies) {
        reference(node, id);
        if (active.containsKey(id)) prerequisites[node.id]!.add(id);
      }
      final parent = node.parentId;
      if (parent != null) {
        reference(node, parent);
        if (active.containsKey(parent)) prerequisites[parent]!.add(node.id);
      }
    }
    final waiting = <String, int>{
      for (final entry in prerequisites.entries) entry.key: entry.value.length
    };
    final dependents = <String, List<String>>{};
    for (final entry in prerequisites.entries) {
      for (final prerequisite in entry.value) {
        dependents.putIfAbsent(prerequisite, () => []).add(entry.key);
      }
    }
    final ready = waiting.keys.where((id) => waiting[id] == 0).toList();
    var resolved = 0;
    while (ready.isNotEmpty) {
      final id = ready.removeLast();
      resolved++;
      for (final dependent in dependents[id] ?? <String>[]) {
        waiting[dependent] = waiting[dependent]! - 1;
        if (waiting[dependent] == 0) ready.add(dependent);
      }
    }
    if (resolved != active.length) {
      throw TaskGraphConflict(
          'circular-reference', waiting.keys.where((id) => waiting[id]! > 0));
    }
  }
}
