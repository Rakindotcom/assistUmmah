// Shared path inventory is generated from the same JSON bundled in the app.
// Adapters provide Firebase SDK operations; identity is always removed last.
export async function executeDeletion(plan, operations) {
  const { uid } = operations;
  if (!uid || uid.includes('/')) throw new Error('Invalid account identifier');
  await operations.recordRequest();
  for (const [parent, child] of Object.entries(plan.subcollections)) {
    await operations.deleteCollection(`${parent}/${uid}/${child}`);
  }
  await operations.deleteActivities(plan.activity.collection, plan.activity.ownerField, uid);
  await operations.deleteDocuments(plan.documents.map(collection => `${collection}/${uid}`));
  await operations.deleteIdentity();
}
