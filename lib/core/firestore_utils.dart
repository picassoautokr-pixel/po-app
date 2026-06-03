import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Firestore 로드 오류 UX — UI에는 일반 문구만, [debugPrint]에 원본 에러.
// ---------------------------------------------------------------------------
const String poFirestoreLoadErrorTitle = '데이터를 불러오는 중 문제가 발생했습니다.';
const String poFirestoreLoadErrorSubtitle = '잠시 후 다시 시도해주세요.';

bool poFirestoreErrorIsFailedPrecondition(Object? e) {
  if (e is FirebaseException) {
    return e.code == 'failed-precondition';
  }
  final s = e?.toString().toLowerCase() ?? '';
  return s.contains('failed-precondition');
}

void poDebugFirestoreError(String contextTag, Object? error,
    [StackTrace? stackTrace]) {
  debugPrint('[Firestore][$contextTag] $error');
  if (poFirestoreErrorIsFailedPrecondition(error)) {
    debugPrint(
      '[Firestore][$contextTag] failed-precondition: '
      'Firestore 콘솔에서 복합 색인 또는 보안 규칙을 확인하세요.',
    );
  }
  if (stackTrace != null) {
    debugPrint('[Firestore][$contextTag stack] $stackTrace');
  }
}

/// [StreamBuilder]/[FutureBuilder] `hasError` 분기에서 호출합니다.
void poReportFirestoreSnapshotError(String contextTag, Object error) =>
    poDebugFirestoreError(contextTag, error);

Widget poFirestoreUserErrorPlaceholder(
  BuildContext context, {
  double verticalPadding = 26,
  IconData icon = Icons.folder_off_outlined,
}) {
  final tt = Theme.of(context).textTheme;
  return Padding(
    padding: EdgeInsets.fromLTRB(20, verticalPadding, 20, verticalPadding),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 42, color: Colors.grey.shade400),
        const SizedBox(height: 14),
        Text(
          poFirestoreLoadErrorTitle,
          textAlign: TextAlign.center,
          style: tt.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.black87,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          poFirestoreLoadErrorSubtitle,
          textAlign: TextAlign.center,
          style: tt.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
      ],
    ),
  );
}

/// 짧은 로딩 인디케이터를 보여주면서 [action]을 실행합니다.
Future<void> runWithBriefLoading(
  BuildContext context,
  Future<void> Function() action, {
  String message = '처리 중...',
}) async {
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    ),
  );
  try {
    await action();
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}
