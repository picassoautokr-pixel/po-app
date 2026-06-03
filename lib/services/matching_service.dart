import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/collaboration_matching_candidate.dart';
import '../region_normalize.dart';

// ─── 내부 헬퍼 ────────────────────────────────────────────────────────────────

String _matchingFieldStr(dynamic v) => v is String ? v.trim() : '';

String matchingUserDisplayName(Map<String, dynamic> d) {
  for (final key in <String>[
    'displayName',
    'appDisplayName',
    'nickname',
    'storeName',
    'businessName',
  ]) {
    final s = _matchingFieldStr(d[key]);
    if (s.isNotEmpty) return s;
  }
  return '이름 미등록 업체';
}

String matchingUserRegionsLine(Map<String, dynamic> d) {
  final po = PoRegionFields.fromUserMap(d);
  if (po.regionFull.isNotEmpty) return po.regionFull;
  final rf = _matchingFieldStr(d['regionFull']);
  if (rf.isNotEmpty) return rf;
  final single = _matchingFieldStr(d['region']);
  if (single.isNotEmpty) return single;
  final raw = d['regions'];
  if (raw is List<dynamic>) {
    final joined = raw
        .whereType<String>()
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .join(', ');
    if (joined.isNotEmpty) return joined;
  }
  return '-';
}

List<String> _matchingUserSearchCategories(Map<String, dynamic> d) {
  final raw = d['searchCategories'];
  if (raw is! List) return [];
  return raw
      .whereType<String>()
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
}

bool _matchingUserAvailable(Map<String, dynamic> d) =>
    d['isAvailable'] == true;

List<String> _matchingRequestServiceCategoryTokens(Map<String, dynamic> r) {
  final raw = r['serviceCategories'];
  if (raw is! List<dynamic>) return [];
  final out = <String>{};
  for (final dynamic e in raw) {
    if (e is String) {
      final t = e.trim();
      if (t.isNotEmpty) out.add(t);
    } else if (e is Map) {
      final m = Map<String, dynamic>.from(e);
      final sub = _matchingFieldStr(m['sub']);
      final main = _matchingFieldStr(m['main']);
      if (sub.isNotEmpty) out.add(sub);
      if (main.isNotEmpty) out.add(main);
      if (main.isNotEmpty && sub.isNotEmpty) {
        out.add('$main · $sub');
      }
    }
  }
  return out.toList(growable: false);
}

List<String> _matchingRequestMainCategoryLabels(Map<String, dynamic> r) {
  final out = <String>[];
  final single = _matchingFieldStr(r['mainCategory']);
  if (single.isNotEmpty) out.add(single);
  final raw = r['mainCategories'];
  if (raw is List<dynamic>) {
    for (final dynamic e in raw) {
      if (e is String && e.trim().isNotEmpty) out.add(e.trim());
    }
  }
  return out;
}

List<String> _matchingUserMainCategoryLabels(Map<String, dynamic> u) {
  final raw = u['mainCategories'];
  if (raw is! List<dynamic>) return [];
  return raw
      .whereType<String>()
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
}

bool _matchingRequestRegionOverlapsUser(
  Map<String, dynamic> user,
  Map<String, dynamic> request,
) {
  final u = PoRegionFields.fromUserMap(user);
  final r = PoRegionFields.fromCollaborationMap(request);
  return poRegionFieldsOverlap(u, r);
}

bool _matchingServiceCategoriesAlign(
  Map<String, dynamic> user,
  Map<String, dynamic> request,
) {
  final reqTok = _matchingRequestServiceCategoryTokens(request);
  if (reqTok.isEmpty) return false;
  final userCats =
      _matchingUserSearchCategories(user).map((String s) => s.trim()).toSet();
  if (userCats.isEmpty) return false;
  return reqTok.any(userCats.contains);
}

bool _matchingMainCategoriesAlign(
  Map<String, dynamic> user,
  Map<String, dynamic> request,
) {
  final reqM = _matchingRequestMainCategoryLabels(request);
  final userM = _matchingUserMainCategoryLabels(user);
  if (reqM.isEmpty || userM.isEmpty) return false;
  final setU = userM.toSet();
  return reqM.any(setU.contains);
}

bool _matchingUserResponseSpeedFast(Map<String, dynamic> user) =>
    _matchingFieldStr(user['responseSpeed']) == '빠름';

bool _matchingUserPriceRangeLowOrMid(Map<String, dynamic> user) {
  final p = _matchingFieldStr(user['priceRange']);
  return p == '저' || p == '중';
}

bool _matchingUserAverageRatingAtLeast8(Map<String, dynamic> user) {
  final v = user['averageRating'];
  if (v is num) return v >= 8;
  return false;
}

// ─── 공개 API ─────────────────────────────────────────────────────────────────

/// 요청([request]) 대비 업체([user]) AI 추천 점수 (높을수록 적합).
int calculateMatchingScore(
  Map<String, dynamic> user,
  Map<String, dynamic> request,
) {
  var score = 0;
  if (_matchingRequestRegionOverlapsUser(user, request)) score += 50;
  if (_matchingServiceCategoriesAlign(user, request)) score += 30;
  if (_matchingMainCategoriesAlign(user, request)) score += 10;
  if (_matchingUserResponseSpeedFast(user)) score += 10;
  if (_matchingUserPriceRangeLowOrMid(user)) score += 10;
  if (_matchingUserAverageRatingAtLeast8(user)) score += 20;
  return score;
}

String matchingFormatAverageRatingDisplay(Map<String, dynamic> user) {
  final v = user['averageRating'];
  if (v is num) return v.toStringAsFixed(1);
  return '—';
}

/// [workType]이 `searchCategories`에 포함된 업체만 가져온 뒤
/// [calculateMatchingScore]로 정렬하여 상위 5개를 반환합니다.
Future<List<CollaborationMatchingCandidate>> fetchCollaborationMatchingCandidates({
  required String workType,
  required String requestId,
}) async {
  final raw = workType.trim();
  if (raw.isEmpty) return [];
  final uid = FirebaseAuth.instance.currentUser?.uid;
  Map<String, dynamic> requestData = <String, dynamic>{};
  final rid = requestId.trim();
  if (rid.isNotEmpty) {
    final rs = await FirebaseFirestore.instance
        .collection('collaborationRequests')
        .doc(rid)
        .get();
    final rd = rs.data();
    if (rd != null) requestData = rd;
  }
  final snap = await FirebaseFirestore.instance
      .collection('users')
      .where('searchCategories', arrayContains: raw)
      .get();
  final filtered = snap.docs
      .where((QueryDocumentSnapshot<Map<String, dynamic>> d) => d.id != uid)
      .map(
        (QueryDocumentSnapshot<Map<String, dynamic>> d) =>
            CollaborationMatchingCandidate(
          doc: d,
          score: calculateMatchingScore(d.data(), requestData),
        ),
      )
      .toList(growable: false);
  filtered.sort((
    CollaborationMatchingCandidate a,
    CollaborationMatchingCandidate b,
  ) {
    if (b.score != a.score) return b.score.compareTo(a.score);
    final da = _matchingUserAvailable(a.doc.data());
    final db = _matchingUserAvailable(b.doc.data());
    if (da != db) return da ? -1 : 1;
    return matchingUserDisplayName(a.doc.data()).toLowerCase().compareTo(
          matchingUserDisplayName(b.doc.data()).toLowerCase(),
        );
  });
  const topN = 5;
  if (filtered.length <= topN) return filtered;
  return filtered.sublist(0, topN);
}
