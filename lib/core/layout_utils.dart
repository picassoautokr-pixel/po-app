import 'package:flutter/material.dart';

double _poMediaBottomInset(BuildContext context) =>
    MediaQuery.of(context).padding.bottom;

/// 전체 화면 스크롤 뷰 하단 여백 (키보드 + 시스템 바 고려).
double poFullScreenScrollBottomPadding(
  BuildContext context, {
  double extra = 0,
}) =>
    _poMediaBottomInset(context) + 24 + extra;

/// 메인 셸 탭 스크롤 뷰 하단 여백.
double poMainShellTabScrollBottomPadding(
  BuildContext context, {
  double extra = 0,
}) =>
    _poMediaBottomInset(context) + kBottomNavigationBarHeight + 16 + extra;

/// 바텀 시트 내부 콘텐츠 하단 여백.
double poBottomSheetContentBottomPadding(
  BuildContext context, {
  double extra = 0,
}) =>
    _poMediaBottomInset(context) + 16 + extra;
