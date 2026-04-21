// Generated values: install Flutter, then from repo root run:
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=careshare-2026 --platforms=android,ios,web,windows,macos,linux
// This overwrites this file and adds native config (e.g. google-services.json).
import "package:firebase_core/firebase_core.dart" show FirebaseOptions;
import "package:flutter/foundation.dart"
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
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
        throw UnsupportedError(
          "DefaultFirebaseOptions are not configured for this platform.",
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC0MOG9Om0FQ9xXVQF3qAzVbuJUsb1Ksrw',
    appId: '1:412022245605:web:c213a1144e5092551b2c0c',
    messagingSenderId: '412022245605',
    projectId: 'careshare-2026',
    authDomain: 'careshare-2026.firebaseapp.com',
    storageBucket: 'careshare-2026.firebasestorage.app',
    measurementId: 'G-N9S0T9YR8Z',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBqg7VA4E-rQbh-FK4V8EdEyPWg3JKppE8',
    appId: '1:412022245605:android:034ea456e4a3a7fa1b2c0c',
    messagingSenderId: '412022245605',
    projectId: 'careshare-2026',
    storageBucket: 'careshare-2026.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDO6zJ_00jvvSorWDsX1qoKgehgN8WEEGA',
    appId: '1:412022245605:ios:1d0e0793cc9fadb11b2c0c',
    messagingSenderId: '412022245605',
    projectId: 'careshare-2026',
    storageBucket: 'careshare-2026.firebasestorage.app',
    iosClientId: '412022245605-7cago1ihja5h2n6l0kai0gflnvsqriao.apps.googleusercontent.com',
    iosBundleId: 'com.careshare.app',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDO6zJ_00jvvSorWDsX1qoKgehgN8WEEGA',
    appId: '1:412022245605:ios:1d0e0793cc9fadb11b2c0c',
    messagingSenderId: '412022245605',
    projectId: 'careshare-2026',
    storageBucket: 'careshare-2026.firebasestorage.app',
    iosClientId: '412022245605-7cago1ihja5h2n6l0kai0gflnvsqriao.apps.googleusercontent.com',
    iosBundleId: 'com.careshare.app',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyC0MOG9Om0FQ9xXVQF3qAzVbuJUsb1Ksrw',
    appId: '1:412022245605:web:58c7ce8fa9d0862c1b2c0c',
    messagingSenderId: '412022245605',
    projectId: 'careshare-2026',
    authDomain: 'careshare-2026.firebaseapp.com',
    storageBucket: 'careshare-2026.firebasestorage.app',
    measurementId: 'G-PH7V9PEKWP',
  );

  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: "REPLACE_ME",
    appId: "1:412022245605:web:0000000000000000000000",
    messagingSenderId: "412022245605",
    projectId: "careshare-2026",
    authDomain: "careshare-2026.firebaseapp.com",
    storageBucket: "careshare-2026.appspot.com",
  );
}