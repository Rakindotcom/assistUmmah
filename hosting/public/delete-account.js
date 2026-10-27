import { initializeApp } from 'https://www.gstatic.com/firebasejs/13.1.0/firebase-app.js';
import {
  getAuth, inMemoryPersistence, setPersistence, signInWithEmailAndPassword,
  signInWithPopup, GoogleAuthProvider, signOut, sendPasswordResetEmail,
  getAdditionalUserInfo, deleteUser, connectAuthEmulator,
} from 'https://www.gstatic.com/firebasejs/13.1.0/firebase-auth.js';
import { getFirestore, doc, collection, query, where, limit, getDocsFromServer, writeBatch, runTransaction, connectFirestoreEmulator } from 'https://www.gstatic.com/firebasejs/13.1.0/firebase-firestore.js';
import { executeDeletion } from './deletion-plan.mjs';
import { firebaseConfig } from './firebase-config.js';

const byId = id => document.getElementById(id);
const status = message => { byId('status').textContent = message; };
let busy = false;
let auth;
let db;
let plan;
function setBusy(value) {
  busy = value;
  document.querySelectorAll('button,input').forEach(element => { element.disabled = value; });
  byId('delete').disabled = value || !byId('confirm').checked;
}
function showAccount(user) {
  byId('login').hidden = !!user;
  byId('confirmation').hidden = !user;
  byId('identity').textContent = user ? `অ্যাকাউন্ট: ${user.email ?? 'Google অ্যাকাউন্ট'}` : '';
  byId('confirm').checked = false;
  byId('delete').disabled = true;
  byId('password').value = '';
}
function describe(error) {
  if (['auth/invalid-credential','auth/wrong-password','auth/user-not-found'].includes(error.code)) return 'ইমেইল অথবা পাসওয়ার্ড সঠিক নয়।';
  if (['auth/popup-closed-by-user','auth/cancelled-popup-request'].includes(error.code)) return 'প্রবেশ বাতিল করা হয়েছে।';
  if (error.code === 'auth/popup-blocked') return 'ব্রাউজারে পপআপের অনুমতি দিয়ে আবার চেষ্টা করুন।';
  if (['auth/too-many-requests','resource-exhausted'].includes(error.code)) return 'অনেকবার চেষ্টা করা হয়েছে। কিছুক্ষণ পর আবার চেষ্টা করুন।';
  if (error.code === 'auth/requires-recent-login') return 'নিরাপত্তার জন্য আবার প্রবেশ করে অনুরোধ করুন।';
  if (['permission-denied','auth/user-disabled'].includes(error.code)) return 'মুছে ফেলা শেষ করা যায়নি। আবার প্রবেশ করে চেষ্টা করুন।';
  return 'মুছে ফেলা শেষ হয়নি। সংযোগ পরীক্ষা করে আবার চেষ্টা করুন। আগের ধাপগুলো আবার নিরাপদে চলবে।';
}
async function perform(action) {
  if (busy) return;
  setBusy(true); status('অপেক্ষা করুন…');
  try { await action(); } catch (error) { status(describe(error)); }
  finally { setBusy(false); }
}
byId('login-form').addEventListener('submit', event => {
  event.preventDefault();
  perform(async () => {
    const result = await signInWithEmailAndPassword(auth, byId('email').value.trim(), byId('password').value);
    showAccount(result.user); status('পরিচয় নিশ্চিত হয়েছে। মুছে ফেলার আগে নিচের বিবরণ পড়ুন।');
  });
});
byId('google-login').addEventListener('click', () => perform(async () => {
  const result = await signInWithPopup(auth, new GoogleAuthProvider());
  if (getAdditionalUserInfo(result)?.isNewUser) {
    // Firebase federated sign-in can create a new identity. Remove that empty
    // identity immediately instead of creating an app profile on this portal.
    await deleteUser(result.user);
    showAccount(null); status('এই Google পরিচয়ে আগে কোনো অ্যাকাউন্ট পাওয়া যায়নি।'); return;
  }
  showAccount(result.user); status('পরিচয় নিশ্চিত হয়েছে। মুছে ফেলার আগে নিচের বিবরণ পড়ুন।');
}));
byId('reset-password').addEventListener('click', () => perform(async () => {
  if (!byId('email').validity.valid || !byId('email').value.trim()) {
    status('প্রথমে অ্যাকাউন্টের ইমেইল লিখুন।'); byId('email').focus(); return;
  }
  await sendPasswordResetEmail(auth, byId('email').value.trim());
  status('এই ইমেইলে অ্যাকাউন্ট থাকলে পাসওয়ার্ড রিসেটের নির্দেশনা পাঠানো হবে।');
}));
byId('confirm').addEventListener('change', () => { byId('delete').disabled = busy || !byId('confirm').checked; });
byId('logout').addEventListener('click', () => perform(async () => {
  await signOut(auth); showAccount(null); status('অন্য অ্যাকাউন্ট দিয়ে প্রবেশ করুন।');
}));
byId('delete').addEventListener('click', () => perform(async () => {
  if (!byId('confirm').checked || !auth.currentUser) return;
  await auth.currentUser.getIdToken(true);
  const user = auth.currentUser;
  async function drain(source) {
    while (true) {
      const snapshot = await getDocsFromServer(query(source, limit(200)));
      if (snapshot.empty) return;
      const batch = writeBatch(db);
      snapshot.docs.forEach(record => batch.delete(record.ref));
      await batch.commit();
    }
  }
  await executeDeletion(plan, {
    uid: user.uid,
    recordRequest: () => runTransaction(db, async transaction => {
      const marker = doc(db, 'accountDeletions', user.uid);
      if (!(await transaction.get(marker)).exists()) transaction.set(marker, {});
    }),
    deleteCollection: path => drain(collection(db, path)),
    deleteActivities: (name, ownerField, uid) => drain(query(collection(db, name), where(ownerField, '==', uid))),
    deleteDocuments: async paths => {
      const batch = writeBatch(db);
      paths.forEach(path => batch.delete(doc(db, path)));
      await batch.commit();
    },
    deleteIdentity: () => deleteUser(user),
  });
  try { await signOut(auth); } catch (_) { /* Auth deletion already completed */ }
  byId('confirmation').hidden = true; byId('login').hidden = true;
  byId('receipt').hidden = false; byId('receipt').setAttribute('tabindex','-1');
  byId('receipt').focus(); status('অ্যাকাউন্ট ও সংশ্লিষ্ট তথ্য মুছে ফেলা হয়েছে।');
}));
try {
  // Emulator routing is available only on loopback hosts for release verification.
  const emulator = ['localhost','127.0.0.1'].includes(location.hostname) &&
    new URLSearchParams(location.search).get('emulator') === '1';
  const app = initializeApp(emulator ? {
    ...firebaseConfig, projectId: 'demo-ummah', apiKey: 'demo-key', authDomain: 'localhost',
  } : firebaseConfig);
  auth = getAuth(app);
  if (emulator) connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  await setPersistence(auth, inMemoryPersistence);
  db = getFirestore(app);
  if (emulator) connectFirestoreEmulator(db, '127.0.0.1', 8787);
  const response = await fetch('/account-data-paths.json');
  if (!response.ok) throw new Error('Account data inventory unavailable');
  plan = await response.json();
  showAccount(null); status('শুধু আপনার বিদ্যমান অ্যাকাউন্ট দিয়ে প্রবেশ করুন।');
} catch (_) { status('নিরাপদ ফর্ম চালু করা যায়নি। পৃষ্ঠাটি আবার খুলুন।'); }
