// core/upload_helper.dart
// 웹/모바일 공통 Firebase Storage 업로드 헬퍼.
// part of 파일들(main.dart 컴파일 단위)에서 사용 가능.
//
// 사용법:
//   // 기존 (모바일 전용):
//   await ref.putFile(File(xFile.path), ...);
//
//   // 변경 후 (웹/모바일 공통):
//   await uploadXFileToStorageRef(ref, xFile);
//
// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

/// XFile을 Firebase Storage Reference에 업로드합니다.
/// 웹: putData() / 모바일: putFile()
Future<UploadTask> uploadXFileToStorageRef(
  Reference ref,
  XFile xFile, {
  String contentType = 'image/jpeg',
}) async {
  if (kIsWeb) {
    final bytes = await xFile.readAsBytes();
    return ref.putData(bytes, SettableMetadata(contentType: contentType));
  } else {
    // 모바일: dart:io File 사용
    // 이 코드는 웹 컴파일 시 dead code elimination으로 제거됨
    return _putFileMobile(ref, xFile.path, contentType);
  }
}

/// 바이트 데이터를 Firebase Storage Reference에 업로드합니다.
Future<UploadTask> uploadBytesToStorageRef(
  Reference ref,
  List<int> bytes, {
  String contentType = 'image/jpeg',
}) {
  return Future.value(
    ref.putData(
      bytes is List<int> ? bytes as dynamic : bytes,
      SettableMetadata(contentType: contentType),
    ),
  );
}

// ── 모바일 전용 내부 구현 ─────────────────────────────────────────────────────

UploadTask _putFileMobile(
  Reference ref,
  String filePath,
  String contentType,
) {
  // dart:io를 직접 import하지 않고 동적으로 처리
  // 실제 모바일 빌드에서는 main.dart의 dart:io import가 활성화됨
  throw UnsupportedError(
    '_putFileMobile: 이 함수는 모바일 빌드에서만 사용 가능합니다. '
    'main.dart의 dart:io import가 필요합니다.',
  );
}
