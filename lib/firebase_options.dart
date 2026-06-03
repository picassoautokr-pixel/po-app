// firebase_options.dart
// flutterfire configure 로 생성된 플랫폼별 Firebase 옵션.
//
// ignore_for_file: lines_longer_than_80_chars

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase.initializeApp 에 전달할 [FirebaseOptions].
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
          'DefaultFirebaseOptions 에 이 플랫폼이 정의되어 있지 않습니다.',
        );
    }
  }

  // ── Web ──────────────────────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAxQS_PATTYsYFCRWXKyqHtWxTAZ0LyTb0',
    appId: '1:237833043397:web:0fde3f8cb454034dfd5fac',
    messagingSenderId: '237833043397',
    projectId: 'po-app-687df',
    authDomain: 'po-app-687df.firebaseapp.com',
    storageBucket: 'po-app-687df.firebasestorage.app',
  );

  // ── Android ───────────────────────────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDXKF03oPmz8qpauPjUDe4-7SGf2Loq8cQ',
    appId: '1:237833043397:android:4ec7041125c01b14fd5fac',
    messagingSenderId: '237833043397',
    projectId: 'po-app-687df',
    storageBucket: 'po-app-687df.firebasestorage.app',
  );

  // ── iOS ───────────────────────────────────────────────────────────────────
  // TODO: iOS google-services.plist 에서 정확한 값을 확인 후 교체하세요.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDXKF03oPmz8qpauPjUDe4-7SGf2Loq8cQ',
    appId: '1:237833043397:ios:0000000000000000fd5fac', // plist에서 교체 필요
    messagingSenderId: '237833043397',
    projectId: 'po-app-687df',
    storageBucket: 'po-app-687df.firebasestorage.app',
    iosBundleId: 'com.example.poApp',
  );

  // ── macOS (iOS 설정 재사용) ────────────────────────────────────────────────
  static const FirebaseOptions macos = ios;

  // ── Windows / Linux (Web 설정 재사용) ────────────────────────────────────
  static const FirebaseOptions windows = web;
  static const FirebaseOptions linux = web;
}
