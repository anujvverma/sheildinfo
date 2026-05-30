import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAajCq0Feln9eaq6DsJP1kHRY-kIQ-FVvc',
    authDomain: 'shieldinfo-48a33.firebaseapp.com',
    projectId: 'shieldinfo-48a33',
    storageBucket: 'shieldinfo-48a33.firebasestorage.app',
    messagingSenderId: '341906326679',
    appId: '1:341906326679:web:36599982c558f5ffefd5d2',
    measurementId: 'G-HEXV37MJR8',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAajCq0Feln9eaq6DsJP1kHRY-kIQ-FVvc',
    appId: '1:341906326679:android:shieldinfo',
    messagingSenderId: '341906326679',
    projectId: 'shieldinfo-48a33',
    storageBucket: 'shieldinfo-48a33.firebasestorage.app',
  );
}
