// core/mobile_utils.dart
// 모바일(Android/iOS) 전용 유틸리티.
// kIsWeb == false 일 때만 import하세요.
//
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// ── 이미지 압축 ───────────────────────────────────────────────────────────────

/// XFile을 JPEG로 압축하여 File 반환. 실패 시 원본 File 반환.
Future<File?> compressChatImageMobile(
  XFile xFile, {
  int quality = 65,
  int maxSide = 1600,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final targetPath = p.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}_compressed.jpg',
    );
    final out = await FlutterImageCompress.compressAndGetFile(
      xFile.path,
      targetPath,
      quality: quality,
      minWidth: maxSide,
      minHeight: maxSide,
    );
    if (out != null) return File(out.path);
    return File(xFile.path);
  } catch (_) {
    return File(xFile.path);
  }
}

/// XFile을 JPEG로 압축하여 Uint8List 반환.
Future<Uint8List?> compressImageToBytesMobile(
  XFile xFile, {
  int quality = 65,
  int maxSide = 1600,
}) async {
  try {
    final result = await FlutterImageCompress.compressWithList(
      await xFile.readAsBytes(),
      quality: quality,
      minWidth: maxSide,
      minHeight: maxSide,
    );
    return result;
  } catch (_) {
    return await xFile.readAsBytes();
  }
}

// ── 임시 파일 ─────────────────────────────────────────────────────────────────

/// 임시 디렉터리 경로 반환.
Future<String> getTempDirPath() async {
  final dir = await getTemporaryDirectory();
  return dir.path;
}

/// 임시 파일 경로 반환.
Future<String> getTempFilePath(String filename) async {
  final dir = await getTemporaryDirectory();
  return p.join(dir.path, filename);
}

// ── 파일 공유 ─────────────────────────────────────────────────────────────────

/// 텍스트 공유.
Future<void> shareTextMobile(String text) async {
  await Share.share(text);
}

/// XFile 목록 공유.
Future<void> shareXFilesMobile(List<XFile> files, {String? text}) async {
  if (files.isEmpty) {
    if (text != null) await Share.share(text);
    return;
  }
  await Share.shareXFiles(files, text: text);
}

/// URL에서 이미지를 다운로드하여 임시 XFile로 반환.
Future<XFile?> downloadImageToTempFile(
  String imageUrl,
  int serial,
) async {
  try {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'chat_img_${serial}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    
    // http 패키지로 다운로드
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(imageUrl));
    final response = await request.close();
    final bytes = await response.fold<List<int>>([], (a, b) => a..addAll(b));
    client.close();
    
    await File(path).writeAsBytes(bytes);
    return XFile(path, mimeType: 'image/jpeg');
  } catch (_) {
    return null;
  }
}
