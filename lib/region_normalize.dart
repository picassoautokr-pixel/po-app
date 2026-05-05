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

/// 예: "서울 강남구 역삼동" → ["서울", "강남구", "역삼동", "강남"]
/// (구 이름은 접미사 `구` 제거 별칭 추가. 순서 유지·중복 제거.)
List<String> poRegionBuildSearchList(List<String> parts, {String? regionFull}) {
  final out = <String>[];

  void add(String s) {
    final x = s.trim();
    if (x.isEmpty) return;
    if (!out.contains(x)) out.add(x);
  }

  for (final p in parts) {
    add(p);
    if (p.length > 1 && p.endsWith('구')) {
      add(p.substring(0, p.length - 1));
    }
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

/// 검색: 선택 지역 문자열이 `regions` 토큰과 일치하는지.
/// - 단일 토큰: `doc.regions.contains(needle)`
/// - 공백으로 구분된 여러 토큰: 각 토큰이 `regions`에 모두 있어야 일치
bool poRegionDocMatchesSelectedFilter(
  PoRegionFields fields,
  String selectedRegion,
) {
  final needle = selectedRegion.trim();
  if (needle.isEmpty) return true;

  final doc = fields.regions.toSet();
  if (doc.isEmpty) return false;

  if (doc.contains(needle)) return true;

  final parts = needle
      .split(RegExp(r'\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  if (parts.length > 1) {
    return parts.every(doc.contains);
  }

  return false;
}
