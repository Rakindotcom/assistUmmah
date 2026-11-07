// Shared path inventory is generated from the same JSON bundled in the app.
// Adapters provide Firebase SDK operations; identity is always removed last.
export async function executeDeletion(plan, operations) {
  const { uid } = operations;
  if (!uid || uid.includes('/')) throw new Error('Invalid account identifier');
  const additional = plan.additionalCollections ?? [];
  if (!Array.isArray(additional) || additional.some(path =>
      typeof path !== 'string' || !/^[a-zA-Z][a-zA-Z0-9]*\/\{uid\}\/[a-zA-Z][a-zA-Z0-9]*$/.test(path))) {
    throw new Error('Invalid account collection path');
  }
  await operations.recordRequest();
  for (const path of additional) {
    await operations.deleteCollection(path.replace('{uid}', uid));
  }
  for (const [parent, child] of Object.entries(plan.subcollections)) {
    await operations.deleteCollection(`${parent}/${uid}/${child}`);
  }
  await operations.deleteActivities(plan.activity.collection, plan.activity.ownerField, uid);
  await operations.deleteDocuments(plan.documents.map(collection => `${collection}/${uid}`));
  await operations.deleteIdentity();
}
