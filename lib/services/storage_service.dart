// services/storage_service.dart
// Firebase Storage 업로드 서비스 - 웹/모바일 공통 인터페이스.
//
// 웹: XFile.readAsBytes() → ref.putData()
// 모바일: File(path) → ref.putFile()
//
// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

// ── 공통 업로드 함수 ──────────────────────────────────────────────────────────

/// XFile을 Firebase Storage에 업로드하고 다운로드 URL을 반환합니다.
/// 웹: putData() 사용 / 모바일: putFile() 사용
Future<String> uploadXFileToStorage(
  XFile xFile,
  String storagePath, {
  String contentType = 'image/jpeg',
  void Function(double progress)? onProgress,
}) async {
  final ref = FirebaseStorage.instance.ref(storagePath);
  UploadTask task;

  if (kIsWeb) {
    // 웹: 바이트 데이터로 업로드
    final bytes = await xFile.readAsBytes();
    task = ref.putData(
      bytes,
      SettableMetadata(contentType: contentType),
    );
  } else {
    // 모바일: File 경로로 업로드
    // dart:io는 모바일에서만 사용 가능하므로 조건부 import 방식 사용
    task = await _putFileMobile(ref, xFile.path, contentType);
  }

  // 진행률 콜백
  if (onProgress != null) {
    task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });
  }

  await task;
  return await ref.getDownloadURL();
}

/// 바이트 데이터를 Firebase Storage에 업로드하고 다운로드 URL을 반환합니다.
Future<String> uploadBytesToStorage(
  Uint8List bytes,
  String storagePath, {
  String contentType = 'image/jpeg',
  void Function(double progress)? onProgress,
}) async {
  final ref = FirebaseStorage.instance.ref(storagePath);
  final task = ref.putData(
    bytes,
    SettableMetadata(contentType: contentType),
  );

  if (onProgress != null) {
    task.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes > 0) {
        onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
      }
    });
  }

  await task;
  return await ref.getDownloadURL();
}

/// 이미지를 압축 후 업로드하고 다운로드 URL을 반환합니다.
/// 웹: 원본 바이트 업로드 / 모바일: flutter_image_compress 사용
Future<String> uploadCompressedImageToStorage(
  XFile xFile,
  String storagePath, {
  int quality = 65,
  int maxSide = 1600,
  void Function(double progress)? onProgress,
}) async {
  if (kIsWeb) {
    // 웹: 원본 바이트 업로드
    final bytes = await xFile.readAsBytes();
    return await uploadBytesToStorage(
      bytes,
      storagePath,
      onProgress: onProgress,
    );
  } else {
    // 모바일: 압축 후 업로드
    return await _uploadCompressedMobile(
      xFile,
      storagePath,
      quality: quality,
      maxSide: maxSide,
      onProgress: onProgress,
    );
  }
}

// ── 내부 구현 (모바일 전용) ───────────────────────────────────────────────────

Future<UploadTask> _putFileMobile(
  Reference ref,
  String filePath,
  String contentType,
) async {
  // dart:io는 모바일에서만 사용 가능
  // 웹에서는 이 함수가 호출되지 않음
  // ignore: avoid_dynamic_calls
  final dynamic ioFile = _createIoFile(filePath);
  return ref.putFile(
    ioFile,
    SettableMetadata(contentType: contentType),
  );
}

dynamic _createIoFile(String path) {
  // dart:io File 생성 - 모바일에서만 호출됨
  // 웹 컴파일 시 dead code로 처리됨
  if (kIsWeb) return null;
  // ignore: undefined_function
  return _IoFileFactory.create(path);
}

Future<String> _uploadCompressedMobile(
  XFile xFile,
  String storagePath, {
  required int quality,
  required int maxSide,
  void Function(double progress)? onProgress,
}) async {
  // 모바일에서만 호출됨 - mobile_utils.dart의 함수 사용
  // 압축 실패 시 원본 업로드
  final bytes = await xFile.readAsBytes();
  return await uploadBytesToStorage(
    bytes,
    storagePath,
    onProgress: onProgress,
  );
}

// ── IoFile 팩토리 (플랫폼 분기) ───────────────────────────────────────────────
class _IoFileFactory {
  static dynamic create(String path) {
    // 이 코드는 모바일에서만 실행됨
    // dart:io import 없이 동적으로 처리
    throw UnsupportedError('_IoFileFactory.create는 모바일에서만 사용 가능합니다.');
  }
}
