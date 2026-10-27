import test, { after } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { initializeApp as initializeAdmin, deleteApp as deleteAdmin } from 'firebase-admin/app';
import { getAuth as adminAuth } from 'firebase-admin/auth';
import { getFirestore as adminFirestore } from 'firebase-admin/firestore';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, connectAuthEmulator, signInWithEmailAndPassword, deleteUser } from 'firebase/auth';
import { getFirestore, connectFirestoreEmulator, doc, collection, query, where, limit,
  getDocFromServer, getDocsFromServer, setDoc, deleteDoc, writeBatch, runTransaction, terminate } from 'firebase/firestore';
import { executeDeletion } from '../../hosting/public/deletion-plan.mjs';

assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Local Firestore emulator required');
assert.ok(process.env.FIREBASE_AUTH_EMULATOR_HOST, 'Local Auth emulator required');
assert.match(process.env.GCLOUD_PROJECT ?? 'demo-ummah', /^demo-/, 'Production tests are forbidden');
const plan = JSON.parse(await readFile(new URL('../../assets/legal/account-data-paths.json', import.meta.url)));
const projectId = 'demo-ummah';
const admin = initializeAdmin({ projectId }, 'spark-tests');
const db = adminFirestore(admin), identities = adminAuth(admin);
const prefix = `spark-${Date.now()}`;
const clients = [];
after(async () => {
  for (const client of clients) { await terminate(client.db); await deleteApp(client.app); }
  await db.terminate(); await deleteAdmin(admin);
});

async function client(uid, create = true) {
  const email = `${uid}@example.test`, password = 'Synthetic-only-42';
  if (create) await identities.createUser({ uid, email, password });
  const app = initializeApp({ projectId, apiKey: 'demo-key', authDomain: 'localhost' }, uid);
  const auth = getAuth(app); connectAuthEmulator(auth, `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`, { disableWarnings: true });
  const store = getFirestore(app);
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  connectFirestoreEmulator(store, host, Number(port));
  await signInWithEmailAndPassword(auth, email, password);
  const value = { app, auth, db: store, uid }; clients.push(value); return value;
}
async function seed(uid, count = 1) {
  for (const parent of plan.documents) await db.doc(`${parent}/${uid}`).set({ synthetic: true });
  for (const [parent, child] of Object.entries(plan.subcollections)) {
    const batch = db.batch();
    for (let i = 0; i < count; i++) {
      const date = new Date(Date.UTC(2025,0,1+i)).toISOString().slice(0,10);
      batch.set(db.doc(`${parent}/${uid}/${child}/${date}`), { synthetic: true });
    }
    await batch.commit();
    await db.doc(`${parent}/${uid}`).delete(); // orphaned parent must not hide records
  }
  await db.doc(`userActivities/${uid}`).set({ userId: uid });
}
function operations(owner) {
  const store = owner.db;
  async function drain(source) {
    while (true) {
      const snapshot = await getDocsFromServer(query(source, limit(200)));
      if (snapshot.empty) return;
      const batch = writeBatch(store); snapshot.docs.forEach(record => batch.delete(record.ref));
      await batch.commit();
    }
  }
  return {
    uid: owner.uid,
    recordRequest: () => runTransaction(store, async transaction => {
      const marker = doc(store, 'accountDeletions', owner.uid);
      if (!(await transaction.get(marker)).exists()) transaction.set(marker, {});
    }),
    deleteCollection: path => drain(collection(store,path)),
    deleteActivities: (name, field, uid) => drain(query(collection(store,name),where(field,'==',uid))),
    deleteDocuments: async paths => {
      const batch = writeBatch(store); paths.forEach(path => batch.delete(doc(store,path))); await batch.commit();
    },
    deleteIdentity: () => deleteUser(owner.auth.currentUser),
  };
}

test('Spark client deletes its own nested data and identity, preserving another account', async () => {
  const owner = await client(`${prefix}-owner`), other = `${prefix}-other`;
  await seed(owner.uid); await seed(other); await identities.createUser({uid: other});
  await executeDeletion(plan,operations(owner));
  for (const parent of plan.documents) assert.equal((await db.doc(`${parent}/${owner.uid}`).get()).exists,false);
  for (const [parent, child] of Object.entries(plan.subcollections)) {
    assert.equal((await db.collection(`${parent}/${owner.uid}/${child}`).get()).empty,true);
    assert.equal((await db.collection(`${parent}/${other}/${child}`).get()).size,1);
  }
  await assert.rejects(identities.getUser(owner.uid),{code:'auth/user-not-found'});
  assert.equal((await identities.getUser(other)).uid,other);
  assert.equal((await db.doc(`userActivities/${owner.uid}`).get()).exists,false);
  assert.deepEqual((await db.doc(`accountDeletions/${owner.uid}`).get()).data(),{});
});

test('interrupted deletion keeps identity, blocks new writes, and resumes to completion', async () => {
  const owner = await client(`${prefix}-retry`); await seed(owner.uid);
  const actions = operations(owner); const real = actions.deleteCollection;
  actions.deleteCollection = async path => { if (path.startsWith('userGrowth')) throw new Error('Injected disconnect'); return real(path); };
  await assert.rejects(executeDeletion(plan,actions),/Injected disconnect/);
  assert.equal((await identities.getUser(owner.uid)).disabled,false);
  await assert.rejects(setDoc(doc(owner.db,'users',owner.uid),{newData:true}),{code:'permission-denied'});
  await executeDeletion(plan,operations(owner));
  await assert.rejects(identities.getUser(owner.uid),{code:'auth/user-not-found'});
});

test('more than one batch of daily records is fully removed', async () => {
  const owner = await client(`${prefix}-batches`); await seed(owner.uid,205);
  await executeDeletion(plan,operations(owner));
  for (const [parent, child] of Object.entries(plan.subcollections)) {
    assert.equal((await db.collection(`${parent}/${owner.uid}/${child}`).get()).empty,true);
  }
});

test('cross-user reads, writes, deletes and marker requests are denied', async () => {
  const owner = await client(`${prefix}-isolation`), victim = `${prefix}-victim`;
  await seed(victim);
  const paths=[...plan.documents.map(parent=>`${parent}/${victim}`),
    ...Object.entries(plan.subcollections).map(([p,c])=>`${p}/${victim}/${c}/2025-01-01`)];
  for(const path of paths){
    await assert.rejects(getDocFromServer(doc(owner.db,path)),{code:'permission-denied'});
    await assert.rejects(setDoc(doc(owner.db,path),{overwrite:true}),{code:'permission-denied'});
    await assert.rejects(deleteDoc(doc(owner.db,path)),{code:'permission-denied'});
  }
  await assert.rejects(setDoc(doc(owner.db,'accountDeletions',victim),{}),{code:'permission-denied'});
});

test('empty markers cannot be forged with fields, overwritten or removed', async () => {
  const owner = await client(`${prefix}-marker`);
  const marker=doc(owner.db,'accountDeletions',owner.uid);
  await assert.rejects(setDoc(marker,{uid:'someone-else'}),{code:'permission-denied'});
  await operations(owner).recordRequest();
  await operations(owner).recordRequest(); // retry is a read, not an overwrite
  await assert.rejects(setDoc(marker,{}),{code:'permission-denied'});
  await assert.rejects(deleteDoc(marker),{code:'permission-denied'});
});

test('legacy activity is readable only during the owners deletion and cannot be recreated', async () => {
  const owner=await client(`${prefix}-activity`); await seed(owner.uid);
  const source=query(collection(owner.db,'userActivities'),where('userId','==',owner.uid));
  await assert.rejects(getDocsFromServer(source),{code:'permission-denied'});
  await operations(owner).recordRequest();
  assert.equal((await getDocsFromServer(source)).size,1);
  await assert.rejects(setDoc(doc(owner.db,'userActivities','cannot-recreate'),{userId:owner.uid}),{code:'permission-denied'});
});

test('anonymous access and stale-token marker creation are denied', async () => {
  const base=`http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${projectId}/databases/(default)/documents`;
  assert.equal((await fetch(`${base}/users/${prefix}-victim`)).status,403);
  const encode=value=>Buffer.from(JSON.stringify(value)).toString('base64url');
  const token=[encode({alg:'none',typ:'JWT'}),encode({aud:projectId,iss:`https://securetoken.google.com/${projectId}`,sub:`${prefix}-stale`,user_id:`${prefix}-stale`,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+3600,auth_time:Math.floor(Date.now()/1000)-600,firebase:{sign_in_provider:'password'}}),''].join('.');
  const response=await fetch(`${base}/accountDeletions/${prefix}-stale`,{method:'PATCH',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({fields:{}})});
  assert.equal(response.status,403);
});
