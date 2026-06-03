import 'package:flutter/material.dart';

String _collaborationRequestString(dynamic v) =>
    v is String ? v.trim() : '';

/// 협업 공고 모집 마감일 표시 문자열.
String _collaborationRecruitmentDeadlineLine(Map<String, dynamic>? data) {
  if (data == null) return '미정';
  final type = _collaborationRequestString(data['deadlineType']);
  if (type == 'none' || type.isEmpty) return '미정';
  if (type == 'date') {
    final ts = data['deadlineDate'];
    if (ts == null) return '미정';
    DateTime dt;
    if (ts is DateTime) {
      dt = ts;
    } else {
      try {
        dt = (ts as dynamic).toDate() as DateTime;
      } catch (_) {
        return '미정';
      }
    }
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
  }
  if (type == 'count') {
    final n = data['deadlineCount'];
    if (n == null) return '미정';
    return '$n명 채용 시';
  }
  return '미정';
}

/// 협업 공고 상태 한국어 표시.
String collaborationDisplayStatusKo(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'open':
    case '모집중':
      return '모집중';
    case 'matched':
    case 'in_progress':
      return '진행중';
    case 'completed':
    case 'complete':
    case 'done':
      return '완료';
    case 'closed':
      return '마감';
    case 'cancelled':
      return '취소';
    default:
      return raw.isEmpty ? '모집중' : raw;
  }
}

/// 내가 지원한 공고 — 지원 문서 status 한국어 표시.
String collaborationMyApplicationStatusLabelKo(dynamic statusRaw) {
  final s = _collaborationRequestString(statusRaw).toLowerCase();
  switch (s) {
    case '':
    case 'pending':
      return '검토중';
    case 'accepted':
      return '채택됨';
    case 'in_progress':
      return '진행중';
    case 'completed':
    case 'complete':
    case 'done':
      return '완료';
    case 'rejected':
      return '미채택';
    case 'cancelled':
      return '취소됨';
    default:
      return s;
  }
}

/// 협업 지원 상태 배지 색상.
({Color background, Color foreground}) collaborationApplicationStatusColors(
  String raw,
) {
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'accepted':
      return (
        background: const Color(0xFFE3F2FD),
        foreground: const Color(0xFF1565C0),
      );
    case 'in_progress':
      return (
        background: const Color(0xFFF3E5F5),
        foreground: const Color(0xFF6A1B9A),
      );
    case 'completed':
    case 'complete':
    case 'done':
      return (
        background: const Color(0xFF263238),
        foreground: Colors.white,
      );
    case 'rejected':
    case 'cancelled':
      return (
        background: const Color(0xFFFFEBEE),
        foreground: const Color(0xFFC62828),
      );
    default:
      return (
        background: Colors.grey.shade200,
        foreground: Colors.grey.shade800,
      );
  }
}

bool _collaborationApplicationStatusCompletedLike(String raw) {
  final s = raw.trim().toLowerCase();
  return s == 'completed' || s == 'complete' || s == 'done';
}

/// collaborationRequests/.../applications 의 status 표시용.
String collaborationApplicationStatusKo(String raw) {
  return collaborationMyApplicationStatusLabelKo(raw);
}

/// 파트너 본인 지원 카드·상세 — 지원 문서 상태 표기 통일.
String collaborationMyApplicantCombinedStatusKo(
  Map<String, dynamic>? application,
) {
  if (application == null) return '미등록';
  return collaborationMyApplicationStatusLabelKo(application['status']);
}

/// Firestore 인덱스 안내 문구.
String collaborationApplicationsIndexHint() {
  return 'Firestore 인덱스가 필요할 수 있습니다.\n'
      '콘솔 오류 링크로 복합 인덱스를 생성해 주세요.\n'
      '컬렉션 그룹: applications\n'
      '필드: applicantUid (==), createdAt (desc)';
}

/// 내가 보낸 지원 목록 필터 칩.
enum CollaborationMyOutgoingFilterChip {
  /// pending, accepted, in_progress (기본값)
  inProgress,
  all,
  completed,
  rejected,
}

bool collaborationMyOutgoingRowMatchesChip({
  required Map<String, dynamic> applicationData,
  required CollaborationMyOutgoingFilterChip chip,
}) {
  final appSt =
      _collaborationRequestString(applicationData['status']).toLowerCase();
  bool inProgressPass() {
    if (appSt.isEmpty || appSt == 'pending') return true;
    if (appSt == 'accepted') return true;
    if (appSt == 'in_progress') return true;
    return false;
  }
  switch (chip) {
    case CollaborationMyOutgoingFilterChip.all:
      return true;
    case CollaborationMyOutgoingFilterChip.inProgress:
      return inProgressPass();
    case CollaborationMyOutgoingFilterChip.completed:
      return _collaborationApplicationStatusCompletedLike(appSt);
    case CollaborationMyOutgoingFilterChip.rejected:
      return appSt == 'rejected' || appSt == 'cancelled';
  }
}

/// 지원자·의뢰자 채팅방 문서 ID (`chats` 컬렉션).
String collaborationApplicationChatFirestoreId(
  String requestId,
  String ownerUid,
  String applicantUid,
) {
  final r = requestId.trim();
  final o = ownerUid.trim();
  final a = applicantUid.trim();
  if (r.isEmpty || o.isEmpty || a.isEmpty) return '';
  return '${r}_${o}_$a';
}

List<String> collaborationUserSearchCategoriesList(Map<String, dynamic>? d) {
  if (d == null) return [];
  final raw = d['searchCategories'];
  if (raw is! List) return [];
  return raw
      .map((dynamic e) => e is String ? e.trim() : '')
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
}
