import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static const String placeholder = 'REPLACE_WITH_FIREBASE_VALUE';

  static bool get isConfigured => currentPlatform.apiKey != placeholder;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB4hkGyEFQkTdsu7Pe8JM6-keICtEs0orY',
    appId: '1:1077713975334:web:47731ec1b2adaf35e80ee7',
    messagingSenderId: '1077713975334',
    projectId: 'assistummah',
    authDomain: 'assistummah.firebaseapp.com',
    storageBucket: 'assistummah.firebasestorage.app',
    measurementId: 'G-0FGQZE1QG2',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDhy-YaDgK3QBqMAC-5PtOCtxDTQaHUlJ8',
    appId: '1:1077713975334:android:b93df4d24c8a1356e80ee7',
    messagingSenderId: '1077713975334',
    projectId: 'assistummah',
    storageBucket: 'assistummah.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDwdnPISSxCGYw-Gm7FYmLeNrcr7eAoVC4',
    appId: '1:1077713975334:ios:f367f1336f5c5acae80ee7',
    messagingSenderId: '1077713975334',
    projectId: 'assistummah',
    storageBucket: 'assistummah.firebasestorage.app',
    iosBundleId: 'com.rakindotcom.ummahassist',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: placeholder,
    appId: placeholder,
    messagingSenderId: placeholder,
    projectId: 'assistummah',
    storageBucket: 'assistummah.firebasestorage.app',
    iosBundleId: 'com.rakindotcom.ummahassist',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: placeholder,
    appId: placeholder,
    messagingSenderId: placeholder,
    projectId: 'assistummah',
    authDomain: 'assistummah.firebaseapp.com',
    storageBucket: 'assistummah.firebasestorage.app',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: placeholder,
    appId: placeholder,
    messagingSenderId: placeholder,
    projectId: 'assistummah',
    authDomain: 'assistummah.firebaseapp.com',
    storageBucket: 'assistummah.firebasestorage.app',
  );
}
