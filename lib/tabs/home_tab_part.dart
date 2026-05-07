part of '../main.dart';

Set<String> _inferSubLabelsForMain(String catalogMain, String haystackLower) {
  final out = <String>{};
  for (final sub in ServiceCategoryCatalog.servicesForMain(catalogMain)) {
    if (haystackLower.contains(sub.toLowerCase())) {
      out.add(sub);
    }
  }
  return out;
}

Set<String> _docSubsForMainFilter(
  Map<String, dynamic> d,
  String catalogMain,
) {
  final fromKeys = <String>{};
  final keys = ServiceCategoryCatalog.selectionKeysFromFirestore(
    serviceCategories: d['serviceCategories'],
  );
  for (final k in keys) {
    final parsed = ServiceCategoryCatalog.splitSelectionKey(k);
    if (parsed != null && parsed.main == catalogMain) {
      fromKeys.add(parsed.sub);
    }
  }
  if (fromKeys.isNotEmpty) return fromKeys;

  final rawList = d['serviceCategories'];
  if (rawList is List<dynamic>) {
    final onlyStrings = <String>{};
    for (final e in rawList) {
      if (e is String && e.trim().isNotEmpty) onlyStrings.add(e.trim());
    }
    if (onlyStrings.isNotEmpty) {
      final docMain = _collaborationRequestString(d['mainCategory']);
      final m = catalogMain.trim();
      if (m.isEmpty) return onlyStrings;
      if (docMain.isEmpty) return onlyStrings;
      final a = docMain.toLowerCase();
      final b = m.toLowerCase();
      if (a == b || a.contains(b) || b.contains(a)) return onlyStrings;
    }
  }

  final hay = '${_collaborationRequestString(d['workType'])} '
          '${_collaborationRequestString(d['description'])} '
      .toLowerCase();
  return _inferSubLabelsForMain(catalogMain, hay);
}

bool _userDocRegionMatches(Map<String, dynamic> d, String regionFilter) {
  return poRegionDocMatchesSelectedFilter(
    PoRegionFields.fromUserMap(d),
    regionFilter,
  );
}

bool _mainLabelsLooselyMatch(String docLabel, String selectedMain) {
  final a = docLabel.trim().toLowerCase();
  final b = selectedMain.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return false;
  return a == b || a.contains(b) || b.contains(a);
}

bool _userListContainsAnyMainCat(
  Map<String, dynamic> d,
  Set<String> selectedMains,
) {
  if (selectedMains.isEmpty) return true;
  final raw = d['mainCategories'];
  if (raw is! List<dynamic>) return false;
  for (final e in raw) {
    if (e is! String) continue;
    final s = e.trim();
    if (s.isEmpty) continue;
    for (final m in selectedMains) {
      if (_mainLabelsLooselyMatch(s, m)) return true;
    }
  }
  return false;
}

bool _userSearchCategoriesMatchSubs(Map<String, dynamic> d, Set<String> subs) {
  if (subs.isEmpty) return true;
  final raw = d['searchCategories'];
  if (raw is! List<dynamic>) return false;
  final items = raw
      .whereType<String>()
      .map((String s) => s.trim().toLowerCase())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  for (final sub in subs) {
    final sl = sub.trim().toLowerCase();
    if (sl.isEmpty) continue;
    for (final it in items) {
      if (it.contains(sl) || sl.contains(it)) return true;
    }
  }
  return false;
}

// --- 통합 검색 (업체 · 구인·협업) --------------------------------------------

String _poSearchHayNoSpace(String lowered) =>
    lowered.replaceAll(RegExp(r'\s+'), '');

/// 축약어·동의어 → 확장 목록 (키·값 모두 소문자로 정규화해 사용).
/// 업체·구인·협업 공통 [expandSearchTerms]에서 참조.
const Map<String, List<String>> _poSearchSynonymExpand =
    <String, List<String>>{
  '블박': <String>['블랙박스'],
  '네비': <String>['내비게이션'],
  '썬팅': <String>['틴팅'],
  '광택': <String>['폴리싱'],
  '유리막': <String>['세라믹 코팅'],
  'ppf': <String>['PPF'],
  '랩핑': <String>['랩핑', 'wrap'],
};

/// 단일 검색 토큰을 원문 토큰 + 동의어 목록으로 확장합니다. 모두 소문자·trim.
/// 예: `블박` → `[블박, 블랙박스]`, `네비` → `[네비, 내비게이션]`
List<String> expandSearchTerms(String keyword) {
  final t = keyword.trim().toLowerCase();
  if (t.isEmpty) return <String>[];

  final out = <String>{t};

  final direct = _poSearchSynonymExpand[t];
  if (direct != null) {
    for (final v in direct) {
      final x = v.trim().toLowerCase();
      if (x.isNotEmpty) out.add(x);
    }
  }

  for (final e in _poSearchSynonymExpand.entries) {
    final keyLower = e.key.trim().toLowerCase();
    if (keyLower == t) continue;
    for (final v in e.value) {
      if (v.trim().toLowerCase() == t) {
        out.add(keyLower);
        for (final v2 in e.value) {
          final x = v2.trim().toLowerCase();
          if (x.isNotEmpty) out.add(x);
        }
        break;
      }
    }
  }

  return out.toList(growable: false);
}

class _PoSearchQuery {
  const _PoSearchQuery({required this.rawTrimmed, required this.tokens});

  final String rawTrimmed;
  final List<String> tokens;

  bool get isEmpty => rawTrimmed.isEmpty;
}

_PoSearchQuery _poParseSearchQuery(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const _PoSearchQuery(rawTrimmed: '', tokens: <String>[]);
  }
  final tokens = trimmed
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
  return _PoSearchQuery(rawTrimmed: trimmed, tokens: tokens);
}

bool _poVariantsMatchHay(
  Iterable<String> variantsLower,
  String hayLower,
  String hayNoSpace,
) {
  for (final v in variantsLower) {
    final vl = v.trim().toLowerCase();
    if (vl.isEmpty) continue;
    if (hayLower.contains(vl)) return true;
    final vns = _poSearchHayNoSpace(vl);
    if (vns.isNotEmpty && hayNoSpace.contains(vns)) return true;
  }
  return false;
}

List<String> _poVariantsForToken(String token) =>
    expandSearchTerms(token).map((e) => e.toLowerCase().trim()).where((e) => e.isNotEmpty).toList();

String _userSearchHayCombined(Map<String, dynamic> d) {
  final regLine = _matchingUserRegionsLine(d);
  final po = PoRegionFields.fromUserMap(d);
  final keys = ServiceCategoryCatalog.selectionKeysFromFirestore(
    serviceCategories: d['serviceCategories'],
  );
  final subs = ServiceCategoryCatalog.distinctSubs(keys);
  final mainCats = <String>[];
  final rawMain = d['mainCategories'];
  if (rawMain is List<dynamic>) {
    for (final e in rawMain) {
      if (e is String && e.trim().isNotEmpty) mainCats.add(e.trim());
    }
  }
  final sc = _matchingUserSearchCategories(d);
  return <String>[
    _matchingFieldStr(d['displayName']),
    _matchingFieldStr(d['businessName']),
    _matchingFieldStr(d['shopName']),
    _matchingFieldStr(d['ownerName']),
    _matchingFieldStr(d['region']),
    _matchingFieldStr(d['regionFull']),
    if (regLine != '-') regLine,
    po.regions.join(' '),
    _matchingFieldStr(d['primaryCategory']),
    mainCats.join(' '),
    sc.join(' '),
    subs.join(' '),
    _matchingFieldStr(d['priceRange']),
    _matchingFieldStr(d['responseSpeed']),
    _userRawServiceCategoryStringsForSearch(d),
  ].join(' ').toLowerCase();
}

/// serviceCategories 가 문자열 리스트일 때 등 추가 텍스트.
String _userRawServiceCategoryStringsForSearch(Map<String, dynamic> d) {
  final raw = d['serviceCategories'];
  if (raw is! List<dynamic>) return '';
  final buf = StringBuffer();
  for (final e in raw) {
    if (e is String && e.trim().isNotEmpty) {
      buf.write(' ${e.trim()}');
    } else if (e is Map) {
      final m = Map<String, dynamic>.from(e);
      buf.write(' ${_matchingFieldStr(m['sub'])} ${_matchingFieldStr(m['main'])}');
    }
  }
  return buf.toString();
}

bool _userDocMatchesSearchQuery(Map<String, dynamic> d, _PoSearchQuery q) {
  if (q.isEmpty) return true;
  final hay = _userSearchHayCombined(d);
  final hayNs = _poSearchHayNoSpace(hay);
  for (final token in q.tokens) {
    final vars = _poVariantsForToken(token);
    if (!_poVariantsMatchHay(vars, hay, hayNs)) return false;
  }
  return true;
}

int _userSearchRelevanceScore(Map<String, dynamic> d, _PoSearchQuery q) {
  if (q.isEmpty) return 0;
  var score = 0;
  final dn = _matchingFieldStr(d['displayName']).toLowerCase();
  final sn = _matchingFieldStr(d['shopName']).toLowerCase();
  final bn = _matchingFieldStr(d['businessName']).toLowerCase();
  final pc = _matchingFieldStr(d['primaryCategory']).toLowerCase();
  final scHay = _matchingUserSearchCategories(d).join(' ').toLowerCase();
  final rawMain = d['mainCategories'];
  final mcHay = StringBuffer();
  if (rawMain is List<dynamic>) {
    for (final e in rawMain) {
      if (e is String && e.trim().isNotEmpty) mcHay.write(' ${e.trim()}');
    }
  }
  final mcStr = mcHay.toString().toLowerCase().trim();
  final regLine = _matchingUserRegionsLine(d).toLowerCase();
  final po = PoRegionFields.fromUserMap(d);
  final regHay = <String>[
    _matchingFieldStr(d['region']).toLowerCase(),
    _matchingFieldStr(d['regionFull']).toLowerCase(),
    if (regLine != '-') regLine,
    ...po.regions.map((r) => r.toLowerCase()),
  ].join(' ');

  final keys = ServiceCategoryCatalog.selectionKeysFromFirestore(
    serviceCategories: d['serviceCategories'],
  );
  final subsHay =
      ServiceCategoryCatalog.distinctSubs(keys).join(' ') +
          _userRawServiceCategoryStringsForSearch(d);

  final descHay = <String>[
    _matchingFieldStr(d['ownerName']).toLowerCase(),
    _matchingFieldStr(d['priceRange']).toLowerCase(),
    _matchingFieldStr(d['responseSpeed']).toLowerCase(),
  ].join(' ');

  void addIfMatch(String hayLower, int weight) {
    final hns = _poSearchHayNoSpace(hayLower);
    for (final token in q.tokens) {
      if (_poVariantsMatchHay(_poVariantsForToken(token), hayLower, hns)) {
        score += weight;
        return;
      }
    }
  }

  addIfMatch(dn, 50);
  addIfMatch(sn, 40);
  addIfMatch(bn, 40);
  addIfMatch(pc, 30);
  final searchAndSvc =
      ('$scHay ${subsHay.toLowerCase()}').trim();
  if (searchAndSvc.isNotEmpty) addIfMatch(searchAndSvc, 30);
  if (mcStr.isNotEmpty) addIfMatch(mcStr, 20);
  addIfMatch(regHay, 20);
  addIfMatch(descHay, 10);

  var tokensHit = 0;
  final allHay = _userSearchHayCombined(d);
  final allNs = _poSearchHayNoSpace(allHay);
  for (final token in q.tokens) {
    if (_poVariantsMatchHay(_poVariantsForToken(token), allHay, allNs)) {
      tokensHit++;
    }
  }
  if (tokensHit == q.tokens.length && q.tokens.length > 1) {
    score += 25;
  }
  return score;
}

String _collabSearchHayCombined(Map<String, dynamic> d) {
  final rawSc = d['serviceCategories'];
  final scBuf = StringBuffer();
  if (rawSc is List<dynamic>) {
    for (final e in rawSc) {
      if (e is String && e.trim().isNotEmpty) {
        scBuf.write(' ${e.trim()}');
      } else if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        scBuf.write(
          ' ${_matchingFieldStr(m['sub'])} ${_matchingFieldStr(m['main'])}',
        );
      }
    }
  }
  return <String>[
    _collaborationRequestString(d['title']),
    _collaborationRequestString(d['workType']),
    _collaborationRequestString(d['mainCategory']),
    scBuf.toString(),
    _collaborationRequestString(d['location']),
    _collaborationRequestString(d['description']),
    _collaborationRequestString(d['materialCondition']),
    _collaborationRequestString(d['price']),
    _collaborationRequestString(d['status']),
    _collaborationRequestString(d['deadlineText']),
    _matchingFieldStr(d['regionFull']),
    PoRegionFields.fromCollaborationMap(d).regions.join(' '),
  ].join(' ').toLowerCase();
}

bool _collabDocMatchesSearchQuery(Map<String, dynamic> d, _PoSearchQuery q) {
  if (q.isEmpty) return true;
  final hay = _collabSearchHayCombined(d);
  final hayNs = _poSearchHayNoSpace(hay);
  for (final token in q.tokens) {
    if (!_poVariantsMatchHay(_poVariantsForToken(token), hay, hayNs)) {
      return false;
    }
  }
  return true;
}

int _collabSearchRelevanceScore(Map<String, dynamic> d, _PoSearchQuery q) {
  if (q.isEmpty) return 0;
  var score = 0;
  final title = _collaborationRequestString(d['title']).toLowerCase();
  final wt = _collaborationRequestString(d['workType']).toLowerCase();
  final scHay = _collabServiceCategoriesHayForSearch(d);
  final mc = _collaborationRequestString(d['mainCategory']).toLowerCase();
  final loc = _collaborationRequestString(d['location']).toLowerCase();
  final rf = _matchingFieldStr(d['regionFull']).toLowerCase();
  final po = PoRegionFields.fromCollaborationMap(d);
  final regHay = <String>[
    loc,
    rf,
    if (po.regionFull.isNotEmpty) po.regionFull.toLowerCase(),
    ...po.regions.map((r) => r.toLowerCase()),
  ].join(' ');
  final desc = _collaborationRequestString(d['description']).toLowerCase();

  void addIfMatch(String hayLower, int weight) {
    final hns = _poSearchHayNoSpace(hayLower);
    for (final token in q.tokens) {
      if (_poVariantsMatchHay(_poVariantsForToken(token), hayLower, hns)) {
        score += weight;
        return;
      }
    }
  }

  addIfMatch(title, 50);
  addIfMatch(wt, 40);
  addIfMatch(scHay, 30);
  addIfMatch(mc, 20);
  addIfMatch(regHay, 22);
  addIfMatch(desc, 10);

  var tokensHit = 0;
  final allHay = _collabSearchHayCombined(d);
  final allNs = _poSearchHayNoSpace(allHay);
  for (final token in q.tokens) {
    if (_poVariantsMatchHay(_poVariantsForToken(token), allHay, allNs)) {
      tokensHit++;
    }
  }
  if (tokensHit == q.tokens.length && q.tokens.length > 1) {
    score += 25;
  }
  return score;
}

String _collabServiceCategoriesHayForSearch(Map<String, dynamic> d) {
  final rawSc = d['serviceCategories'];
  final buf = StringBuffer();
  if (rawSc is List<dynamic>) {
    for (final e in rawSc) {
      if (e is String && e.trim().isNotEmpty) {
        buf.write(' ${e.trim()}');
      } else if (e is Map) {
        final m = Map<String, dynamic>.from(e);
        buf.write(
          ' ${_matchingFieldStr(m['sub'])} ${_matchingFieldStr(m['main'])}',
        );
      }
    }
  }
  return buf.toString().toLowerCase();
}

bool _userDocSubsFromServiceCategoriesContain(
    Map<String, dynamic> d, Set<String> distinctSubs,) {
  final keys = ServiceCategoryCatalog.selectionKeysFromFirestore(
    serviceCategories: d['serviceCategories'],
  );
  final docSubs = ServiceCategoryCatalog.distinctSubs(keys);
  for (final s in distinctSubs) {
    final sl = s.trim();
    if (sl.isEmpty) continue;
    final slLower = sl.toLowerCase();
    for (final ds in docSubs) {
      final dl = ds.toLowerCase();
      if (dl == slLower || dl.contains(slLower) || slLower.contains(dl)) {
        return true;
      }
    }
  }
  return false;
}

bool _userMatchesServiceSubFilter(
  Map<String, dynamic> d,
  Set<String> distinctSubs,
) {
  if (distinctSubs.isEmpty) return true;
  if (_userSearchCategoriesMatchSubs(d, distinctSubs)) return true;
  return _userDocSubsFromServiceCategoriesContain(d, distinctSubs);
}

bool _collabListSearchCategoriesMatchSubs(
  Map<String, dynamic> d,
  Set<String> distinctSubs,
) {
  final raw = d['searchCategories'];
  if (raw is! List<dynamic>) return false;
  final items = raw
      .whereType<String>()
      .map((String s) => s.trim().toLowerCase())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
  for (final sub in distinctSubs) {
    final sl = sub.trim().toLowerCase();
    if (sl.isEmpty) continue;
    for (final it in items) {
      if (it.contains(sl) || sl.contains(it)) return true;
    }
  }
  return false;
}

bool _collabMatchesSelectedSubs(
  Map<String, dynamic> d,
  Set<String> distinctSubs,
) {
  if (distinctSubs.isEmpty) return true;
  if (_collabListSearchCategoriesMatchSubs(d, distinctSubs)) return true;

  final raw = d['serviceCategories'];
  final fromSc = <String>[];
  if (raw is List<dynamic>) {
    for (final e in raw) {
      if (e is String && e.trim().isNotEmpty) fromSc.add(e.trim());
    }
  }
  for (final s in distinctSubs) {
    final sl = s.trim();
    if (sl.isEmpty) continue;
    final slLower = sl.toLowerCase();
    for (final c in fromSc) {
      final cl = c.toLowerCase();
      if (cl == slLower || cl.contains(slLower) || slLower.contains(cl)) {
        return true;
      }
    }
  }
  final wt = _collaborationRequestString(d['workType']).toLowerCase();
  for (final s in distinctSubs) {
    final sl = s.trim().toLowerCase();
    if (sl.isNotEmpty && wt.contains(sl)) return true;
  }
  return false;
}

bool _passesUserSearchFilters({
  required Map<String, dynamic> d,
  required String regionFilter,
  required String keywordApplied,
  required Set<String> selectedMainCategories,
  required Set<String> distinctSubs,
}) {
  if (!_userDocRegionMatches(d, regionFilter)) return false;

  if (!_userListContainsAnyMainCat(d, selectedMainCategories)) return false;

  if (!_userMatchesServiceSubFilter(d, distinctSubs)) return false;

  final q = _poParseSearchQuery(keywordApplied);
  if (!q.isEmpty && !_userDocMatchesSearchQuery(d, q)) return false;

  return true;
}

bool _collabDocHasAnyMainCategory(
  Map<String, dynamic> d,
  Set<String> mains,
) {
  if (mains.isEmpty) return true;
  final mc = _collaborationRequestString(d['mainCategory']);
  if (mc.isNotEmpty) {
    for (final m in mains) {
      if (_mainLabelsLooselyMatch(mc, m)) return true;
    }
  }
  final rawList = d['mainCategories'];
  if (rawList is List<dynamic>) {
    for (final e in rawList) {
      if (e is! String) continue;
      final s = e.trim();
      if (s.isEmpty) continue;
      for (final m in mains) {
        if (_mainLabelsLooselyMatch(s, m)) return true;
      }
    }
  }
  final keys = ServiceCategoryCatalog.selectionKeysFromFirestore(
    serviceCategories: d['serviceCategories'],
  );
  for (final k in keys) {
    final p = ServiceCategoryCatalog.splitSelectionKey(k);
    if (p == null) continue;
    for (final m in mains) {
      if (_mainLabelsLooselyMatch(p.main, m)) return true;
    }
  }
  return false;
}

Set<String> _docSubsUnionForMains(
  Map<String, dynamic> d,
  Set<String> mains,
) {
  if (mains.isEmpty) {
    return ServiceCategoryCatalog.distinctSubs(
      ServiceCategoryCatalog.selectionKeysFromFirestore(
        serviceCategories: d['serviceCategories'],
      ),
    );
  }
  final u = <String>{};
  for (final m in mains) {
    u.addAll(_docSubsForMainFilter(d, m));
  }
  return u;
}

/// 비어 있으면 과거 데이터 호환을 위해 모집중으로 간주.
bool _collabOpenLikeStatus(dynamic statusField) {
  final s = _collaborationRequestString(statusField).trim().toLowerCase();
  if (s.isEmpty) return true;
  return s == 'open' || s == '모집중';
}

bool _passesHomeCollaborationFilters({
  required Map<String, dynamic> d,
  required String regionFilter,
  required String keywordApplied,
  required Set<String> selectedMainCategories,
  required Set<String> selectedSubLabels,
}) {
  if (!poRegionDocMatchesSelectedFilter(
    PoRegionFields.fromCollaborationMap(d),
    regionFilter,
  )) {
    return false;
  }

  final q = _poParseSearchQuery(keywordApplied);
  if (!q.isEmpty && !_collabDocMatchesSearchQuery(d, q)) {
    return false;
  }

  if (!_collabDocHasAnyMainCategory(d, selectedMainCategories)) {
    return false;
  }

  if (!_collabMatchesSelectedSubs(d, selectedSubLabels)) {
    return false;
  }

  return true;
}

int _responseSpeedSortRank(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.contains('매우') || s.contains('빠름') || s.contains('빨')) return 0;
  if (s.contains('보통')) return 1;
  if (s.contains('느')) return 2;
  return 3;
}

int _priceRangeSortRank(String raw) {
  final s = raw.trim().toLowerCase();
  if (s.contains('저') || s.contains('낮')) return 0;
  if (s.contains('중')) return 1;
  if (s.contains('고') || s.contains('높')) return 2;
  return 3;
}

bool _userHasAnySubInSearchCategories(Map<String, dynamic> d, Set<String> subs) {
  if (subs.isEmpty) return true;
  return _userSearchCategoriesMatchSubs(d, subs);
}

DateTime? _firestoreAsDateTime(dynamic v) {
  if (v is Timestamp) return v.toDate();
  return null;
}

int _compareRecommendedUsers(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required String regionFilter,
  required Set<String> distinctSubs,
}) {
  final ua = _matchingUserAvailable(a);
  final ub = _matchingUserAvailable(b);
  if (ua != ub) return ua ? -1 : 1;

  final ra = _userDocRegionMatches(a, regionFilter) ? 0 : 1;
  final rb = _userDocRegionMatches(b, regionFilter) ? 0 : 1;
  if (ra != rb) return ra.compareTo(rb);

  final sa = _userHasAnySubInSearchCategories(a, distinctSubs) ? 0 : 1;
  final sb = _userHasAnySubInSearchCategories(b, distinctSubs) ? 0 : 1;
  if (sa != sb) return sa.compareTo(sb);

  final fa = _responseSpeedSortRank(_matchingFieldStr(a['responseSpeed']));
  final fb = _responseSpeedSortRank(_matchingFieldStr(b['responseSpeed']));
  if (fa != fb) return fa.compareTo(fb);

  final pa = _priceRangeSortRank(_matchingFieldStr(a['priceRange']));
  final pb = _priceRangeSortRank(_matchingFieldStr(b['priceRange']));
  if (pa != pb) return pa.compareTo(pb);

  return 0;
}

int _compareRecommendedCollabs(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required String regionFilter,
  required Set<String> selectedMainCategories,
  required Set<String> selectedSubLabels,
}) {
  final oa = _collaborationRequestString(a['status']);
  final ob = _collaborationRequestString(b['status']);
  final openA = _collabOpenLikeStatus(oa);
  final openB = _collabOpenLikeStatus(ob);
  if (openA != openB) return openA ? -1 : 1;

  final ma = poRegionDocMatchesSelectedFilter(
    PoRegionFields.fromCollaborationMap(a),
    regionFilter,
  );
  final mb = poRegionDocMatchesSelectedFilter(
    PoRegionFields.fromCollaborationMap(b),
    regionFilter,
  );
  if (ma != mb) return ma ? -1 : 1;

  bool hits(Map<String, dynamic> d, Set<String> filterSubs) {
    if (filterSubs.isEmpty) return true;
    final docSubs = _docSubsUnionForMains(d, selectedMainCategories);
    for (final sub in filterSubs) {
      if (docSubs.contains(sub)) return true;
      if (_collaborationRequestString(d['workType'])
          .toLowerCase()
          .contains(sub.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  final ha = hits(a, selectedSubLabels);
  final hb = hits(b, selectedSubLabels);
  if (ha != hb) return ha ? -1 : 1;

  final da = _firestoreAsDateTime(a['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
  final db = _firestoreAsDateTime(b['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
  return db.compareTo(da);
}

double _homeUserSortRatingValue(Map<String, dynamic> d) {
  final v = d['averageRating'];
  if (v is num) return v.toDouble();
  return double.negativeInfinity;
}

/// 표시이름순: displayName → shopName → businessName (비어 있으면 다음 필드).
String _homeUserSortDisplayNameKey(Map<String, dynamic> d) {
  for (final key in <String>['displayName', 'shopName', 'businessName']) {
    final s = _matchingFieldStr(d[key]);
    if (s.isNotEmpty) return s;
  }
  return '';
}

int _homeUserPrimaryCompare(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  String sortOption,
) {
  switch (sortOption) {
    case kPoListSortRating:
      return _homeUserSortRatingValue(b)
          .compareTo(_homeUserSortRatingValue(a));
    case kPoListSortValue:
      final pa = _priceRangeSortRank(_matchingFieldStr(a['priceRange']));
      final pb = _priceRangeSortRank(_matchingFieldStr(b['priceRange']));
      return pa.compareTo(pb);
    case kPoListSortDisplayName:
      return _homeUserSortDisplayNameKey(a)
          .compareTo(_homeUserSortDisplayNameKey(b));
    case kPoListSortDistance:
      // TODO(geolocation): 실제 위도·경도 기반 거리 계산으로 교체 예정.
      return _matchingFieldStr(a['region'])
          .compareTo(_matchingFieldStr(b['region']));
    case kPoListSortDeadline:
      return 0;
    default:
      return 0;
  }
}

int _compareHomeUsersWithSort(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  String? sortOption, {
  required bool sortDescending,
  required String regionFilter,
  required Set<String> distinctSubs,
}) {
  if (sortOption == null || sortOption.isEmpty) {
    return _compareRecommendedUsers(
      a,
      b,
      regionFilter: regionFilter,
      distinctSubs: distinctSubs,
    );
  }

  var primary = _homeUserPrimaryCompare(a, b, sortOption);
  final invert =
      sortDescending != poListSortDefaultDescending(sortOption);
  if (invert) primary = -primary;

  if (primary != 0) return primary;
  return _compareRecommendedUsers(
    a,
    b,
    regionFilter: regionFilter,
    distinctSubs: distinctSubs,
  );
}

/// `deadline` 필드에서 정렬용 epoch(ms). 파싱 불가면 null.
int? _collabRequestDeadlineMillis(Map<String, dynamic> d) {
  final v = d['deadline'];
  if (v == null) return null;
  if (v is Timestamp) return v.millisecondsSinceEpoch;
  if (v is DateTime) return v.millisecondsSinceEpoch;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final t = DateTime.tryParse(v);
    if (t != null) return t.millisecondsSinceEpoch;
  }
  return null;
}

/// 0 = 마감일 지정+날짜 있음, 1 = 수시모집(always), 2 = 레거시·미설정
int _collabRequestDeadlineSortTier(Map<String, dynamic> d) {
  final t = _collaborationRequestString(d['deadlineType']).trim().toLowerCase();
  if (t == 'date' && _collabRequestDeadlineMillis(d) != null) return 0;
  if (t == 'always') return 1;
  return 2;
}

int _compareCollaborationFeedDocsWithSort(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  String? sortOption, {
  required bool sortDescending,
  required String regionFilter,
  required Set<String> selectedMainCategories,
  required Set<String> selectedSubLabels,
}) {
  int tieBreak() {
    final primary = _collabSortForSearch(a, b);
    if (primary != 0) return primary;
    return _compareRecommendedCollabs(
      a,
      b,
      regionFilter: regionFilter,
      selectedMainCategories: selectedMainCategories,
      selectedSubLabels: selectedSubLabels,
    );
  }

  if (sortOption == null || sortOption.isEmpty) {
    return tieBreak();
  }

  switch (sortOption) {
    case kPoListSortRating:
      // TODO(collab-rating): 의뢰 공고에 평점 필드가 생기면 primary 비교로 교체.
      final t = tieBreak();
      final invert =
          sortDescending != poListSortDefaultDescending(sortOption);
      return invert ? -t : t;
    case kPoListSortResponse:
      // TODO(collab-response): 공고 응답 속성 도입 시 primary 비교로 교체.
      final t = tieBreak();
      final invert =
          sortDescending != poListSortDefaultDescending(sortOption);
      return invert ? -t : t;
    case kPoListSortDistance:
      // TODO(geolocation): 위도·경도 기반 거리 계산으로 교체 예정.
      final la = _collaborationRequestString(a['location']);
      final lb = _collaborationRequestString(b['location']);
      var c = la.compareTo(lb);
      final invert =
          sortDescending != poListSortDefaultDescending(sortOption);
      if (invert) c = -c;
      if (c != 0) return c;
      return tieBreak();
    case kPoListSortDeadline:
      final ea = _collabRequestDeadlineSortTier(a);
      final eb = _collabRequestDeadlineSortTier(b);
      if (ea != eb) return ea.compareTo(eb);
      if (ea == 0) {
        final ma = _collabRequestDeadlineMillis(a)!;
        final mb = _collabRequestDeadlineMillis(b)!;
        var c = ma.compareTo(mb);
        final invert =
            sortDescending != poListSortDefaultDescending(sortOption);
        if (invert) c = -c;
        if (c != 0) return c;
      }
      return tieBreak();
    default:
      return tieBreak();
  }
}

int _compareHomeUsersOrdered(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required _PoSearchQuery searchQ,
  required String? sortOption,
  required bool sortDescending,
  required String regionFilter,
  required Set<String> distinctSubs,
}) {
  if (!searchQ.isEmpty &&
      (sortOption == null || sortOption.isEmpty)) {
    final ra = _userSearchRelevanceScore(a, searchQ);
    final rb = _userSearchRelevanceScore(b, searchQ);
    if (ra != rb) return rb.compareTo(ra);
  }
  return _compareHomeUsersWithSort(
    a,
    b,
    sortOption,
    sortDescending: sortDescending,
    regionFilter: regionFilter,
    distinctSubs: distinctSubs,
  );
}

int _compareCollabDocsOrdered(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  required _PoSearchQuery searchQ,
  required String? sortOption,
  required bool sortDescending,
  required String regionFilter,
  required Set<String> selectedMainCategories,
  required Set<String> selectedSubLabels,
}) {
  if (!searchQ.isEmpty &&
      (sortOption == null || sortOption.isEmpty)) {
    final ra = _collabSearchRelevanceScore(a, searchQ);
    final rb = _collabSearchRelevanceScore(b, searchQ);
    if (ra != rb) return rb.compareTo(ra);
  }
  return _compareCollaborationFeedDocsWithSort(
    a,
    b,
    sortOption,
    sortDescending: sortDescending,
    regionFilter: regionFilter,
    selectedMainCategories: selectedMainCategories,
    selectedSubLabels: selectedSubLabels,
  );
}

// ---------------------------------------------------------------------------
// businesses 컬렉션 — 검색/필터/관련도 헬퍼
// ---------------------------------------------------------------------------

/// businesses 문서에서 검색 haystack 생성.
/// 필드: businessName, ownerName, category, serviceType, sourceKeyword,
///       region, address, roadAddress, subCategories, description
String _businessSearchHay(Map<String, dynamic> d) {
  final subCats = <String>[];
  final raw = d['subCategories'];
  if (raw is List) {
    for (final e in raw) {
      if (e is String && e.trim().isNotEmpty) subCats.add(e.trim());
    }
  }
  return <String>[
    _claimFieldStr(d['businessName']),
    _claimFieldStr(d['ownerName']),
    _claimFieldStr(d['category']),
    _claimFieldStr(d['serviceType']),
    _claimFieldStr(d['sourceKeyword']),
    _claimFieldStr(d['region']),
    _claimFieldStr(d['address']),
    _claimFieldStr(d['roadAddress']),
    subCats.join(' '),
    _claimFieldStr(d['description']),
  ].join(' ').toLowerCase();
}

bool _businessDocMatchesSearchQuery(
    Map<String, dynamic> d, _PoSearchQuery q) {
  if (q.isEmpty) return true;
  final hay = _businessSearchHay(d);
  final hayNs = _poSearchHayNoSpace(hay);
  for (final token in q.tokens) {
    if (!_poVariantsMatchHay(_poVariantsForToken(token), hay, hayNs)) {
      return false;
    }
  }
  return true;
}

int _businessSearchRelevanceScore(
    Map<String, dynamic> d, _PoSearchQuery q) {
  if (q.isEmpty) return 0;
  var score = 0;

  void add(String hayLower, int weight) {
    final hns = _poSearchHayNoSpace(hayLower);
    for (final token in q.tokens) {
      if (_poVariantsMatchHay(_poVariantsForToken(token), hayLower, hns)) {
        score += weight;
      }
    }
  }

  add(_claimFieldStr(d['businessName']).toLowerCase(), 10);
  add(_claimFieldStr(d['category']).toLowerCase(), 5);
  add(_claimFieldStr(d['serviceType']).toLowerCase(), 5);

  final subCats = <String>[];
  final raw = d['subCategories'];
  if (raw is List) {
    for (final e in raw) {
      if (e is String) subCats.add(e.trim().toLowerCase());
    }
  }
  add(subCats.join(' '), 4);
  add(_claimFieldStr(d['region']).toLowerCase(), 3);
  add(_claimFieldStr(d['address']).toLowerCase(), 2);
  add(_claimFieldStr(d['roadAddress']).toLowerCase(), 2);
  return score;
}

/// businesses 문서가 지역 필터를 통과하는지 확인.
bool _businessDocMatchesRegion(Map<String, dynamic> d, String regionFilter) {
  if (regionFilter.isEmpty) return true;
  final f = regionFilter.trim().toLowerCase();
  final region = _claimFieldStr(d['region']).toLowerCase();
  final address = _claimFieldStr(d['address']).toLowerCase();
  final road = _claimFieldStr(d['roadAddress']).toLowerCase();
  return region.contains(f) || address.contains(f) || road.contains(f);
}

/// businesses 문서가 메인 카테고리 필터를 통과하는지 확인.
bool _businessDocMatchesMainCategories(
    Map<String, dynamic> d, Set<String> mains) {
  if (mains.isEmpty) return true;
  final cat = _claimFieldStr(d['category']).toLowerCase();
  final svc = _claimFieldStr(d['serviceType']).toLowerCase();
  final srcKw = _claimFieldStr(d['sourceKeyword']).toLowerCase();
  final subCats = <String>[];
  final raw = d['subCategories'];
  if (raw is List) {
    for (final e in raw) {
      if (e is String && e.trim().isNotEmpty) {
        subCats.add(e.trim().toLowerCase());
      }
    }
  }
  for (final m in mains) {
    final ml = m.trim().toLowerCase();
    if (ml.isEmpty) continue;
    if (cat.contains(ml) || svc.contains(ml) || srcKw.contains(ml)) {
      return true;
    }
    for (final s in subCats) {
      if (s.contains(ml)) return true;
    }
  }
  return false;
}

/// businesses 문서가 서브 카테고리(distinctSubs) 필터를 통과하는지 확인.
bool _businessDocMatchesDistinctSubs(
    Map<String, dynamic> d, Set<String> subs) {
  if (subs.isEmpty) return true;
  final cat = _claimFieldStr(d['category']).toLowerCase();
  final svc = _claimFieldStr(d['serviceType']).toLowerCase();
  final subCats = <String>[];
  final raw = d['subCategories'];
  if (raw is List) {
    for (final e in raw) {
      if (e is String && e.trim().isNotEmpty) {
        subCats.add(e.trim().toLowerCase());
      }
    }
  }
  final hay = '$cat $svc ${subCats.join(' ')}';
  for (final sub in subs) {
    if (hay.contains(sub.trim().toLowerCase())) return true;
  }
  return false;
}

/// businesses 문서 전체 필터 통과 여부.
bool _passesBusinessFilters({
  required Map<String, dynamic> d,
  required String regionFilter,
  required String keywordApplied,
  required Set<String> selectedMainCategories,
  required Set<String> distinctSubs,
}) {
  if (!_businessDocMatchesRegion(d, regionFilter)) return false;
  if (!_businessDocMatchesMainCategories(d, selectedMainCategories)) {
    return false;
  }
  if (!_businessDocMatchesDistinctSubs(d, distinctSubs)) return false;
  final q = _poParseSearchQuery(keywordApplied);
  if (!q.isEmpty && !_businessDocMatchesSearchQuery(d, q)) return false;
  return true;
}

// ---------------------------------------------------------------------------

const Color _kHomeTabAccent = Color(0xFF007AFF);

Widget _homePartnerCard({
  required BuildContext context,
  required TextTheme textTheme,
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
  required Set<String> favoriteUids,
}) {
    final d = doc.data();
    final name = poHomeUserCardTitle(d);
    final regions = _matchingUserRegionsLine(d);
    final primary = _matchingFieldStr(d['primaryCategory']);
    final cats = _matchingUserSearchCategories(d);
    final catsJoined = cats.isEmpty ? '-' : cats.join(' · ');
    final price = _matchingFieldStr(d['priceRange']);
    final resp = _matchingFieldStr(d['responseSpeed']);
    final phoneRaw = poUserPrimaryPhone(d);
    final isFav = favoriteUids.contains(doc.id);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: () {
            Navigator.of(context).push(poSmoothPushRoute<void>(
              CompanyDetailScreen(
                partnerUid: doc.id,
                userData: Map<String, dynamic>.from(doc.data()),
              ),
            ));
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    if (poBusinessVerificationShowVerifiedBadge(d)) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 4),
                        child: poVerifiedCompanyBadgeChip(fontSize: 10),
                      ),
                    ],
                    IconButton(
                      tooltip: isFav ? '즐겨찾기 해제' : '즐겨찾기',
                      onPressed: () =>
                          toggleFavoritePartnerUidForMe(context, doc.id),
                      icon: Icon(
                        isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: _kHomeTabAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        regions,
                        style: textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade700),
                      ),
                    ),
                  ],
                ),
                if (primary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    primary,
                    style: textTheme.labelMedium?.copyWith(
                      color: _kHomeTabAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  catsJoined,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade800,
                    height: 1.35,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_rounded,
                            size: 18, color: Colors.amber.shade700),
                        const SizedBox(width: 4),
                        Text(
                          '평점 ${_matchingFormatAverageRatingDisplay(d)}',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '가성비 · ${price.isEmpty ? '-' : price}',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '응답 · ${resp.isEmpty ? '-' : resp}',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '위치',
                      icon: Icon(Icons.place_outlined, color: _kHomeTabAccent),
                      onPressed: regions == '-' || regions.isEmpty
                          ? null
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('지역: $regions')),
                              );
                            },
                    ),
                    IconButton(
                      tooltip: '전화',
                      icon: Icon(Icons.call_outlined, color: _kHomeTabAccent),
                      onPressed: phoneRaw.isEmpty
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('등록된 전화번호가 없습니다.'),
                                ),
                              );
                            }
                          : () {
                              final sanitized = phoneRaw
                                  .replaceAll(RegExp(r'[^\d+]'), '');
                              _launchBusinessPhone(Uri.parse('tel:$sanitized'));
                            },
                    ),
                    IconButton(
                      tooltip: '채팅',
                      icon: Icon(Icons.chat_bubble_outline_rounded,
                          color: _kHomeTabAccent),
                      onPressed: () {
                        runWithBriefLoading(context, () {
                          if (!context.mounted) return;
                          Navigator.of(context).push(poSmoothPushRoute<void>(
                            ChatScreen(
                              requestId: 'direct',
                              partnerUid: doc.id,
                              requestTitle: '$name · 문의',
                              partnerDisplayName: name,
                            ),
                          ));
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


/// businesses 컬렉션 문서를 위한 홈 목록 카드.
Widget _homeBusinessCard({
  required BuildContext context,
  required TextTheme textTheme,
  required QueryDocumentSnapshot<Map<String, dynamic>> doc,
}) {
  final d = doc.data();
  final name = _claimFieldStr(d['businessName']);
  final region = _claimFieldStr(d['region']);
  final address = _claimFieldStr(d['address']);
  final roadAddress = _claimFieldStr(d['roadAddress']);
  final phoneOpts = _extractBusinessPhoneOptions(d);
  final category = _claimFieldStr(d['category']);
  final serviceType = _claimFieldStr(d['serviceType']);
  final claimed = d['claimed'] == true;
  final verified = d['verified'] == true;

  final locationLine = roadAddress.isNotEmpty
      ? roadAddress
      : address.isNotEmpty
          ? address
          : region;
  final categoryLine =
      serviceType.isNotEmpty ? serviceType : category;

  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => Navigator.of(context).push(
          poSmoothPushRoute<void>(
              BusinessDetailScreen(businessId: doc.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      name.isEmpty ? '(업체명 없음)' : name,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  // 인증 배지
                  if (verified)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 4),
                      child: poVerifiedCompanyBadgeChip(fontSize: 10),
                    ),
                  // 사전등록 배지 (claimed == false)
                  if (!claimed)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          child: Text(
                            '사전등록',
                            style: textTheme.labelSmall?.copyWith(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w700,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (locationLine.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.place_outlined,
                        size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        locationLine,
                        style: textTheme.bodySmall
                            ?.copyWith(color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              if (categoryLine.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  categoryLine,
                  style: textTheme.labelMedium?.copyWith(
                    color: _kHomeTabAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 위치 버튼
                  if (locationLine.isNotEmpty)
                    IconButton(
                      tooltip: '위치',
                      icon: Icon(Icons.place_outlined,
                          color: _kHomeTabAccent),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('지역: $locationLine')),
                        );
                      },
                    ),
                  // 전화 버튼 — 번호 없으면 비활성
                  IconButton(
                    tooltip: phoneOpts.isEmpty ? '전화번호 없음' : '전화',
                    icon: Icon(
                      Icons.call_outlined,
                      color: phoneOpts.isEmpty
                          ? Colors.grey.shade400
                          : _kHomeTabAccent,
                    ),
                    onPressed: phoneOpts.isEmpty
                        ? null
                        : () => poShowBusinessPhoneSheet(context, d),
                  ),
                  // 내 업체 인증하기 버튼 (claimed == false 일 때만)
                  if (!claimed)
                    IconButton(
                      tooltip: '내 업체 인증하기',
                      icon: Icon(Icons.verified_user_outlined,
                          color: _kHomeTabAccent),
                      onPressed: () => Navigator.of(context).push(
                        poSmoothPushRoute<void>(
                          BusinessDetailScreen(businessId: doc.id),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 홈 탭: 업체 목록 (필터·카테고리는 [PoMainListHeader]).
class HomeTabScreen extends StatelessWidget {
  const HomeTabScreen({
    super.key,
    required this.regionFilter,
    required this.keyword,
    required this.selectedMainCategories,
    required this.subKeySet,
    required this.favoritesOnly,
    required this.selectedSortOption,
    required this.sortDescending,
  });

  final String regionFilter;
  final String keyword;
  final Set<String> selectedMainCategories;
  final Set<String> subKeySet;
  final bool favoritesOnly;
  final String? selectedSortOption;
  final bool sortDescending;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final distinctSubs = ServiceCategoryCatalog.distinctSubs(subKeySet);

    if (uid == null) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('업체 목록을 보려면 로그인해 주세요.'),
          ),
        ),
      );
    }

    return ColoredBox(
      color: Colors.white,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream:
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, meSnap) {
          if (meSnap.hasError) {
            poReportFirestoreSnapshotError(
              'home_me_doc',
              meSnap.error!,
            );
            return Center(
              child: poFirestoreUserErrorPlaceholder(context),
            );
          }
          final rawFav = meSnap.data?.data()?['favoritePartnerUids'];
          final fav = <String>{
            if (rawFav is Iterable)
              for (final e in rawFav)
                if (e is String && e.trim().isNotEmpty) e.trim(),
          };

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, userQs) {
              if (userQs.hasError) {
                poReportFirestoreSnapshotError(
                    'home_partner_list', userQs.error!);
                return Center(
                    child: poFirestoreUserErrorPlaceholder(context));
              }

              // businesses 컬렉션 병렬 스트림
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('businesses')
                    .snapshots(),
                builder: (context, bizQs) {
                  if (bizQs.hasError) {
                    poReportFirestoreSnapshotError(
                        'home_businesses_list', bizQs.error!);
                  }

                  final usersLoading =
                      userQs.connectionState == ConnectionState.waiting &&
                          !userQs.hasData;
                  final bizLoading =
                      bizQs.connectionState == ConnectionState.waiting &&
                          !bizQs.hasData;
                  if (usersLoading && bizLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final searchQ = _poParseSearchQuery(keyword);

                  // ── users 목록 필터 ──────────────────────────────────
                  var userList = (userQs.data?.docs ??
                          const <QueryDocumentSnapshot<
                              Map<String, dynamic>>>[])
                      .where(
                        (q) => _passesUserSearchFilters(
                          d: q.data(),
                          regionFilter: regionFilter,
                          keywordApplied: keyword,
                          selectedMainCategories: selectedMainCategories,
                          distinctSubs: distinctSubs,
                        ),
                      )
                      .toList();

                  if (favoritesOnly) {
                    userList =
                        userList.where((q) => fav.contains(q.id)).toList();
                  }

                  userList.sort(
                    (a, b) => _compareHomeUsersOrdered(
                      a.data(),
                      b.data(),
                      searchQ: searchQ,
                      sortOption: selectedSortOption,
                      sortDescending: sortDescending,
                      regionFilter: regionFilter,
                      distinctSubs: distinctSubs,
                    ),
                  );

                  // ── businesses 목록 필터 ─────────────────────────────
                  // 즐겨찾기 모드일 때는 businesses 숨김 (uid 기반 즐겨찾기 없음)
                  var bizList = favoritesOnly
                      ? <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                      : (bizQs.data?.docs ??
                              const <QueryDocumentSnapshot<
                                  Map<String, dynamic>>>[])
                          .where(
                            (q) => _passesBusinessFilters(
                              d: q.data(),
                              regionFilter: regionFilter,
                              keywordApplied: keyword,
                              selectedMainCategories: selectedMainCategories,
                              distinctSubs: distinctSubs,
                            ),
                          )
                          .toList();

                  bizList.sort((a, b) {
                    if (!searchQ.isEmpty) {
                      final ra =
                          _businessSearchRelevanceScore(a.data(), searchQ);
                      final rb =
                          _businessSearchRelevanceScore(b.data(), searchQ);
                      if (ra != rb) return rb.compareTo(ra);
                    }
                    return _claimFieldStr(a.data()['businessName'])
                        .compareTo(
                            _claimFieldStr(b.data()['businessName']));
                  });

                  // ── 병합 결과 렌더링 ─────────────────────────────────
                  final totalCount =
                      userList.length + bizList.length;

                  if (totalCount == 0) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          !searchQ.isEmpty
                              ? '검색 결과가 없습니다.'
                              : favoritesOnly
                                  ? '즐겨찾기한 업체가 없습니다.'
                                  : '조건에 맞는 업체가 없습니다.',
                          textAlign: TextAlign.center,
                          style: textTheme.bodyMedium?.copyWith(
                            color: Colors.grey.shade600,
                            height: 1.45,
                          ),
                        ),
                      ),
                    );
                  }

                  // 사전등록 업체 구분선 여부
                  final hasDivider =
                      userList.isNotEmpty && bizList.isNotEmpty;
                  final itemCount =
                      totalCount + (hasDivider ? 1 : 0);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!searchQ.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 0),
                          child: Text(
                            '검색 결과 $totalCount개',
                            style: textTheme.labelLarge?.copyWith(
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            poMainShellTabScrollBottomPadding(context),
                          ),
                          itemCount: itemCount,
                          itemBuilder: (context, i) {
                            // users 카드
                            if (i < userList.length) {
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 10),
                                child: _homePartnerCard(
                                  context: context,
                                  textTheme: textTheme,
                                  doc: userList[i],
                                  favoriteUids: fav,
                                ),
                              );
                            }

                            // 구분선 (사전등록 업체 섹션 헤더)
                            if (hasDivider && i == userList.length) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                          color: Colors.grey.shade200),
                                    ),
                                    Padding(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12),
                                      child: Text(
                                        '사전 등록 업체',
                                        style: textTheme.labelSmall
                                            ?.copyWith(
                                          color: Colors.grey.shade500,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                          color: Colors.grey.shade200),
                                    ),
                                  ],
                                ),
                              );
                            }

                            // businesses 카드
                            final bizIdx = i -
                                userList.length -
                                (hasDivider ? 1 : 0);
                            return Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10),
                              child: _homeBusinessCard(
                                context: context,
                                textTheme: textTheme,
                                doc: bizList[bizIdx],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}


/// 검색 결과: 모집중·open 먼저, 그다음 상태명 사전순.
int _collabSortForSearch(Map<String, dynamic> a, Map<String, dynamic> b) {
  final sa = _collaborationRequestString(a['status']);
  final sb = _collaborationRequestString(b['status']);
  final oa = _collabOpenLikeStatus(sa);
  final ob = _collabOpenLikeStatus(sb);
  if (oa != ob) return oa ? -1 : 1;
  return sa.toLowerCase().compareTo(sb.toLowerCase());
}
