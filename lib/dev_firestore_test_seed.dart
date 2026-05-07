import 'package:cloud_firestore/cloud_firestore.dart';

import 'region_normalize.dart';
import 'service_category_catalog.dart';

/// 개발·테스트용: 고정 문서 ID로 [users] 5건 + 매칭 테스트 8건, [collaborationRequests] 5건을
/// 덮어써서 동일 버튼으로도 중복 없이 갱신할 수 있습니다.
Future<void> seedDevFirestoreTestData() async {
  final db = FirebaseFirestore.instance;
  final batch = db.batch();
  final ts = FieldValue.serverTimestamp();

  final film = ServiceCategoryCatalog.filmMainTitle;

  Map<String, Object?> collaborationRegionPack(String zone) {
    final trimmed = zone.trim();
    final p = PoRegionFields.fromRegionFull(trimmed);
    return <String, Object?>{
      'location': p.regionFull.isNotEmpty ? p.regionFull : trimmed,
      ...poRegionCollaborationFirestoreMap(p),
    };
  }

  void setUser(String docId, Map<String, Object?> fields) {
    batch.set(
      db.collection('users').doc(docId),
      <String, Object?>{
        'uid': docId,
        ...fields,
        'createdAt': ts,
        'updatedAt': ts,
      },
    );
  }

  void setRequest(String docId, Map<String, Object?> fields) {
    batch.set(
      db.collection('collaborationRequests').doc(docId),
      <String, Object?>{
        'requestId': docId,
        ...fields,
        'createdAt': ts,
        'updatedAt': ts,
      },
    );
  }

  setUser('test_user_1', <String, Object?>{
    'displayName': '강남 PPF랩핑',
    'businessName': '강남 PPF랩핑',
    'shopName': '강남 PPF랩핑 1호점',
    'ownerName': '김강남',
    'region': '서울 강남구',
    'regions': <String>['서울 강남구', '서울'],
    'mainCategories': <String>[film],
    'searchCategories': <String>['PPF', '랩핑'],
    'primaryCategory': 'PPF · 랩핑',
    'priceRange': '중',
    'responseSpeed': '빠름',
    'isAvailable': true,
    'phoneNumber': '02-1234-0001',
    'storePhone': '010-1001-0001',
  });

  setUser('test_user_2', <String, Object?>{
    'displayName': '수원 틴팅마스터',
    'businessName': '수원 틴팅마스터',
    'shopName': '수원 틴팅마스터',
    'ownerName': '이수원',
    'region': '경기 수원시',
    'regions': <String>['경기 수원시', '경기'],
    'mainCategories': <String>[film],
    'searchCategories': <String>['썬팅 (틴팅)'],
    'primaryCategory': '썬팅 (틴팅)',
    'priceRange': '저',
    'responseSpeed': '보통',
    'isAvailable': true,
    'phoneNumber': '031-123-0002',
    'storePhone': '010-1002-0002',
  });

  setUser('test_user_3', <String, Object?>{
    'displayName': '인천 블랙박스프로',
    'businessName': '인천 블랙박스프로',
    'shopName': '블랙박스프로 인천센터',
    'ownerName': '박인천',
    'region': '인천',
    'regions': <String>['인천', '인천광역시'],
    'mainCategories': <String>['전장 시공'],
    'searchCategories': <String>['블랙박스', '후방카메라'],
    'primaryCategory': '블랙박스 · 전장',
    'priceRange': '중',
    'responseSpeed': '매우 빠름',
    'isAvailable': true,
    'phoneNumber': '032-234-0003',
    'storePhone': '010-1003-0003',
  });

  setUser('test_user_4', <String, Object?>{
    'displayName': '부산 디테일링샵',
    'businessName': '부산 디테일링샵',
    'shopName': '해운대 디테일링샵',
    'ownerName': '최부산',
    'region': '부산 해운대구',
    'regions': <String>['부산 해운대구', '부산'],
    'mainCategories': <String>['실내 시공'],
    'searchCategories': <String>['실내 크리닝 / 디테일링'],
    'primaryCategory': '실내 크리닝 / 디테일링',
    'priceRange': '중',
    'responseSpeed': '보통',
    'isAvailable': false,
    'phoneNumber': '051-345-0004',
    'storePhone': '010-1004-0004',
  });

  setUser('test_user_5', <String, Object?>{
    'displayName': '대전 정비파트너',
    'businessName': '대전 정비파트너',
    'shopName': '대전 정비파트너',
    'ownerName': '정대전',
    'region': '대전',
    'regions': <String>['대전', '대전광역시'],
    'mainCategories': <String>['정비 & 경정비'],
    'searchCategories': <String>['엔진오일', '배터리'],
    'primaryCategory': '정비 · 경정비',
    'priceRange': '저',
    'responseSpeed': '빠름',
    'isAvailable': true,
    'phoneNumber': '042-456-0005',
    'storePhone': '010-1005-0005',
  });

  setRequest('test_request_1', <String, Object?>{
    ...collaborationRegionPack('서울 강남구 역삼동'),
    'ownerUid': 'dev_collab_owner_1',
    'ownerEmail': 'dev_collab_1@example.test',
    'title': 'PPF + 랩핑 협업 구함',
    'workType': 'PPF + 랩핑 현장 협업',
    'mainCategory': film,
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': film, 'sub': 'PPF'},
      <String, String>{'main': film, 'sub': '랩핑'},
    ],
    'date': '협의 · 급건 우대',
    'deadlineType': 'date',
    'deadline': Timestamp.fromDate(DateTime(2026, 12, 15)),
    'deadlineText': '2026-12-15',
    'description':
        '필름 시공(PPF·랩핑) 경험 있는 분과 현장 공유·일정 조율 가능합니다.',
    'status': 'open',
  });

  setRequest('test_request_2', <String, Object?>{
    ...collaborationRegionPack('경기 수원시'),
    'ownerUid': 'dev_collab_owner_2',
    'ownerEmail': 'dev_collab_2@example.test',
    'title': '틴팅 시공 인력 구합니다',
    'workType': '썬팅 시공 인력',
    'mainCategory': film,
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': film, 'sub': '썬팅 (틴팅)'},
    ],
    'date': '내주 중',
    'deadlineType': 'always',
    'deadlineText': '수시모집중',
    'description': '필름 시공 라인에서 썬팅 전문으로 같이 하실 분 찾습니다.',
    'status': '모집중',
  });

  setRequest('test_request_3', <String, Object?>{
    ...collaborationRegionPack('인천'),
    'ownerUid': 'dev_collab_owner_3',
    'ownerEmail': 'dev_collab_3@example.test',
    'title': '블랙박스 설치 협업',
    'workType': '블랙박스 설치',
    'mainCategory': '전장 시공',
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '전장 시공', 'sub': '블랙박스'},
    ],
    'date': '주말 가능',
    'deadlineType': 'date',
    'deadline': Timestamp.fromDate(DateTime(2026, 6, 1)),
    'deadlineText': '2026-06-01',
    'description': '전장 시공 업체와 블랙박스 동선 정리·설치 협업 요청드립니다.',
    'status': 'open',
  });

  setRequest('test_request_4', <String, Object?>{
    ...collaborationRegionPack('부산 해운대구'),
    'ownerUid': 'dev_collab_owner_4',
    'ownerEmail': 'dev_collab_4@example.test',
    'title': '실내 크리닝 긴급 협업',
    'workType': '실내 크리닝 / 디테일링',
    'mainCategory': '실내 시공',
    'serviceCategories': <Map<String, String>>[
      <String, String>{
        'main': '실내 시공',
        'sub': '실내 크리닝 / 디테일링',
      },
    ],
    'date': '당일·익일',
    'description':
        '실내 시공 약속이 몰려 인력 한 분만 도와주실 분 구합니다. 디테일링 경험자 우대.',
    'status': '모집중',
  });

  setRequest('test_request_5', <String, Object?>{
    ...collaborationRegionPack('대전'),
    'ownerUid': 'dev_collab_owner_5',
    'ownerEmail': 'dev_collab_5@example.test',
    'title': '엔진오일 출장 가능 업체 구함',
    'workType': '엔진오일 출장',
    'mainCategory': '정비 & 경정비',
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '정비 & 경정비', 'sub': '엔진오일'},
    ],
    'date': '평일 오전',
    'description': '정비·경정비 반경 내 엔진오일 출장 가능 업체 연락 주세요.',
    'status': 'open',
  });

  /// AI 매칭·`calculateScore` 테스트용 업체 (고정 ID).
  setUser('test_match_user_1', <String, Object?>{
    'displayName': '강남 PPF 랩핑 전문',
    'businessName': '강남 PPF 랩핑 전문',
    'shopName': '강남 PPF 랩핑 전문 본점',
    'ownerName': '김강남',
    'region': '서울 강남구',
    'regions': <String>['서울', '서울 강남구', '강남'],
    'mainCategories': <String>['외장 시공', '필름 시공'],
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '외장 시공', 'sub': 'PPF'},
      <String, String>{'main': '필름 시공', 'sub': 'PPF'},
      <String, String>{'main': '외장 시공', 'sub': '랩핑'},
      <String, String>{'main': '필름 시공', 'sub': '랩핑'},
    ],
    'searchCategories': <String>['PPF', '랩핑'],
    'primaryCategory': 'PPF',
    'priceRange': '중',
    'responseSpeed': '빠름',
    'isAvailable': true,
    'averageRating': 9.2,
    'phoneNumber': '02-9101-0001',
    'storePhone': '010-9101-1001',
  });

  setUser('test_match_user_2', <String, Object?>{
    'displayName': '서초 랩핑 파트너',
    'businessName': '서초 랩핑 파트너',
    'shopName': '서초 랩핑 파트너 본점',
    'ownerName': '이서초',
    'region': '서울 서초구',
    'regions': <String>['서울', '서울 서초구', '서초', '강남'],
    'mainCategories': <String>['외장 시공', '필름 시공'],
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '외장 시공', 'sub': '랩핑'},
      <String, String>{'main': '필름 시공', 'sub': '랩핑'},
    ],
    'searchCategories': <String>['랩핑'],
    'primaryCategory': '랩핑',
    'priceRange': '저',
    'responseSpeed': '빠름',
    'isAvailable': true,
    'averageRating': 8.7,
    'phoneNumber': '02-9102-0002',
    'storePhone': '010-9102-1002',
  });

  setUser('test_match_user_3', <String, Object?>{
    'displayName': '강남 틴팅 PPF샵',
    'businessName': '강남 틴팅 PPF샵',
    'shopName': '강남 틴팅 PPF샵 본점',
    'ownerName': '박틴팅',
    'region': '서울 강남구',
    'regions': <String>['서울', '서울 강남구', '강남'],
    'mainCategories': <String>['필름 시공'],
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '필름 시공', 'sub': '썬팅 (틴팅)'},
      <String, String>{'main': '필름 시공', 'sub': 'PPF'},
    ],
    'searchCategories': <String>['썬팅 (틴팅)', 'PPF'],
    'primaryCategory': '썬팅 (틴팅)',
    'priceRange': '중',
    'responseSpeed': '보통',
    'isAvailable': true,
    'averageRating': 8.3,
    'phoneNumber': '02-9103-0003',
    'storePhone': '010-9103-1003',
  });

  setUser('test_match_user_4', <String, Object?>{
    'displayName': '송파 PPF 긴급출장',
    'businessName': '송파 PPF 긴급출장',
    'shopName': '송파 PPF 긴급출장 본점',
    'ownerName': '최송파',
    'region': '서울 송파구',
    'regions': <String>['서울', '서울 송파구', '송파', '강남'],
    'mainCategories': <String>['외장 시공', '필름 시공'],
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '외장 시공', 'sub': 'PPF'},
      <String, String>{'main': '필름 시공', 'sub': 'PPF'},
    ],
    'searchCategories': <String>['PPF'],
    'primaryCategory': 'PPF',
    'priceRange': '고',
    'responseSpeed': '빠름',
    'isAvailable': true,
    'averageRating': 9.0,
    'phoneNumber': '02-9104-0004',
    'storePhone': '010-9104-1004',
  });

  setUser('test_match_user_5', <String, Object?>{
    'displayName': '강남 광택 코팅샵',
    'businessName': '강남 광택 코팅샵',
    'shopName': '강남 광택 코팅샵 본점',
    'ownerName': '정광택',
    'region': '서울 강남구',
    'regions': <String>['서울', '서울 강남구', '강남'],
    'mainCategories': <String>['외장 시공'],
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '외장 시공', 'sub': '광택 / 폴리싱'},
      <String, String>{
        'main': '외장 시공',
        'sub': '유리막 코팅 / 세라믹 코팅',
      },
    ],
    'searchCategories': <String>[
      '광택 / 폴리싱',
      '유리막 코팅 / 세라믹 코팅',
    ],
    'primaryCategory': '광택 / 폴리싱',
    'priceRange': '중',
    'responseSpeed': '빠름',
    'isAvailable': true,
    'averageRating': 8.8,
    'phoneNumber': '02-9105-0005',
    'storePhone': '010-9105-1005',
  });

  setUser('test_match_user_6', <String, Object?>{
    'displayName': '강남 블랙박스 전장',
    'businessName': '강남 블랙박스 전장',
    'shopName': '강남 블랙박스 전장 본점',
    'ownerName': '한전장',
    'region': '서울 강남구',
    'regions': <String>['서울', '서울 강남구', '강남'],
    'mainCategories': <String>['전장 시공'],
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '전장 시공', 'sub': '블랙박스'},
      <String, String>{'main': '전장 시공', 'sub': '후방카메라'},
    ],
    'searchCategories': <String>['블랙박스', '후방카메라'],
    'primaryCategory': '블랙박스',
    'priceRange': '저',
    'responseSpeed': '빠름',
    'isAvailable': true,
    'averageRating': 8.5,
    'phoneNumber': '02-9106-0006',
    'storePhone': '010-9106-1006',
  });

  setUser('test_match_user_7', <String, Object?>{
    'displayName': '성남 랩핑 PPF 협업',
    'businessName': '성남 랩핑 PPF 협업',
    'shopName': '성남 랩핑 PPF 협업 본점',
    'ownerName': '조성남',
    'region': '경기 성남시',
    'regions': <String>['경기', '성남', '분당', '서울', '강남'],
    'mainCategories': <String>['외장 시공', '필름 시공'],
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '외장 시공', 'sub': 'PPF'},
      <String, String>{'main': '필름 시공', 'sub': 'PPF'},
      <String, String>{'main': '외장 시공', 'sub': '랩핑'},
      <String, String>{'main': '필름 시공', 'sub': '랩핑'},
    ],
    'searchCategories': <String>['PPF', '랩핑'],
    'primaryCategory': '랩핑',
    'priceRange': '저',
    'responseSpeed': '보통',
    'isAvailable': true,
    'averageRating': 8.1,
    'phoneNumber': '031-9107-0007',
    'storePhone': '010-9107-1007',
  });

  setUser('test_match_user_8', <String, Object?>{
    'displayName': '강남 PPF 가능하지만 비활성',
    'businessName': '강남 PPF 가능하지만 비활성',
    'shopName': '강남 PPF 가능하지만 비활성 본점',
    'ownerName': '윤비활',
    'region': '서울 강남구',
    'regions': <String>['서울', '서울 강남구', '강남'],
    'mainCategories': <String>['외장 시공', '필름 시공'],
    'serviceCategories': <Map<String, String>>[
      <String, String>{'main': '외장 시공', 'sub': 'PPF'},
      <String, String>{'main': '필름 시공', 'sub': 'PPF'},
    ],
    'searchCategories': <String>['PPF'],
    'primaryCategory': 'PPF',
    'priceRange': '저',
    'responseSpeed': '빠름',
    'isAvailable': false,
    'averageRating': 9.5,
    'phoneNumber': '02-9108-0008',
    'storePhone': '010-9108-1008',
  });

  await batch.commit();
}
