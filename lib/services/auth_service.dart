import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/navigation.dart';

/// Google 계정으로 Firebase 인증 후 성공 시에만 [MainShell]로 이동합니다.
///
/// 이전 세션 토큰이 남아 `access_token audience is not for this project` 가 나는 경우를
/// 줄이기 위해 매번 [GoogleSignIn.signOut] 후 [GoogleSignIn.disconnect]를 시도합니다.
///
/// [destinationBuilder]: 로그인 성공 후 이동할 위젯 빌더.
/// main.dart 의 MainShell 순환 참조를 피하기 위해 콜백으로 주입합니다.
Future<void> signInWithGoogle(
  BuildContext context, {
  required Widget Function() destinationBuilder,
}) async {
  final GoogleSignIn googleSignIn = GoogleSignIn();
  await googleSignIn.signOut();
  try {
    await googleSignIn.disconnect();
  } catch (e, st) {
    // 연결 해제 실패는 무시해도 되는 경우가 많음.
    // ignore: avoid_print
    print('GoogleSignIn.disconnect: $e\n$st');
  }
  try {
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 취소되었습니다.')),
      );
      return;
    }
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);
    if (!context.mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // ignore: avoid_print
      print('uid: ${user.uid}');
      // ignore: avoid_print
      print('email: ${user.email}');
      // ignore: avoid_print
      print('displayName: ${user.displayName}');
      // ignore: avoid_print
      print('photoURL: ${user.photoURL}');
    }
    Navigator.of(context).pushReplacement(
      poFadeReplaceRoute<void>(destinationBuilder()),
    );
  } on PlatformException catch (e, st) {
    if (e.code == GoogleSignIn.kSignInCanceledError) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 취소되었습니다.')),
      );
      return;
    }
    // ignore: avoid_print
    print('$e\n$st');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  } catch (e, st) {
    // ignore: avoid_print
    print('$e\n$st');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}
