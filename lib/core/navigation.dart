import 'package:flutter/material.dart';

const Duration _kPoNavPushDuration = Duration(milliseconds: 300);
const Duration _kPoNavPopDuration = Duration(milliseconds: 260);

/// 서브 화면으로 들어갈 때 미세 슬라이드 + 페이드.
Route<T> poSmoothPushRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: page.runtimeType.toString()),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: _kPoNavPushDuration,
    reverseTransitionDuration: _kPoNavPopDuration,
    opaque: true,
    barrierDismissible: false,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 로그인 직후 등 전체 교체: 페이드만 (자연스러운 홈 진입).
Route<T> poFadeReplaceRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: page.runtimeType.toString()),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    opaque: true,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}
