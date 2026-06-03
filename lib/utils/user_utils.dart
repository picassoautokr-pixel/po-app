import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ─── 내부 헬퍼 ────────────────────────────────────────────────────────────────

String _fieldStr(dynamic v) => v is String ? v.trim() : '';

DateTime? _firestoreAsDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

// ─── 공개 API ─────────────────────────────────────────────────────────────────

/// 홈·업체 상세 공통: 카드/상세 헤더용 표시명.
String poHomeUserCardTitle(Map<String, dynamic> d) {
  for (final key in <String>[
    'displayName',
    'businessName',
    'shopName',
    'ownerName',
    'appDisplayName',
    'nickname',
    'storeName',
  ]) {
    final s = _fieldStr(d[key]);
    if (s.isNotEmpty) return s;
  }
  return '이름 미등록 업체';
}

/// 홈·업체 상세 공통: 전화 (storePhone → phoneNumber → businessPhone).
String poUserPrimaryPhone(Map<String, dynamic> d) {
  for (final key in <String>['storePhone', 'phoneNumber', 'businessPhone']) {
    final s = _fieldStr(d[key]);
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// `businessVerificationStatus` 정규화 (없거나 알 수 없으면 unverified).
String poNormalizeBusinessVerificationStatus(dynamic raw) {
  final s = raw is String ? raw.trim().toLowerCase() : '';
  switch (s) {
    case 'pending':
      return 'pending';
    case 'verified':
      return 'verified';
    case 'rejected':
      return 'rejected';
    default:
      return 'unverified';
  }
}

/// 마이페이지 인증 상태 UI 문자열.
String poBusinessVerificationUiState(Map<String, dynamic>? doc) {
  if (doc == null) return 'unverified';
  return poNormalizeBusinessVerificationStatus(
    doc['businessVerificationStatus'],
  );
}

/// 인증 배지 표시 여부.
bool poBusinessVerificationShowVerifiedBadge(Map<String, dynamic>? d) {
  if (d == null) return false;
  return poNormalizeBusinessVerificationStatus(
        d['businessVerificationStatus'],
      ) ==
      'verified';
}

/// 관리자 여부 확인.
bool poIsAdminUser(Map<String, dynamic>? userDoc) =>
    userDoc?['isAdmin'] == true;

/// 인증 업체 배지 칩 위젯.
Widget poVerifiedCompanyBadgeChip({double fontSize = 11}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF1565C0),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.verified_rounded, size: 13, color: Colors.white),
        const SizedBox(width: 4),
        Text(
          '인증업체',
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}

/// 마이페이지 인증 상태 라인 텍스트.
String poBusinessVerificationMyPageLine(String normalized) {
  switch (normalized) {
    case 'verified':
      return '사업자 인증 완료';
    case 'pending':
      return '인증 검토 중';
    case 'rejected':
      return '인증 반려됨';
    default:
      return '사업자 미인증';
  }
}

// ─── 마감 디테일 유틸 ─────────────────────────────────────────────────────────

String finishDetailFieldStr(dynamic v) => v is String ? v.trim() : '';

/// imageUrl이 실제 이미지 URL인지 검사.
bool isValidImageUrl(String url) {
  if (url.isEmpty) return false;
  if (!url.startsWith('http')) return false;
  if (url.contains('console.firebase.google.com')) return false;
  if (url.contains('firestore.googleapis.com')) return false;
  return true;
}

/// Firebase 에러 링크·에러 문자열이 포함된 필드 값을 빈 문자열로 처리.
String safeTextOrEmpty(dynamic v) {
  if (v is! String) return '';
  final s = v.trim();
  if (s.isEmpty) return '';
  if (s.contains('console.firebase.google.com')) return '';
  if (s.startsWith('FirebaseException') ||
      s.startsWith('Error:') ||
      s.startsWith('Exception:') ||
      s.startsWith('[cloud_firestore')) {
    return '';
  }
  return s;
}

String formatFinishDetailCreatedAt(dynamic v) {
  final dt = _firestoreAsDateTime(v);
  if (dt == null) return '-';
  return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

Future<void> confirmDeleteFinishDetail(
  BuildContext context,
  DocumentReference<Map<String, dynamic>> docRef,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('마감 디테일 삭제'),
      content: const Text('이 마감 디테일을 삭제할까요? 저장된 정보가 제거됩니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade700,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('삭제'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await docRef.delete();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('삭제했습니다.')),
    );
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('삭제 실패: $e')),
    );
  }
}

void showFinishDetailImagePreview(BuildContext context, String? rawUrl) {
  final url = finishDetailFieldStr(rawUrl);
  if (url.isEmpty) return;
  showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 44, 0, 0),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const SizedBox(
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '이미지를 불러올 수 없습니다.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
    },
  );
}

int finishDetailCreatedCompare(
  QueryDocumentSnapshot<Map<String, dynamic>> a,
  QueryDocumentSnapshot<Map<String, dynamic>> b,
) {
  final ta = a.data()['createdAt'];
  final tb = b.data()['createdAt'];
  final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
  final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
  return db.compareTo(da);
}

/// 리뷰 평점 항목 키 목록.
const List<String> collaborationReviewScoreKeys = <String>[
  'quality',
  'communication',
  'punctuality',
  'professionalism',
  'price',
];

/// 리뷰 평점 항목 한국어 라벨.
const Map<String, String> collaborationReviewScoreLabelsKo = {
  'quality': '시공 품질',
  'communication': '소통',
  'punctuality': '시간 준수',
  'professionalism': '전문성',
  'price': '가격 만족도',
};

/// 리뷰 문서 ID 생성 규칙.
String collaborationReviewDocId(String reviewerUid, String requestId) {
  final r = reviewerUid.trim();
  final q = requestId.trim();
  if (r.isEmpty || q.isEmpty) return '';
  return '${r}_$q';
}

/// 사용자 평균 평점 재계산 (리뷰 작성/수정 후 호출).
Future<void> collaborationRecomputeUserAverageRating(String targetUid) async {
  final uid = targetUid.trim();
  if (uid.isEmpty) return;
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('reviews')
      .get();
  if (snap.docs.isEmpty) return;
  final keys = collaborationReviewScoreKeys;
  var total = 0.0;
  var count = 0;
  for (final doc in snap.docs) {
    final d = doc.data();
    for (final k in keys) {
      final v = d[k];
      if (v is num) {
        total += v;
        count++;
      }
    }
  }
  if (count == 0) return;
  final avg = total / count;
  await FirebaseFirestore.instance.collection('users').doc(uid).update(
    <String, Object?>{'averageRating': avg},
  );
}
