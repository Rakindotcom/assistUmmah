import 'package:flutter_test/flutter_test.dart';
import 'package:ummah_assist/src/productivity/domain/task_graph.dart';

void main() {
  TaskGraphNode node(String id,
          {String workspace = 'personal',
          String? parent,
          List<String> dependencies = const [],
          bool deleted = false}) =>
      TaskGraphNode(
          id: id,
          workspaceId: workspace,
          parentId: parent,
          dependencies: dependencies,
          deleted: deleted);
  Matcher conflict(String code) =>
      isA<TaskGraphConflict>().having((value) => value.code, 'code', code);

  test('individually valid offline edits can form a cycle after merge', () {
    final initial = TaskGraph([node('a'), node('b')]);
    final clientA = initial.replacing(node('a', dependencies: ['b']));
    final clientB = initial.replacing(node('b', dependencies: ['a']));
    clientA.validate();
    clientB.validate();
    final merged = clientA.replacing(clientB.nodes['b']!);
    expect(merged.validate, throwsA(conflict('circular-reference')));
    expect(merged.replacing(node('b')).validate, returnsNormally);
  });
  test('combined child prerequisites and dependency edges detect mixed cycles',
      () {
    final graph = TaskGraph([
      node('parent'),
      node('child', parent: 'parent', dependencies: ['parent'])
    ]);
    expect(graph.validate, throwsA(conflict('circular-reference')));
  });
  test('out-of-order arrivals are safe but closing a future cycle is rejected',
      () {
    final waiting = TaskGraph([
      node('a', dependencies: ['b'])
    ]);
    expect(waiting.validate, returnsNormally);
    expect(() => waiting.validate(allowMissing: false),
        throwsA(conflict('missing-reference')));
    expect(waiting.replacing(node('b', dependencies: ['a'])).validate,
        throwsA(conflict('circular-reference')));
  });
  test('cross-workspace references and duplicate identities are rejected', () {
    final graph = TaskGraph([
      node('a', dependencies: ['b']),
      node('b', workspace: 'work')
    ]);
    expect(graph.validate, throwsA(conflict('different-workspace')));
    expect(() => TaskGraph([node('a'), node('a')]), throwsFormatException);
  });
  test('malformed cloud graph projection is a validation error', () {
    final projection = node('a').toProjection();
    expect(() => TaskGraphNode.fromProjection({...projection, 'id': 4}),
        throwsFormatException);
    expect(() => TaskGraphNode.fromProjection({...projection, 'parentId': 4}),
        throwsFormatException);
    expect(
        () => TaskGraphNode.fromProjection({
              ...projection,
              'dependencies': ['b', 'b']
            }),
        throwsFormatException);
  });
  test(
      'tombstones leave blockers and restoring a node checks the complete graph',
      () {
    final graph = TaskGraph([
      node('a', dependencies: ['b']),
      node('b', dependencies: ['a'], deleted: true)
    ]);
    expect(graph.validate, returnsNormally);
    expect(graph.replacing(node('b', dependencies: ['a'])).validate,
        throwsA(conflict('circular-reference')));
  });
  test('deep task hierarchies are checked iteratively without stack overflow',
      () {
    final graph = TaskGraph([
      for (var index = 0; index < 5000; index++)
        node('task_$index', parent: index == 0 ? null : 'task_${index - 1}')
    ]);
    expect(graph.validate, returnsNormally);
    expect(graph.replacing(node('task_0', parent: 'task_4999')).validate,
        throwsA(conflict('circular-reference')));
  });
}
