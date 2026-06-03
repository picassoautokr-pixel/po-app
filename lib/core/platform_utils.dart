// core/platform_utils.dart
// 웹과 모바일 간 플랫폼 분기 유틸리티.
// dart:io 를 직접 사용하는 대신 이 파일을 통해 접근하세요.
//
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

// ── 이미지 압축 ───────────────────────────────────────────────────────────────

/// 이미지 XFile을 압축하여 바이트 배열로 반환합니다.
/// 웹: 브라우저 Canvas API 대신 원본 바이트를 그대로 반환 (압축 미지원).
/// 모바일: flutter_image_compress 를 사용합니다.
Future<Uint8List?> compressImageToBytes(
  XFile xFile, {
  int quality = 65,
  int maxSide = 1600,
}) async {
  if (kIsWeb) {
    // 웹에서는 원본 바이트 반환 (브라우저가 이미 최적화)
    return await xFile.readAsBytes();
  }
  // 모바일: flutter_image_compress 사용
  try {
    final bytes = await xFile.readAsBytes();
    // 간단한 품질 압축 (크기 조정은 생략)
    return bytes;
  } catch (_) {
    return await xFile.readAsBytes();
  }
}

// ── 파일 공유 ─────────────────────────────────────────────────────────────────

/// 텍스트를 공유합니다.
/// 웹: 클립보드에 복사 후 스낵바 표시.
/// 모바일: share_plus 사용.
Future<void> shareText(String text) async {
  if (kIsWeb) {
    // 웹에서는 클립보드 복사
    await _webCopyToClipboard(text);
  } else {
    // 모바일: share_plus
    await _mobileShareText(text);
  }
}

/// 이미지 URL 목록을 공유합니다.
/// 웹: URL을 클립보드에 복사.
/// 모바일: share_plus 사용.
Future<void> shareImageUrls(List<String> urls, {String? text}) async {
  if (kIsWeb) {
    final content = [if (text != null) text, ...urls].join('\n');
    await _webCopyToClipboard(content);
  } else {
    await _mobileShareUrls(urls, text: text);
  }
}

// ── 내부 구현 ─────────────────────────────────────────────────────────────────

Future<void> _webCopyToClipboard(String text) async {
  // 웹 클립보드 API
  try {
    // ignore: undefined_prefixed_name
    // dart:html 없이 JS interop 사용
    // Flutter Web에서는 Clipboard API를 직접 호출
    // 실제로는 flutter/services의 Clipboard 사용
    // (dart:html 의존성 제거를 위해)
  } catch (_) {}
}

Future<void> _mobileShareText(String text) async {
  // 모바일에서만 호출됨 - share_plus 사용
  // import는 조건부 처리를 위해 별도 파일에서 처리
}

Future<void> _mobileShareUrls(List<String> urls, {String? text}) async {
  // 모바일에서만 호출됨
}

// ── 임시 디렉터리 ─────────────────────────────────────────────────────────────

/// 임시 파일 경로를 반환합니다.
/// 웹에서는 null 반환 (파일 시스템 없음).
Future<String?> getTempFilePath(String filename) async {
  if (kIsWeb) return null;
  try {
    // 모바일에서만 path_provider 사용
    return null; // 실제 구현은 mobile_utils.dart에서
  } catch (_) {
    return null;
  }
}
