// platform_io.dart
// 모바일(Android/iOS) 전용 패키지 import.
// 웹 빌드 시에는 platform_web.dart 가 대신 사용됩니다.
//
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ── 이미지 압축 ───────────────────────────────────────────────────────────────

/// 이미지를 JPEG로 압축하여 File 반환. 실패 시 원본 File 반환.
Future<File?> platformCompressImage(
  XFile xFile, {
  int quality = 65,
  int maxSide = 1600,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final salt = math.Random().nextInt(1 << 20);
    final target = p.join(dir.path, 'img_cmp_${stamp}_$salt.jpg');
    final out = await FlutterImageCompress.compressAndGetFile(
      xFile.path,
      target,
      quality: quality,
      minWidth: maxSide,
      minHeight: maxSide,
      format: CompressFormat.jpeg,
    );
    if (out != null) return File(out.path);
  } catch (_) {}
  try {
    return File(xFile.path);
  } catch (_) {
    return null;
  }
}

/// 임시 디렉터리 경로 반환.
Future<String> platformGetTempDirPath() async {
  final dir = await getTemporaryDirectory();
  return dir.path;
}

/// 임시 파일 경로 반환.
Future<String> platformGetTempFilePath(String filename) async {
  final dir = await getTemporaryDirectory();
  return p.join(dir.path, filename);
}

/// 파일 존재 여부 확인.
bool platformFileExists(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

/// 파일 삭제.
void platformDeleteFile(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {}
}

/// 파일 바이트 읽기.
Future<List<int>?> platformReadFileBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}

/// 파일 바이트 쓰기.
Future<void> platformWriteFileBytes(String path, List<int> bytes) async {
  await File(path).writeAsBytes(bytes, flush: true);
}

/// Firebase Storage에 File 업로드.
UploadTask platformPutFile(
  Reference ref,
  String filePath, {
  String contentType = 'image/jpeg',
}) {
  return ref.putFile(
    File(filePath),
    SettableMetadata(contentType: contentType),
  );
}

/// 텍스트 공유.
Future<void> platformShareText(String text) async {
  await Share.share(text);
}

/// XFile 목록 공유.
Future<void> platformShareXFiles(List<XFile> files, {String? text}) async {
  if (files.isEmpty) {
    if (text != null) await Share.share(text);
    return;
  }
  await Share.shareXFiles(files, text: text);
}

/// dart:io File 객체 생성 (모바일 전용, Image.file에 전달용).
File platformBuildFile(String path) => File(path);

/// URL에서 이미지를 다운로드하여 임시 XFile로 반환.
Future<XFile?> platformDownloadImageToTemp(
  String imageUrl,
  int serial,
) async {
  try {
    final res = await http.get(Uri.parse(imageUrl));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final name = serial == 0
        ? 'chat_image_$ts.jpg'
        : 'chat_image_${ts}_$serial.jpg';
    final path = p.join(dir.path, name);
    await File(path).writeAsBytes(res.bodyBytes, flush: true);
    return XFile(path, mimeType: 'image/jpeg');
  } catch (_) {
    return null;
  }
}
