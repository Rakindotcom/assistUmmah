import 'dart:convert';

/// Fixed account-owned paths shared with the public deletion page through JSON.
/// Identity is removed last; any earlier failure leaves a resumable account.
class AccountDeletionPlan {
  AccountDeletionPlan.fromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    documents = (data['documents'] as List).cast<String>();
    subcollections = (data['subcollections'] as Map).cast<String, String>();
    additionalCollections =
        (data['additionalCollections'] as List? ?? []).cast<String>();
    for (final path in additionalCollections) {
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9]*/\{uid\}/[a-zA-Z][a-zA-Z0-9]*$')
          .hasMatch(path)) {
        throw const FormatException('Invalid account collection path.');
      }
    }
    final activity = (data['activity'] as Map).cast<String, String>();
    activityCollection = activity['collection']!;
    activityOwnerField = activity['ownerField']!;
  }

  late final List<String> documents;
  late final Map<String, String> subcollections;
  late final List<String> additionalCollections;
  late final String activityCollection;
  late final String activityOwnerField;

  Future<void> execute({
    required String uid,
    required Future<void> Function() recordRequest,
    required Future<void> Function(String path) deleteCollection,
    required Future<void> Function(
            String collection, String ownerField, String uid)
        deleteActivities,
    required Future<void> Function(List<String> paths) deleteDocuments,
    required Future<void> Function() deleteIdentity,
  }) async {
    if (uid.isEmpty || uid.contains('/')) throw ArgumentError.value(uid, 'uid');
    await recordRequest();
    for (final path in additionalCollections) {
      await deleteCollection(path.replaceAll('{uid}', uid));
    }
    for (final entry in subcollections.entries) {
      await deleteCollection('${entry.key}/$uid/${entry.value}');
    }
    await deleteActivities(activityCollection, activityOwnerField, uid);
    await deleteDocuments(
        documents.map((collection) => '$collection/$uid').toList());
    await deleteIdentity();
  }
}
