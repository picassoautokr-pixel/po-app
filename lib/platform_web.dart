// platform_web.dart
// 웹(Flutter Web) 전용 stub.
// dart:io, flutter_image_compress, path_provider, share_plus 없이
// 동일한 함수 시그니처를 제공합니다.
//
// ignore_for_file: avoid_web_libraries_in_flutter

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

// XFile은 image_picker에서 제공하므로 웹에서도 사용 가능

// ── 이미지 압축 ───────────────────────────────────────────────────────────────

/// 웹에서는 압축 미지원 - XFile을 그대로 반환 (null 반환 시 원본 사용).
Future<dynamic> platformCompressImage(
  XFile xFile, {
  int quality = 65,
  int maxSide = 1600,
}) async {
  // 웹에서는 File 객체 없음 - null 반환으로 원본 바이트 업로드 유도
  return null;
}

/// 웹에서는 임시 디렉터리 없음.
Future<String> platformGetTempDirPath() async => '';

/// 웹에서는 임시 파일 경로 없음.
Future<String> platformGetTempFilePath(String filename) async => '';

/// 웹에서는 파일 시스템 없음 - 항상 false.
bool platformFileExists(String path) => false;

/// 웹에서는 파일 삭제 불필요.
void platformDeleteFile(String path) {}

/// 웹에서는 파일 바이트 읽기 불가 - null 반환.
Future<List<int>?> platformReadFileBytes(String path) async => null;

/// 웹에서는 파일 바이트 쓰기 불가.
Future<void> platformWriteFileBytes(String path, List<int> bytes) async {}

/// 웹에서는 putFile 대신 putData 사용.
/// XFile 바이트를 읽어 putData로 업로드.
UploadTask platformPutFile(
  Reference ref,
  String filePath, {
  String contentType = 'image/jpeg',
}) {
  // 웹에서는 filePath가 없으므로 빈 데이터로 업로드 (실제로는 호출되지 않아야 함)
  // 웹 업로드는 uploadXFileToStorageRef() 사용 권장
  return ref.putData(
    const [],
    SettableMetadata(contentType: contentType),
  );
}

/// 웹에서 텍스트 공유: 클립보드에 복사.
Future<void> platformShareText(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

/// 웹에서 XFile 목록 공유: URL을 클립보드에 복사.
Future<void> platformShareXFiles(List<XFile> files, {String? text}) async {
  final content = [
    if (text != null && text.isNotEmpty) text,
    ...files.map((f) => f.name),
  ].join('\n');
  if (content.isNotEmpty) {
    await Clipboard.setData(ClipboardData(text: content));
  }
}

/// 웹에서 이미지 다운로드: XFile로 변환 불가 - null 반환.
Future<XFile?> platformDownloadImageToTemp(
  String imageUrl,
  int serial,
) async {
  // 웹에서는 임시 파일 저장 불가
  // 이미지 URL을 직접 사용하는 방식으로 대체
  return null;
}

/// 웹에서는 dart:io File 없음 - 호출되어서는 안 됨 (kIsWeb 분기로 보호).
/// 컴파일 오류 방지를 위한 stub.
dynamic platformBuildFile(String path) {
  throw UnsupportedError('platformBuildFile은 웹에서 사용할 수 없습니다.');
}
