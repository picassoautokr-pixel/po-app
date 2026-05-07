// 지역 필드 정규화 및 검색용 `regions` 생성 (users / collaborationRequests 공통).

/// 공백 정리 후 토큰 분리.
List<String> poRegionSplitParts(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return const [];
  return t
      .split(RegExp(r'\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);
}

/// 행정구역 토큰에서 검색·필터용 별칭을 붙입니다.
///
/// 예: "서울 강남구 역삼동" 근처 → `강남`(강남구), `역삼`(역삼동), `수원`(수원시) 등.
List<String> poRegionBuildSearchList(List<String> parts, {String? regionFull}) {
  final out = <String>[];

  void add(String s) {
    final x = s.trim();
    if (x.isEmpty) return;
    if (!out.contains(x)) out.add(x);
  }

  void addAdminAliases(String p) {
    if (p.length <= 1) return;
    if (p.endsWith('구')) {
      add(p.substring(0, p.length - 1));
    }
    if (p.endsWith('동')) {
      add(p.substring(0, p.length - 1));
    }
    if (p.endsWith('읍') || p.endsWith('면')) {
      add(p.substring(0, p.length - 1));
    }
    if (p.endsWith('시')) {
      add(p.substring(0, p.length - 1));
    }
  }

  for (final p in parts) {
    add(p);
    addAdminAliases(p);
  }

  final full = (regionFull ?? parts.join(' ')).trim();
  if (full.isNotEmpty) {
    add(full);
    final fp = poRegionSplitParts(full);
    if (fp.length >= 2) {
      add(fp.sublist(0, 2).join(' '));
    }
    if (fp.length >= 3) {
      add(fp.sublist(0, 3).join(' '));
    }
  }

  return out;
}

class PoRegionFields {
  const PoRegionFields({
    required this.regionFull,
    required this.regionLevel1,
    required this.regionLevel2,
    required this.regionLevel3,
    required this.regions,
  });

  final String regionFull;
  final String regionLevel1;
  final String regionLevel2;
  final String regionLevel3;
  final List<String> regions;

  static const PoRegionFields empty = PoRegionFields(
    regionFull: '',
    regionLevel1: '',
    regionLevel2: '',
    regionLevel3: '',
    regions: <String>[],
  );

  /// 단일 주소 한 줄에서 레벨·검색 배열 계산.
  factory PoRegionFields.fromRegionFull(String raw) {
    final full = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (full.isEmpty) return PoRegionFields.empty;

    final parts = poRegionSplitParts(full);
    final l1 = parts.isNotEmpty ? parts[0] : '';
    final l2 = parts.length > 1 ? parts[1] : '';
    final l3 = parts.length > 2 ? parts[2] : '';

    final search = poRegionBuildSearchList(parts, regionFull: full);

    return PoRegionFields(
      regionFull: full,
      regionLevel1: l1,
      regionLevel2: l2,
      regionLevel3: l3,
      regions: search,
    );
  }

  /// `users` 문서: 신규 필드 우선, 없으면 `region` / `regions`에서 합성.
  factory PoRegionFields.fromUserMap(Map<String, dynamic>? d) {
    if (d == null) return PoRegionFields.empty;

    final rf = _stringField(d['regionFull']);
    if (rf.isNotEmpty) return PoRegionFields.fromRegionFull(rf);

    final single = _stringField(d['region']);
    if (single.isNotEmpty) return PoRegionFields.fromRegionFull(single);

    final rawList = d['regions'];
    if (rawList is List<dynamic>) {
      final strings = rawList
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (strings.isNotEmpty) {
        return PoRegionFields.fromRegionFull(strings.join(' '));
      }
    }

    return PoRegionFields.empty;
  }

  /// `collaborationRequests`: `regionFull` 우선, 없으면 `location`.
  factory PoRegionFields.fromCollaborationMap(Map<String, dynamic>? d) {
    if (d == null) return PoRegionFields.empty;

    final rf = _stringField(d['regionFull']);
    if (rf.isNotEmpty) return PoRegionFields.fromRegionFull(rf);

    final loc = _stringField(d['location']);
    if (loc.isNotEmpty) return PoRegionFields.fromRegionFull(loc);

    final rawList = d['regions'];
    if (rawList is List<dynamic>) {
      final strings = rawList
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
      if (strings.isNotEmpty) {
        return PoRegionFields.fromRegionFull(strings.join(' '));
      }
    }

    return PoRegionFields.empty;
  }

  static String _stringField(dynamic v) => v is String ? v.trim() : '';
}

/// Firestore `set` / `merge`용 (빈 문자열은 호출부에서 생략 가능).
Map<String, Object?> poRegionUserFirestoreMap(PoRegionFields f) {
  return <String, Object?>{
    'regionFull': f.regionFull,
    'regionLevel1': f.regionLevel1,
    'regionLevel2': f.regionLevel2,
    'regionLevel3': f.regionLevel3,
    'regions': f.regions,
    if (f.regionFull.isNotEmpty) 'region': f.regionFull,
  };
}

Map<String, Object?> poRegionCollaborationFirestoreMap(
    PoRegionFields f,) {
  return <String, Object?>{
    'regionFull': f.regionFull,
    'regionLevel1': f.regionLevel1,
    'regionLevel2': f.regionLevel2,
    'regionLevel3': f.regionLevel3,
    'regions': f.regions,
  };
}

/// 문서·필터·겹침 판별에 쓰는 지역 토큰 집합 (레거시 `location`만 있어도 [fromCollaborationMap]으로 복원).
Set<String> poRegionExpandedDocTokens(PoRegionFields fields) {
  final out = <String>{};
  void add(String? s) {
    if (s == null) return;
    final x = s.trim();
    if (x.isEmpty) return;
    out.add(x);
  }

  add(fields.regionLevel1);
  add(fields.regionLevel2);
  add(fields.regionLevel3);
  if (fields.regionFull.isNotEmpty) {
    add(fields.regionFull);
    for (final p in poRegionSplitParts(fields.regionFull)) {
      add(p);
    }
  }
  for (final r in fields.regions) {
    add(r);
  }
  return out;
}

/// 한글 지역 토큰 느슨한 일치 (예: 필터 "강남" ↔ 문서 "강남구").
bool poRegionTokensLooselyMatch(String docTok, String needle) {
  final d = docTok.trim();
  final n = needle.trim();
  if (d.isEmpty || n.isEmpty) return false;
  if (d == n) return true;
  final dl = d.toLowerCase();
  final nl = n.toLowerCase();
  if (dl == nl) return true;
  const minSub = 2;
  if (nl.length >= minSub && dl.contains(nl)) return true;
  if (dl.length >= minSub && nl.contains(dl)) return true;
  return false;
}

/// 업체·공고 지역이 겹치는지 (거리/GPS 이전 단계의 완화된 교집합).
bool poRegionFieldsOverlap(PoRegionFields a, PoRegionFields b) {
  final ta = poRegionExpandedDocTokens(a);
  final tb = poRegionExpandedDocTokens(b);
  if (ta.isEmpty || tb.isEmpty) return false;
  for (final x in ta) {
    for (final y in tb) {
      if (poRegionTokensLooselyMatch(x, y)) return true;
    }
  }
  return false;
}

/// 홈·구인 협업 지역 필터: [regionFull]·[regions]·레벨·토큰 부분 일치.
bool poRegionDocMatchesSelectedFilter(
  PoRegionFields fields,
  String selectedRegion,
) {
  final needle = selectedRegion.trim();
  if (needle.isEmpty) return true;

  final docTokens = poRegionExpandedDocTokens(fields);
  if (docTokens.isEmpty) return false;

  final parts = poRegionSplitParts(needle);
  if (parts.isEmpty) return false;

  bool needlePartMatches(String part) {
    return docTokens.any((dt) => poRegionTokensLooselyMatch(dt, part));
  }

  if (parts.length > 1) {
    return parts.every(needlePartMatches);
  }

  return needlePartMatches(parts.first);
}
