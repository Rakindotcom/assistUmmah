// Creates one dedicated app-review account using ordinary Firebase client APIs.
// No Admin SDK, existing-account mutation, billing change or email-send API.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {createRequire} = require('node:module');
const root = path.resolve(__dirname, '..');
const testRequire = createRequire(path.join(root, 'test/firebase/package.json'));
const {initializeApp, deleteApp} = testRequire('firebase/app');
const {getAuth, createUserWithEmailAndPassword, signInWithEmailAndPassword, signOut, updateProfile} = testRequire('firebase/auth');
const {getFirestore, doc, getDocFromServer, writeBatch} = testRequire('firebase/firestore');

async function main() {
  const credentialPath = path.join(root, '.local/play-reviewer-credentials.json');
  const config = JSON.parse(fs.readFileSync(path.join(root, 'android/app/google-services.json')));
  if (config.project_info.project_id !== 'assistummah') throw new Error('Unexpected Firebase project');
  const client = config.client.find(item => item.client_info.android_client_info.package_name === 'com.rakindotcom.ummah_assist');
  const app = initializeApp({projectId: 'assistummah', apiKey: client.api_key[0].current_key}, 'review-provisioning');
  const auth = getAuth(app);
  try {
    if (fs.existsSync(credentialPath)) {
      const saved = JSON.parse(fs.readFileSync(credentialPath));
      const result = await signInWithEmailAndPassword(auth, saved.email, saved.password);
      if (result.user.uid !== saved.uid) throw new Error('Reviewer identity mismatch');
      console.log('Existing reviewer credentials verified. No records overwritten.');
      await signOut(auth);
      return;
    }
    const email = process.env.REVIEWER_EMAIL;
    if (!email || !email.endsWith('@gmail.com') || !email.includes('+')) {
      throw new Error('Set REVIEWER_EMAIL to an owner-controlled Gmail review alias.');
    }
    const password = crypto.randomBytes(24).toString('base64url');
    // EMAIL_EXISTS aborts; this tool never resets another account's password.
    const {user} = await createUserWithEmailAndPassword(auth, email, password);
    const uid = user.uid;
    fs.mkdirSync(path.dirname(credentialPath), {recursive: true});
    fs.writeFileSync(credentialPath, JSON.stringify({email, password, uid}, null, 2)+'\n', {mode: 0o600, flag: 'wx'});
    await updateProfile(user, {displayName: 'পর্যালোচনার নমুনা অ্যাকাউন্ট'});
    const db = getFirestore(app);
    const existing = await getDocFromServer(doc(db, 'users', uid));
    if (existing.exists()) throw new Error('New reviewer unexpectedly has data; refusing to overwrite it.');
    const day = new Intl.DateTimeFormat('en-CA', {timeZone: 'Asia/Dhaka', year: 'numeric', month: '2-digit', day: '2-digit'}).format(new Date());
    const batch = writeBatch(db);
    batch.set(doc(db, 'users', uid), {email, displayName: 'পর্যালোচনার নমুনা অ্যাকাউন্ট'});
    batch.set(doc(db, 'userSettings', uid), {profile: {name: 'পর্যালোচনার নমুনা অ্যাকাউন্ট'}, notifications: {}, remindersConfigured: false});
    batch.set(doc(db, 'userPreferences', uid), {userType: 'student', quranGoal: {unit: 'minutes', target: 10}});
    batch.set(doc(db, 'userTasks', uid), {dateUpdated: day, todayTasks: {mustDo: [], goodToDo: []}, missedTasks: {mustDo: [], goodToDo: []}, scheduledTasks: [], recurringTasks: [
      {id: 'review-reading', text: 'কুরআন পড়ার জন্য সময় রাখা', section: 'mustDo', repeat: 'daily', startDate: day},
      {id: 'review-plan', text: 'দিনের কাজ গুছিয়ে নেওয়া', section: 'goodToDo', repeat: 'daily', startDate: day},
    ]});
    batch.set(doc(db, 'userContacts', uid), {contacts: {}});
    await batch.commit();
    await signOut(auth);
    await signInWithEmailAndPassword(auth, email, password);
    const verified = await getDocFromServer(doc(db, 'users', uid));
    if (!verified.exists()) throw new Error('Reviewer Firestore read verification failed');
    await signOut(auth);
    console.log('Dedicated reviewer created; password sign-in, own-profile read and sign-out verified.');
    console.log('Private credentials: .local/play-reviewer-credentials.json (excluded from Git and upload packet).');
  } finally {
    await deleteApp(app);
  }
}
main().catch(error => {console.error(error.code || error.message); process.exitCode = 1;});
