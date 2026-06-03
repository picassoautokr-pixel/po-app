// core/web_utils.dart
// 웹(Flutter Web) 전용 유틸리티.
// kIsWeb == true 일 때만 사용하세요.
//
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';

// ── 이미지 처리 ───────────────────────────────────────────────────────────────

/// 웹에서 XFile을 바이트로 읽기 (압축 없이 원본 반환).
Future<Uint8List?> readImageBytesWeb(XFile xFile) async {
  try {
    return await xFile.readAsBytes();
  } catch (_) {
    return null;
  }
}

// ── 클립보드 ──────────────────────────────────────────────────────────────────

/// 텍스트를 클립보드에 복사합니다.
Future<void> copyToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

// ── 파일 다운로드 ─────────────────────────────────────────────────────────────

/// 웹에서 이미지 URL을 새 탭으로 열어 다운로드 유도.
/// (dart:html 의존성 없이 url_launcher 사용)
Future<void> openImageUrlInNewTab(String url) async {
  // url_launcher 패키지로 처리 (main.dart에서 launchUrl 사용)
}

// ── 공유 ──────────────────────────────────────────────────────────────────────

/// 웹에서 텍스트 공유: 클립보드 복사 후 완료.
Future<void> shareTextWeb(String text) async {
  await copyToClipboard(text);
}

/// 웹에서 이미지 URL 공유: URL을 클립보드에 복사.
Future<void> shareImageUrlsWeb(List<String> urls, {String? text}) async {
  final content = [if (text != null) text, ...urls].join('\n');
  await copyToClipboard(content);
}
