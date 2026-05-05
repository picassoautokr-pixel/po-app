/// 시공 분야 메인·서브 카테고리 정의, Firestore 형식 변환, PPF·랩핑 연동 처리.
abstract final class ServiceCategoryCatalog {
  ServiceCategoryCatalog._();

  static const String _delimiter = '\x1f';

  /// 외장 / 필름 — PPF·랩핑이 양쪽에 동시 반영됩니다.
  static const String exteriorMainTitle = '외장 시공 (도장/표면)';
  static const String filmMainTitle = '필름 시공';

  /// UI·Firestore에서 메인 카테고리 표시 순서.
  static const List<String> mainTitles = [
    exteriorMainTitle,
    filmMainTitle,
    '전장 시공',
    '실내 시공',
    '튜닝 & 퍼포먼스',
    '정비 & 경정비',
    '특수 시공',
    '사고 수리 & 보험',
  ];

  /// 메인 카테고리별 서브(서비스) 목록 (순서 고정).
  static final Map<String, List<String>> servicesByMain = {
    exteriorMainTitle: [
      '광택 / 폴리싱',
      '유리막 코팅 / 세라믹 코팅',
      'PPF',
      '랩핑',
      '덴트',
      '판금 / 도장',
    ],
    filmMainTitle: [
      '썬팅 (틴팅)',
      '건물/차량 겸용 필름 (열차단, 보안)',
      'PPF',
      '랩핑',
    ],
    '전장 시공': [
      '블랙박스',
      '내비게이션',
      '후방카메라',
      '하이패스',
      '순정 옵션 활성화 (코딩)',
      '전기차 관련 작업',
    ],
    '실내 시공': [
      '시트 (가죽 / 커버)',
      '실내 크리닝 / 디테일링',
      '방음 / 방진',
      '트림 교체',
      '천장 (헤드라이너)',
    ],
    '튜닝 & 퍼포먼스': [
      '휠 / 타이어',
      '서스펜션',
      '브레이크',
      '흡기 / 배기',
      'ECU 맵핑',
    ],
    '정비 & 경정비': [
      '엔진오일',
      '브레이크 패드',
      '배터리',
      '냉각수',
      '일반 정비',
    ],
    '특수 시공': [
      '캠핑카 개조',
      '구조변경',
      '특장차 작업',
      '오디오 튜닝 (하이엔드)',
    ],
    '사고 수리 & 보험': [
      '보험 수리',
      '사고차 복원',
      '렌트 연계',
    ],
  };

  /// PPF / 랩핑 선택 시 반대쪽 메인(외장⇄필름)에 동일 서브 반영.
  static bool mirrorsAcrossExteriorAndFilm(String sub) =>
      sub == 'PPF' || sub == '랩핑';

  /// 반대쪽 메인(외장/필름 쌍만). 해당 없으면 null.
  static String? pairedExteriorFilmMain(String main) {
    if (main == exteriorMainTitle) return filmMainTitle;
    if (main == filmMainTitle) return exteriorMainTitle;
    return null;
  }

  static List<String> servicesForMain(String main) =>
      List<String>.from(servicesByMain[main] ?? const <String>[]);

  static String selectionKey(String main, String sub) =>
      '$main$_delimiter$sub';

  static ({String main, String sub})? splitSelectionKey(String key) {
    final s = key;
    final i = s.indexOf(_delimiter);
    if (i <= 0 || i >= s.length - 1) return null;
    return (main: s.substring(0, i), sub: s.substring(i + 1));
  }

  /// 선택 키에서 서브 이름만 모은 집합(동일 라벨이 여러 메인에 있어도 한 번).
  static Set<String> distinctSubs(Set<String> selectionKeys) {
    final out = <String>{};
    for (final raw in selectionKeys) {
      final parsed = splitSelectionKey(raw);
      if (parsed != null) out.add(parsed.sub);
    }
    return out;
  }

  /// [selectionKeys]에 대해 선택을 반영했을 때의 토글 결과 키 집합(중복 제거·PPF/랩핑 연동 포함).
  static Set<String> toggledSelectionSet({
    required Set<String> current,
    required String main,
    required String sub,
    required bool selected,
  }) {
    final next = {...current};
    void applySide(String m, String s, bool sel) {
      final k = selectionKey(m, s);
      if (sel) {
        next.add(k);
      } else {
        next.remove(k);
      }
    }

    applySide(main, sub, selected);

    if (mirrorsAcrossExteriorAndFilm(sub)) {
      final twin = pairedExteriorFilmMain(main);
      if (twin != null) {
        applySide(twin, sub, selected);
      }
    }

    return next;
  }

  /// 선택 키로부터 저장용 `serviceCategories`(중복 제거, 순서 안정화).
  static List<Map<String, String>> buildServiceMaps(Set<String> selectionKeys) {
    final tuples = <String, ({String main, String sub})>{};
    for (final raw in selectionKeys) {
      final parsed = splitSelectionKey(raw);
      if (parsed == null) continue;
      final dedupe = '${parsed.main}|${parsed.sub}';
      tuples[dedupe] = (main: parsed.main, sub: parsed.sub);
    }
    final list = tuples.values.toList(growable: false);
    list.sort((a, b) {
      final cmpM = compareMainTitles(a.main, b.main);
      if (cmpM != 0) return cmpM;
      return compareSubTitles(a.main, a.sub, b.sub);
    });
    return [
      for (final t in list) {'main': t.main, 'sub': t.sub},
    ];
  }

  /// 선택 서브가 존재하는 메인 카테고리 목록(`mainTitles` 순).
  static List<String> buildMainCategoriesList(Set<String> selectionKeys) {
    final mains = <String>{};
    for (final raw in selectionKeys) {
      final parsed = splitSelectionKey(raw);
      if (parsed != null && servicesByMain.containsKey(parsed.main)) {
        mains.add(parsed.main);
      }
    }
    final sorted = mains.toList();
    sorted.sort(compareMainTitles);
    return sorted;
  }

  static int compareMainTitles(String a, String b) {
    final ia = mainTitles.indexOf(a);
    final ib = mainTitles.indexOf(b);
    if (ia >= 0 && ib >= 0 && ia != ib) return ia.compareTo(ib);
    if (ia >= 0 && ib < 0) return -1;
    if (ib >= 0 && ia < 0) return 1;
    return a.compareTo(b);
  }

  static int compareSubTitles(String main, String a, String b) {
    final order = servicesByMain[main];
    if (order == null || order.isEmpty) return a.compareTo(b);
    final ia = order.indexOf(a);
    final ib = order.indexOf(b);
    if (ia >= 0 && ib >= 0 && ia != ib) return ia.compareTo(ib);
    if (ia >= 0 && ib < 0) return -1;
    if (ib >= 0 && ia < 0) return 1;
    return a.compareTo(b);
  }

  /// Firestore `serviceCategories` 항목에서 선택 키 복구(불완전한 저장 보정 포함).
  static Set<String> selectionKeysFromFirestore({
    dynamic serviceCategories,
  }) {
    final keys = <String>{};
    if (serviceCategories is List<dynamic>) {
      for (final item in serviceCategories) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final m = _readString(map['main']);
        final sub = _readString(map['sub']);
        if (m == null || sub == null) continue;
        if (_isValidCombo(m, sub)) {
          keys.add(selectionKey(m, sub));
        }
      }
    }
    return normalizeMirroredSelections(keys);
  }

  /// 한쪽 외장/필름에만 PPF·랩핑이 있으면 다른 쪽에도 맞춤(과거 저장 호환).
  static Set<String> normalizeMirroredSelections(Set<String> keys) {
    var current = {...keys};
    bool changed = true;
    while (changed) {
      changed = false;
      final copy = {...current};
      for (final k in copy) {
        final parsed = splitSelectionKey(k);
        if (parsed == null) continue;
        if (!mirrorsAcrossExteriorAndFilm(parsed.sub)) continue;
        final twin = pairedExteriorFilmMain(parsed.main);
        if (twin != null &&
            servicesByMain[twin]?.contains(parsed.sub) == true) {
          final other = selectionKey(twin, parsed.sub);
          if (!current.contains(other)) {
            current.add(other);
            changed = true;
          }
        }
      }
    }
    return current;
  }

  static String? _readString(Object? value) {
    if (value is String) return value.trim().isEmpty ? null : value.trim();
    return null;
  }

  static bool _isValidCombo(String main, String sub) =>
      servicesByMain[main]?.contains(sub) ?? false;
}
