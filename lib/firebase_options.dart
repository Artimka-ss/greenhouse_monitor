import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;

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
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions не підтримує цю платформу.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAQ3S9tTbIhFoI3dyIFJ4tW86Hoge6fjpo',
    authDomain: 'mobileapppindus.firebaseapp.com',
    databaseURL: 'https://mobileapppindus-default-rtdb.europe-west1.firebasedatabase.app',
    projectId: 'mobileapppindus',
    storageBucket: 'mobileapppindus.firebasestorage.app',
    messagingSenderId: '976737478200',
    appId: '1:976737478200:web:bb197650a8e35cc622e8cd',
    measurementId: 'G-WQK8YBY02W',
  );

  static const FirebaseOptions android = web; // 👈 якщо ти не маєш окремих параметрів
  static const FirebaseOptions ios = web;     // 👈 можеш копіювати ті самі
}
