// Sample records only for the dedicated review identity created by our helper.
// Uses that account's ordinary client permissions, never an Admin credential.
const fs = require('node:fs');
const path = require('node:path');
const {createRequire} = require('node:module');
const root = path.resolve(__dirname, '..');
const sdk = createRequire(path.join(root, 'test/firebase/package.json'));
const {initializeApp, deleteApp} = sdk('firebase/app');
const {getAuth, signInWithEmailAndPassword, signOut} = sdk('firebase/auth');
const {getFirestore, doc, getDocFromServer, writeBatch} = sdk('firebase/firestore');

async function main() {
  const credentials = JSON.parse(fs.readFileSync(path.join(root, '.local/play-reviewer-credentials.json')));
  const config = JSON.parse(fs.readFileSync(path.join(root, 'android/app/google-services.json')));
  if (config.project_info.project_id !== 'assistummah') throw new Error('Unexpected project');
  const client = config.client.find(item => item.client_info.android_client_info.package_name === 'com.rakindotcom.ummah_assist');
  const app = initializeApp({projectId: 'assistummah', apiKey: client.api_key[0].current_key}, 'review-history');
  try {
    const auth = getAuth(app);
    const result = await signInWithEmailAndPassword(auth, credentials.email, credentials.password);
    if (result.user.uid !== credentials.uid) throw new Error('Unexpected identity');
    const db = getFirestore(app);
    const uid = result.user.uid;
    const profile = await getDocFromServer(doc(db, 'users', uid));
    if (profile.data()?.displayName !== 'পর্যালোচনার নমুনা অ্যাকাউন্ট') {
      throw new Error('Refusing to seed an account without the exact review fixture identity');
    }
    const formatDay = new Intl.DateTimeFormat('en-CA', {timeZone: 'Asia/Dhaka', year: 'numeric', month: '2-digit', day: '2-digit'});
    const goal = {unit: 'pages', target: 5};
    const goals = [
      {id: 'subhanallah', name: 'সুবহানাল্লাহ', target: 33},
      {id: 'alhamdulillah', name: 'আলহামদুলিল্লাহ', target: 33},
      {id: 'allahu_akbar', name: 'আল্লাহু আকবার', target: 34},
    ];
    const batch = writeBatch(db);
    batch.set(doc(db, 'userPreferences', uid), {quranGoal: goal, dhikrGoals: goals}, {merge: true});
    for (let index = 0; index < 7; index++) {
      const date = formatDay.format(new Date(Date.now() - index * 86400000));
      batch.set(doc(db, 'userPrayers', uid, 'dailyPrayers', date), {
        date,
        prayers: Object.fromEntries(['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'].map((key, number) => {
          const prayed = index > 0 || number < 2;
          return [key, {state: prayed ? 'prayed' : 'unlogged', prayed, jamat: prayed && number < 2}];
        })),
      });
      batch.set(doc(db, 'userQuran', uid, 'dailyReading', date), {
        date, goal, minutes: 12 + index, pages: index === 0 ? 3 : 5,
        lastRead: 'সূরা আল-বাকারা • আয়াত ২০',
      });
      batch.set(doc(db, 'userDhikr', uid, 'dailyDhikr', date), {
        date, goals, counts: {subhanallah: 33, alhamdulillah: index === 0 ? 20 : 33, allahu_akbar: index === 0 ? 14 : 34},
      });
    }
    await batch.commit();
    await signOut(auth);
    console.log('Seven days of fabricated prayer, Quran and dhikr records seeded only for the dedicated review identity.');
  } finally {
    await deleteApp(app);
  }
}
main().catch(error => {console.error(error.code || error.message); process.exitCode = 1;});
