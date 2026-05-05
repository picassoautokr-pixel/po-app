import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dev_firestore_test_seed.dart';
import 'firebase_options.dart';
import 'region_normalize.dart';
import 'service_category_catalog.dart';

part 'tabs/home_tab_part.dart';
part 'tabs/requests_tab_part.dart';
part 'tabs/chat_tab_part.dart';
part 'tabs/favorite_partners_tab_part.dart';
part 'tabs/my_page_tab_part.dart';
part 'tabs/feed_shell_part.dart';
part 'tabs/collaboration_feed_tab_part.dart';
part 'notification_screen_part.dart';

/// 반투명 딤 위에 로딩을 약 1초 표시한 뒤 [action]을 실행합니다.
Future<void> runWithBriefLoading(
  BuildContext context,
  VoidCallback action,
) async {
  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (ctx) => Center(
      child: CircularProgressIndicator(
        color: Theme.of(ctx).colorScheme.primary,
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 1000));
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (!context.mounted) return;
  action();
}

const Duration _kPoNavPushDuration = Duration(milliseconds: 300);
const Duration _kPoNavPopDuration = Duration(milliseconds: 260);

/// 서브 화면으로 들어갈 때 미세 슬라이드 + 페이드.
Route<T> poSmoothPushRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: page.runtimeType.toString()),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: _kPoNavPushDuration,
    reverseTransitionDuration: _kPoNavPopDuration,
    opaque: true,
    barrierDismissible: false,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position:
              Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// 로그인 직후 등 전체 교체: 페이드만 (자연스러운 홈 진입).
Route<T> poFadeReplaceRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: page.runtimeType.toString()),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    opaque: true,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

/// Google 계정으로 Firebase 인증 후 성공 시에만 [MainShell]로 이동합니다.
///
/// 이전 세션 토큰이 남아 `access_token audience is not for this project` 가 나는 경우를
/// 줄이기 위해 매번 [GoogleSignIn.signOut] 후 [GoogleSignIn.disconnect]를 시도합니다.
Future<void> signInWithGoogle(BuildContext context) async {
  final GoogleSignIn googleSignIn = GoogleSignIn();

  await googleSignIn.signOut();
  try {
    await googleSignIn.disconnect();
  } catch (e, st) {
    // 연결 해제 실패는 무시해도 되는 경우가 많음. 원인 파악용으로만 출력합니다.
    // ignore: avoid_print
    print('GoogleSignIn.disconnect: $e\n$st');
  }

  try {
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 취소되었습니다.')),
      );
      return;
    }

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await FirebaseAuth.instance.signInWithCredential(credential);

    if (!context.mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // ignore: avoid_print
      print('uid: ${user.uid}');
      // ignore: avoid_print
      print('email: ${user.email}');
      // ignore: avoid_print
      print('displayName: ${user.displayName}');
      // ignore: avoid_print
      print('photoURL: ${user.photoURL}');
    }

    Navigator.of(context).pushReplacement(
      poFadeReplaceRoute<void>(const MainShell()),
    );
  } on PlatformException catch (e, st) {
    if (e.code == GoogleSignIn.kSignInCanceledError) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 취소되었습니다.')),
      );
      return;
    }
    // ignore: avoid_print
    print('$e\n$st');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  } catch (e, st) {
    // ignore: avoid_print
    print('$e\n$st');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString())),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app();
    }
  } on FirebaseException catch (e, stackTrace) {
    if (e.code == 'duplicate-app') {
      Firebase.app();
    } else {
      debugPrint('Firebase 초기화 실패: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  } catch (e, stackTrace) {
    debugPrint('Firebase 초기화 실패: $e');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(const MyApp());
}

/// 피오(P.O) — 시공·협업 매칭 데모
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color _accent = Color(0xFF007AFF);

  /// 런처·OS에 표시되는 앱 이름
  static const String applicationName = '피오 (P.O)';

  /// 각 화면 AppBar 등 상단 제목 통일
  static const String appBarTitle = '피오';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: applicationName,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accent,
          brightness: Brightness.light,
          primary: _accent,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  static const Color _accent = Color(0xFF007AFF);
  static const double _btnHeight = 54;
  static const double _btnRadius = 14;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  MyApp.appBarTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: _accent,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '시공·협업 매칭',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        letterSpacing: -0.2,
                      ),
                ),
                const SizedBox(height: 40),
                Text(
                  '가까운 업체 찾기부터 협업까지 한곳에서',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                        color: Colors.black87,
                        fontSize: 17,
                      ),
                ),
                const SizedBox(height: 48),
                _SocialLoginButton(
                  label: '네이버로 로그인',
                  backgroundColor: const Color(0xFF03C75A),
                  foregroundColor: Colors.white,
                  onPressed: () {
                    // ignore: avoid_print
                    print('네이버로 로그인');
                  },
                ),
                const SizedBox(height: 12),
                _SocialLoginButton(
                  label: '카카오톡으로 로그인',
                  backgroundColor: const Color(0xFFFEE500),
                  foregroundColor: const Color(0xFF191919),
                  onPressed: () {
                    // ignore: avoid_print
                    print('카카오톡으로 로그인');
                  },
                ),
                const SizedBox(height: 12),
                _SocialLoginButton(
                  label: '구글로 로그인',
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  borderSide: BorderSide(color: Colors.grey.shade400, width: 1),
                  onPressed: () => signInWithGoogle(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [MainShell]이 마운트되어 있을 때 홈 탭(0)으로 바꿉니다. (협업 등록 후 복귀용)
class _MainShellTabHost {
  static _MainShellState? _live;

  static void register(_MainShellState s) => _live = s;

  static void unregister(_MainShellState s) {
    if (identical(_live, s)) _live = null;
  }

  static void goHomeTab() {
    final live = _live;
    if (live == null || !live.mounted) return;
    live.setTabIndex(0);
  }
}

String _collaborationRequestString(dynamic v) =>
    v is String ? v.trim() : '';

/// collaborationRequests.status → 카드 라벨
String collaborationDisplayStatusKo(String raw) {
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'open':
      return '모집중';
    case 'closed':
      return '마감';
    case 'matched':
      return '채택됨';
    case 'in_progress':
      return '진행중';
    case 'cancelled':
      return '취소';
    case 'completed':
    case 'complete':
    case 'done':
      return '완료';
    default:
      return raw.trim().isEmpty ? '모집중' : raw.trim();
  }
}

/// collaborationRequests/.../applications 의 status 표시용.
String collaborationApplicationStatusKo(String raw) {
  final s = raw.trim().toLowerCase();
  switch (s) {
    case 'pending':
      return '검토중';
    case 'accepted':
      return '채택';
    case 'rejected':
      return '거절';
    default:
      return raw.trim().isEmpty ? '미등록' : raw.trim();
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

List<String> collaborationApplicantSearchCategoriesList(
  Map<String, dynamic>? d,
) {
  if (d == null) return [];
  final raw = d['applicantSearchCategories'];
  if (raw is! List) return [];
  return raw
      .map((dynamic e) => e is String ? e.trim() : '')
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
}

int? collaborationParseProposedPrice(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

String collaborationFormatProposedPrice(dynamic v) {
  if (v == null) return '미등록';
  if (v is num) {
    if (v == v.roundToDouble()) return '${v.toInt()}';
    return v.toString();
  }
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return '미등록';
    final n = int.tryParse(t.replaceAll(RegExp(r'[^\d]'), ''));
    if (n != null) return '$n';
    return t;
  }
  return '미등록';
}

/// 리뷰 `scores` 맵에 사용하는 키 (EvaluationScreen과 동일).
const List<String> collaborationReviewScoreKeys = <String>[
  'construction_finish',
  'construction_speed',
  'after_service',
  'response_speed',
  'kindness',
  'value_for_money',
];

const Map<String, String> collaborationReviewScoreLabelsKo = {
  'construction_finish': '시공 마감',
  'construction_speed': '시공 속도',
  'after_service': 'A/S',
  'response_speed': '응답 속도',
  'kindness': '친절함',
  'value_for_money': '가성비',
};

String collaborationReviewDocId(String reviewerUid, String requestId) {
  final r = reviewerUid.trim();
  final q = requestId.trim();
  if (r.isEmpty || q.isEmpty) return '';
  final safeRid = q.replaceAll(RegExp(r'[/\s]'), '_');
  return '${r}_$safeRid';
}

/// `users/{uid}/reviews` 기준으로 [averageRating]을 갱신합니다.
Future<void> collaborationRecomputeUserAverageRating(String targetUid) async {
  final t = targetUid.trim();
  if (t.isEmpty) return;

  final snap = await FirebaseFirestore.instance
      .collection('users')
      .doc(t)
      .collection('reviews')
      .get();

  if (snap.docs.isEmpty) {
    await FirebaseFirestore.instance.collection('users').doc(t).set(
      <String, Object?>{'averageRating': FieldValue.delete()},
      SetOptions(merge: true),
    );
    return;
  }

  final keys = collaborationReviewScoreKeys;
  var sumMeans = 0.0;
  var reviewCount = 0;

  for (final doc in snap.docs) {
    final d = doc.data();
    final scoresRaw = d['scores'];
    if (scoresRaw is! Map) continue;
    final sm = Map<String, dynamic>.from(scoresRaw);
    var catSum = 0.0;
    var catN = 0;
    for (final k in keys) {
      final v = sm[k];
      if (v is num) {
        catSum += v.toDouble();
        catN++;
      }
    }
    if (catN > 0) {
      sumMeans += catSum / catN;
      reviewCount++;
    }
  }

  if (reviewCount == 0) {
    await FirebaseFirestore.instance.collection('users').doc(t).set(
      <String, Object?>{'averageRating': FieldValue.delete()},
      SetOptions(merge: true),
    );
    return;
  }

  final avg = sumMeans / reviewCount;
  final rounded = (avg * 100).round() / 100.0;

  await FirebaseFirestore.instance.collection('users').doc(t).set(
    <String, Object?>{'averageRating': rounded},
    SetOptions(merge: true),
  );
}

/// 채팅 메타 업데이트 (messages 서브컬렉션과 동일 doc id 유지).
Future<void> collaborationTouchChatRoomSummary({
  required String chatId,
  required String myUid,
  required String partnerUid,
  required String requestId,
  required String requestTitle,
  required String lastMessagePreview,
}) async {
  final rid = requestId.trim();
  final pu = partnerUid.trim();
  if (chatId.trim().isEmpty || myUid.trim().isEmpty || pu.isEmpty) return;

  await FirebaseFirestore.instance.collection('chats').doc(chatId).set(
    <String, Object?>{
      'chatId': chatId.trim(),
      'participants': <String>[myUid.trim(), pu],
      'requestId': rid,
      'partnerUid': pu,
      'requestTitle':
          requestTitle.trim().isEmpty ? '채팅' : requestTitle.trim(),
      'lastMessage': lastMessagePreview,
      'updatedAt': FieldValue.serverTimestamp(),
      'hasMessages': true,
      'createdByCall': false,
    },
    SetOptions(merge: true),
  );
}

Future<void> collaborationEnsureChatRoomShell({
  required String chatId,
  required String myUid,
  required String partnerUid,
  required String requestId,
  required String requestTitle,
}) async {
  final pu = partnerUid.trim();
  if (chatId.trim().isEmpty || myUid.trim().isEmpty || pu.isEmpty) return;

  await FirebaseFirestore.instance.collection('chats').doc(chatId).set(
    <String, Object?>{
      'chatId': chatId.trim(),
      'participants': <String>[myUid.trim(), pu],
      'requestId': requestId.trim(),
      'partnerUid': pu,
      'requestTitle':
          requestTitle.trim().isEmpty ? '채팅' : requestTitle.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'createdByCall': false,
    },
    SetOptions(merge: true),
  );
}

String _matchingFieldStr(dynamic v) =>
    v is String ? v.trim() : '';

String _matchingUserDisplayName(Map<String, dynamic> d) {
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

String _matchingUserRegionsLine(Map<String, dynamic> d) {
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
    final s = _matchingFieldStr(d[key]);
    if (s.isNotEmpty) return s;
  }
  return '이름 미등록 업체';
}

/// 홈·업체 상세 공통: 전화 (storePhone → phoneNumber → businessPhone).
String poUserPrimaryPhone(Map<String, dynamic> d) {
  for (final key in <String>['storePhone', 'phoneNumber', 'businessPhone']) {
    final s = _matchingFieldStr(d[key]);
    if (s.isNotEmpty) return s;
  }
  return '';
}

String _companyProfileFieldOrMissing(Map<String, dynamic> d, String key) {
  final v = d[key];
  if (v == null) return '미등록';
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? '미등록' : t;
  }
  if (v is bool || v is num) {
    return v.toString();
  }
  return '미등록';
}

String _companyProfileListLine(Map<String, dynamic> d, String key) {
  final v = d[key];
  if (v is! List || v.isEmpty) return '미등록';
  final parts = <String>[];
  for (final e in v) {
    if (e is String) {
      final t = e.trim();
      if (t.isNotEmpty) parts.add(t);
    }
  }
  return parts.isEmpty ? '미등록' : parts.join(' · ');
}

String _companyProfileRegionsLine(Map<String, dynamic> d) {
  final line = _matchingUserRegionsLine(d);
  if (line == '-' || line.trim().isEmpty) return '미등록';
  return line;
}

String _companyProfileLicenseStatus(Map<String, dynamic> d) {
  final v = d['businessLicenseStatus'];
  if (v == null) return '미등록';
  if (v is bool) {
    return v ? '인증' : '미인증';
  }
  if (v is String) {
    final t = v.trim();
    return t.isEmpty ? '미등록' : t;
  }
  return v.toString();
}

String _finishDetailFieldStr(dynamic v) =>
    v is String ? v.trim() : '';

void _showFinishDetailImagePreview(BuildContext context, String? rawUrl) {
  final url = _finishDetailFieldStr(rawUrl);
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

/// 업체 프로필: `users/{partnerUid}/finishDetails` — 인덱스 없이 스냅샷 후 클라이언트 정렬.
class _CompanyFinishDetailsSection extends StatelessWidget {
  const _CompanyFinishDetailsSection({required this.partnerUid});

  final String partnerUid;

  static const Color _accent = Color(0xFF007AFF);

  int _createdCompare(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ta = a.data()['createdAt'];
    final tb = b.data()['createdAt'];
    final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
    final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
    return db.compareTo(da);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(partnerUid)
          .collection('finishDetails')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text(
              '마감 디테일을 불러오지 못했습니다.',
              style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
            ),
          );
        }

        final rawDocs = snapshot.data?.docs ?? [];
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          rawDocs,
        )..sort(_createdCompare);

        if (docs.isEmpty) {
          return Text(
            '등록된 마감 디테일이 없습니다.',
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
              height: 1.45,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < docs.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _FinishDetailCard(
                data: docs[i].data(),
                accent: _accent,
                textTheme: textTheme,
                onImageTap: (url) =>
                    _showFinishDetailImagePreview(context, url),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FinishDetailCard extends StatelessWidget {
  const _FinishDetailCard({
    required this.data,
    required this.accent,
    required this.textTheme,
    required this.onImageTap,
  });

  final Map<String, dynamic> data;
  final Color accent;
  final TextTheme textTheme;
  final void Function(String? url) onImageTap;

  @override
  Widget build(BuildContext context) {
    final title = _finishDetailFieldStr(data['title']);
    final description = _finishDetailFieldStr(data['description']);
    final category = _finishDetailFieldStr(data['category']);
    final imageUrl = _finishDetailFieldStr(data['imageUrl']);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            child: Material(
              color: Colors.grey.shade200,
              child: InkWell(
                onTap: imageUrl.isEmpty ? null : () => onImageTap(imageUrl),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: imageUrl.isEmpty
                      ? Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            size: 40,
                            color: Colors.grey.shade500,
                          ),
                        )
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 32,
                                height: 32,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 36,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  )
                else
                  Text(
                    '제목 없음',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade800,
                      height: 1.45,
                    ),
                  ),
                ],
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      category,
                      style: textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

List<String> _matchingUserSearchCategories(Map<String, dynamic> d) {
  final raw = d['searchCategories'];
  if (raw is! List<dynamic>) return [];
  return raw
      .whereType<String>()
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList(growable: false);
}

bool _matchingUserAvailable(Map<String, dynamic> d) =>
    d['isAvailable'] == true;

/// AI 추천 매칭: 업체 문서 + 계산된 점수.
class CollaborationMatchingCandidate {
  CollaborationMatchingCandidate({
    required this.doc,
    required this.score,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int score;
}

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
  if (u.regions.isEmpty || r.regions.isEmpty) return false;
  final rs = r.regions.toSet();
  return u.regions.any(rs.contains);
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

/// 요청([request]) 대비 업체([user]) AI 추천 점수 (높을수록 적합).
int calculateScore(
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

String _matchingFormatAverageRatingDisplay(Map<String, dynamic> user) {
  final v = user['averageRating'];
  if (v is num) return v.toStringAsFixed(1);
  return '—';
}

/// [workType]이 `searchCategories`에 포함된 업체만 가져온 뒤 [calculateScore]로 정렬합니다.
Future<List<CollaborationMatchingCandidate>> _fetchCollaborationMatchingCandidates({
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
          score: calculateScore(d.data(), requestData),
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
    return _matchingUserDisplayName(a.doc.data()).toLowerCase().compareTo(
          _matchingUserDisplayName(b.doc.data()).toLowerCase(),
        );
  });

  const topN = 5;
  if (filtered.length <= topN) return filtered;
  return filtered.sublist(0, topN);
}

/// 협업 요청 카드·상세용 표시 제목 (`title` 우선, 구 데이터는 `workType`).
String _collaborationDisplayTitle(Map<String, dynamic> d) {
  final t = _collaborationRequestString(d['title']);
  if (t.isNotEmpty) return t;
  final w = _collaborationRequestString(d['workType']);
  if (w.isNotEmpty) return w;
  return '협업 요청';
}

String _collaborationReqMissingStr(Map<String, dynamic>? d, String key) {
  if (d == null) return '미등록';
  final v = d[key];
  if (v == null) return '미등록';
  if (v is String) return v.trim().isEmpty ? '미등록' : v.trim();
  if (v is bool) return v ? '예' : '아니오';
  if (v is num) return v.toString();
  return '미등록';
}

String _collaborationReqOnSiteLabel(Map<String, dynamic>? d) {
  if (d == null) return '미등록';
  final v = d['isOnSite'];
  if (v == null) return '미등록';
  if (v is bool) return v ? '출장 시공' : '방문 시공';
  return '미등록';
}

String _collaborationReqServiceCategoriesLine(Map<String, dynamic>? d) {
  if (d == null) return '미등록';
  final raw = d['serviceCategories'];
  if (raw is! List || raw.isEmpty) return '미등록';
  final out = <String>[];
  for (final e in raw) {
    if (e is String) {
      final t = e.trim();
      if (t.isNotEmpty) out.add(t);
    } else if (e is Map) {
      final m = Map<String, dynamic>.from(e);
      final sub = _matchingFieldStr(m['sub']);
      final main = _matchingFieldStr(m['main']);
      if (sub.isNotEmpty) {
        out.add(main.isNotEmpty ? '$main · $sub' : sub);
      }
    }
  }
  return out.isEmpty ? '미등록' : out.join(' · ');
}

String _collaborationReqStatusLine(Map<String, dynamic>? d) {
  if (d == null) return '미등록';
  final raw = _collaborationRequestString(d['status']);
  if (raw.isEmpty) return '미등록';
  return collaborationDisplayStatusKo(raw);
}

bool _collaborationReqIsUrgent(Map<String, dynamic>? d) =>
    d != null && d['isUrgent'] == true;

/// 작성자 여부에 따라 소유자 관리 화면 또는 파트너 상세 화면으로 이동합니다.
void _openCollaborationRequestDetailFromDoc(
  BuildContext context,
  DocumentSnapshot<Map<String, dynamic>> doc,
) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
    return;
  }

  final d = doc.data();
  if (d == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('공고 정보를 찾을 수 없습니다.')),
    );
    return;
  }
  final ownerUidFs = _collaborationRequestString(d['ownerUid']);
  final isOwner = ownerUidFs.isNotEmpty && ownerUidFs == user.uid;
  final ownerEmail = _collaborationRequestString(d['ownerEmail']);

  if (!context.mounted) return;

  if (isOwner) {
    Navigator.of(context).push(poSmoothPushRoute<void>(
      OwnerRequestDetailScreen(requestId: doc.id),
    ));
  } else {
    Navigator.of(context).push(poSmoothPushRoute<void>(
      PartnerRequestDetailScreen(
        requestId: doc.id,
        ownerUid: ownerUidFs,
        ownerEmailFromRequest:
            ownerEmail.isEmpty ? null : ownerEmail,
      ),
    ));
  }
}

void _openPoNotifications(BuildContext context) {
  Navigator.of(
    context,
  ).push(poSmoothPushRoute<void>(const NotificationScreen()));
}

Widget _collaborationDetailLabeledBlock({
  required TextTheme textTheme,
  required String label,
  required String body,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: Colors.grey.shade600,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        body,
        style: textTheme.bodyMedium?.copyWith(
          height: 1.45,
          color: Colors.black87,
        ),
      ),
    ],
  );
}

Widget _collaborationRequestDetailFieldsCard({
  required TextTheme textTheme,
  required Map<String, dynamic>? data,
  required bool showStatus,
  String? statusOverride,
}) {
  final titleText = data == null
      ? '미등록'
      : (_collaborationRequestString(data['title']).isNotEmpty
          ? _collaborationRequestString(data['title'])
          : _collaborationDisplayTitle(data));
  final isUrgent = _collaborationReqIsUrgent(data);
  final statusBody = statusOverride ??
      (showStatus ? _collaborationReqStatusLine(data) : null);

  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  titleText,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                    height: 1.3,
                  ),
                ),
              ),
              if (isUrgent)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    '긴급',
                    style: textTheme.labelSmall?.copyWith(
                      color: Colors.red.shade800,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '메인 카테고리',
            body: _collaborationReqMissingStr(data, 'mainCategory'),
          ),
          const SizedBox(height: 14),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '세부 시공분야',
            body: _collaborationReqServiceCategoriesLine(data),
          ),
          const SizedBox(height: 14),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '지역',
            body: _collaborationReqMissingStr(data, 'location'),
          ),
          const SizedBox(height: 14),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '일정',
            body: _collaborationReqMissingStr(data, 'date'),
          ),
          const SizedBox(height: 14),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '출장 여부',
            body: _collaborationReqOnSiteLabel(data),
          ),
          const SizedBox(height: 14),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '자재 조건',
            body: _collaborationReqMissingStr(data, 'materialCondition'),
          ),
          const SizedBox(height: 14),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '희망 금액',
            body: _collaborationReqMissingStr(data, 'price'),
          ),
          const SizedBox(height: 14),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '긴급 여부',
            body: data == null
                ? '미등록'
                : (data['isUrgent'] == true
                    ? '긴급'
                    : (data['isUrgent'] == false ? '일반' : '미등록')),
          ),
          const SizedBox(height: 14),
          _collaborationDetailLabeledBlock(
            textTheme: textTheme,
            label: '상세 내용',
            body: _collaborationReqMissingStr(data, 'description'),
          ),
          if (showStatus && statusBody != null) ...[
            const SizedBox(height: 14),
            _collaborationDetailLabeledBlock(
              textTheme: textTheme,
              label: '모집 상태',
              body: statusBody,
            ),
          ],
        ],
      ),
    ),
  );
}

/// collaborationRequests 문서 → 피드 카드 (작성자·비작성자에 따라 상세 분기).
Widget _collaborationCardFromFirestoreDoc(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc, {
  bool showCollaborationStatus = false,
}) {
  final d = doc.data();
  final displayTitle = _collaborationDisplayTitle(d);
  final isUrgent = d['isUrgent'] == true;
  final location = _collaborationRequestString(d['location']);
  final date = _collaborationRequestString(d['date']);
  final description = _collaborationRequestString(d['description']);
  final status = _collaborationRequestString(d['status']).isEmpty
      ? 'open'
      : _collaborationRequestString(d['status']);
  final accentLine =
      showCollaborationStatus ? '' : (status == 'open' ? '' : status);
  final statusChip =
      showCollaborationStatus ? collaborationDisplayStatusKo(status) : null;

  final displayLocation = location.isEmpty ? '-' : location;

  return _CollaborationCard(
    title: displayTitle,
    region: displayLocation,
    when: date.isEmpty ? '-' : date,
    accentLine: accentLine,
    titleStatusChip: statusChip,
    showUrgentBadge: isUrgent,
    description: description,
    onTap: () {
      runWithBriefLoading(context, () {
        if (!context.mounted) return;
        _openCollaborationRequestDetailFromDoc(context, doc);
      });
    },
  );
}

/// 구인·협업 피드 리스트용 카드 (상단 액션: 위치·전화·채팅·즐겨찾기).
Widget _collaborationFeedListCard(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc, {
  required Set<String> favoriteRequestIds,
}) {
  final textTheme = Theme.of(context).textTheme;
  const accent = Color(0xFF007AFF);
  final d = doc.data();
  final requestId = doc.id;
  final title = _collaborationDisplayTitle(d);
  final location = _collaborationRequestString(d['location']);
  final mainCat = _collaborationRequestString(d['mainCategory']);
  final svcLine = _collaborationReqServiceCategoriesLine(d);
  final desc = _collaborationRequestString(d['description']);
  final statusRaw = _collaborationRequestString(d['status']);
  final statusKo =
      collaborationDisplayStatusKo(statusRaw.isEmpty ? 'open' : statusRaw);
  final isUrgent = d['isUrgent'] == true;
  final ownerUid = _collaborationRequestString(d['ownerUid']).trim();
  final me = FirebaseAuth.instance.currentUser?.uid ?? '';
  final isFav = favoriteRequestIds.contains(requestId);

  void openDetail() {
    runWithBriefLoading(context, () {
      if (!context.mounted) return;
      _openCollaborationRequestDetailFromDoc(context, doc);
    });
  }

  return DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade300),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: openDetail,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Text(
                              title,
                              style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            if (isUrgent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  '긴급',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: accent.withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                statusKo,
                                style: textTheme.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: isFav ? '즐겨찾기 해제' : '즐겨찾기',
                        onPressed: () => toggleFavoriteCollaborationRequestForMe(
                          context,
                          requestId,
                        ),
                        icon: Icon(
                          isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  if (mainCat.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      mainCat,
                      style: textTheme.labelMedium?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    svcLine,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade800,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      desc,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.place_outlined,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location.isEmpty ? '미등록' : location,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: '위치',
                icon: Icon(Icons.place_outlined, color: accent),
                onPressed: location.isEmpty
                    ? null
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('지역: $location')),
                        );
                      },
              ),
              IconButton(
                tooltip: '전화 (공고자)',
                icon: Icon(Icons.call_outlined, color: accent),
                onPressed: ownerUid.isEmpty
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('공고자 정보를 찾을 수 없습니다.')),
                        );
                      }
                    : () async {
                        final u = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(ownerUid)
                            .get();
                        final phone = poUserPrimaryPhone(u.data() ?? {});
                        if (!context.mounted) return;
                        if (phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('등록된 전화번호가 없습니다.'),
                            ),
                          );
                          return;
                        }
                        final sanitized =
                            phone.replaceAll(RegExp(r'[^\d+]'), '');
                        await _launchBusinessPhone(Uri.parse('tel:$sanitized'));
                      },
              ),
              IconButton(
                tooltip: '채팅',
                icon: Icon(Icons.chat_bubble_outline_rounded, color: accent),
                onPressed: me.isEmpty || ownerUid.isEmpty
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('로그인이 필요합니다.')),
                        );
                      }
                    : () {
                        final chatId = collaborationApplicationChatFirestoreId(
                          requestId,
                          ownerUid,
                          me,
                        );
                        if (chatId.isEmpty) return;
                        Navigator.of(context).push(poSmoothPushRoute<void>(
                          ChatScreen(
                            requestId: requestId,
                            partnerUid: ownerUid,
                            requestTitle: title,
                            chatFirestoreDocId: chatId,
                          ),
                        ));
                      },
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tabIndex = 0;

  static const Color _accent = Color(0xFF007AFF);

  String _regionFilter = '';
  final Set<String> _selectedMainCategories = <String>{};
  final Set<String> _subKeys = <String>{};
  bool _favoritesOnly = false;

  final TextEditingController _regionDialogController =
      TextEditingController();
  final FocusNode _regionDialogFocusNode = FocusNode();
  final TextEditingController _searchKeywordController =
      TextEditingController();
  final FocusNode _searchKeywordFocusNode = FocusNode();

  void _onSearchKeywordChanged() {
    if (mounted) setState(() {});
  }

  bool _keepSubKeyDespiteMain(
    String main,
    String sub,
    Set<String> selected,
  ) {
    if (selected.contains(main)) return true;
    final twin = ServiceCategoryCatalog.pairedExteriorFilmMain(main);
    if (twin != null &&
        selected.contains(twin) &&
        ServiceCategoryCatalog.mirrorsAcrossExteriorAndFilm(sub)) {
      return true;
    }
    return false;
  }

  void _pruneSubKeysForSelectedMains() {
    if (_selectedMainCategories.isEmpty) return;
    final sel = _selectedMainCategories;
    _subKeys.removeWhere((k) {
      final p = ServiceCategoryCatalog.splitSelectionKey(k);
      if (p == null) return true;
      return !_keepSubKeyDespiteMain(p.main, p.sub, sel);
    });
  }

  void setTabIndex(int index) {
    if (!mounted) return;
    const maxIx = 4;
    setState(() {
      if (index < 0) {
        _tabIndex = 0;
      } else if (index > maxIx) {
        _tabIndex = maxIx;
      } else {
        _tabIndex = index;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _MainShellTabHost.register(this);
    _searchKeywordController.addListener(_onSearchKeywordChanged);
  }

  @override
  void dispose() {
    _MainShellTabHost.unregister(this);
    _regionDialogController.dispose();
    _regionDialogFocusNode.dispose();
    _searchKeywordController.removeListener(_onSearchKeywordChanged);
    _searchKeywordController.dispose();
    _searchKeywordFocusNode.dispose();
    super.dispose();
  }

  void _resetListFilters() {
    setState(() {
      _selectedMainCategories.clear();
      _subKeys.clear();
      _searchKeywordController.clear();
    });
  }

  void _openCategoryFilterSheet() {
    showPoServiceCategoryFilterSheet(
      context: context,
      accent: _accent,
      initialMains: Set<String>.from(_selectedMainCategories),
      initialSubKeys: Set<String>.from(_subKeys),
      onApply: (mains, keys) {
        if (!mounted) return;
        setState(() {
          _selectedMainCategories
            ..clear()
            ..addAll(mains);
          _subKeys
            ..clear()
            ..addAll(keys);
          _pruneSubKeysForSelectedMains();
        });
      },
      onResetAll: () {
        if (!mounted) return;
        _resetListFilters();
      },
    );
  }

  void _clearSearchKeyword() {
    setState(() {
      _searchKeywordController.clear();
    });
  }

  Future<void> _pickRegionDialog() async {
    final textTheme = Theme.of(context).textTheme;
    _regionDialogController.text = _regionFilter;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('지역 필터', style: textTheme.titleMedium),
          content: TextField(
            controller: _regionDialogController,
            focusNode: _regionDialogFocusNode,
            decoration: const InputDecoration(
              hintText: '비우면 전국 · 예: 서울 강남',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: _accent),
              child: const Text('적용'),
            ),
          ],
        );
      },
    );
    if (!mounted) return;
    if (ok == true) {
      setState(() {
        _regionFilter = _regionDialogController.text.trim();
      });
    }
    _regionDialogFocusNode.unfocus();
  }

  void _onProfileTap() {
    Navigator.of(context).push(
      poSmoothPushRoute<void>(const MyPageTabScreenV2()),
    );
  }

  Widget _myRequestsTopBar(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '내 요청',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: '알림',
              onPressed: () => _openPoNotifications(context),
              icon: Icon(Icons.notifications_outlined, color: Colors.grey.shade800),
            ),
            FilledButton.icon(
              onPressed: () {
                runWithBriefLoading(context, () {
                  if (!context.mounted) return;
                  Navigator.of(context).push(poSmoothPushRoute<void>(
                    const CollaborationRequestCreateScreen(),
                  ));
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('새 공고 작성'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _favoritesTopBar(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(
            '즐겨찾기',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '알림',
            onPressed: () => _openPoNotifications(context),
            icon: Icon(Icons.notifications_outlined, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Visibility(
              visible: _tabIndex == 0 || _tabIndex == 1,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: false,
              child: PoMainListHeader(
                accent: _accent,
                regionLabel: _regionFilter.isEmpty ? '전체 지역' : _regionFilter,
                onRegionTap: _pickRegionDialog,
                searchController: _searchKeywordController,
                searchFocusNode: _searchKeywordFocusNode,
                onSearchChanged: () => setState(() {}),
                onSearchClear: _clearSearchKeyword,
                onNotificationTap: () => _openPoNotifications(context),
                onProfileTap: _onProfileTap,
                favoritesOnly: _favoritesOnly,
                onFavoritesOnlyChanged: (bool v) =>
                    setState(() => _favoritesOnly = v),
                selectedMainCategories:
                    Set<String>.from(_selectedMainCategories),
                selectedSubKeys: _subKeys,
                onOpenCategoryFilter: _openCategoryFilterSheet,
              ),
            ),
            if (_tabIndex == 2) _myRequestsTopBar(context),
            if (_tabIndex == 4) _favoritesTopBar(context),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: <Widget>[
                  HomeTabScreen(
                    regionFilter: _regionFilter,
                    keyword: _searchKeywordController.text.trim(),
                    selectedMainCategories:
                        Set<String>.from(_selectedMainCategories),
                    subKeySet: Set<String>.from(_subKeys),
                    favoritesOnly: _favoritesOnly,
                  ),
                  CollaborationFeedTabBody(
                    regionFilter: _regionFilter,
                    keyword: _searchKeywordController.text.trim(),
                    selectedMainCategories:
                        Set<String>.from(_selectedMainCategories),
                    subKeySet: Set<String>.from(_subKeys),
                    favoritesOnly: _favoritesOnly,
                  ),
                  const MyRequestsTabScreen(),
                  const ChatTabScreen(),
                  const FavoritePartnersTabScreen(),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        elevation: 8,
        selectedItemColor: _accent,
        unselectedItemColor: Colors.grey.shade600,
        selectedFontSize: 12,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.handshake_outlined),
            activeIcon: Icon(Icons.handshake),
            label: '구인·협업',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.note_add_outlined),
            activeIcon: Icon(Icons.note_add),
            label: '내 요청',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            activeIcon: Icon(Icons.chat_rounded),
            label: '채팅',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.star_border_rounded),
            activeIcon: Icon(Icons.star_rounded),
            label: '즐겨찾기',
          ),
        ],
      ),
    );
  }
}

/// 모집글 작성자: 관리 메뉴 및 추천 업체 매칭 진입.
class OwnerRequestDetailScreen extends StatefulWidget {
  const OwnerRequestDetailScreen({
    super.key,
    required this.requestId,
  });

  final String requestId;

  @override
  State<OwnerRequestDetailScreen> createState() =>
      _OwnerRequestDetailScreenState();
}

class _OwnerRequestDetailScreenState extends State<OwnerRequestDetailScreen> {
  static const Color _accent = Color(0xFF007AFF);

  bool _closing = false;
  bool _workBusy = false;

  String _requestStatusLower(Map<String, dynamic>? data) => data == null
      ? ''
      : _collaborationRequestString(data['status']).toLowerCase();

  Future<void> _onStartWork() async {
    if (_workBusy) return;
    setState(() => _workBusy = true);
    try {
      await FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim())
          .update(<String, Object?>{
        'status': 'in_progress',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('작업 시작 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _workBusy = false);
    }
  }

  Future<void> _onCompleteWorkAndEvaluate(Map<String, dynamic> data) async {
    if (_workBusy) return;
    final partner =
        _collaborationRequestString(data['selectedApplicantUid']).trim();
    if (partner.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('채택된 업체 정보를 찾을 수 없습니다.'),
        ),
      );
      return;
    }

    setState(() => _workBusy = true);
    try {
      await FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim())
          .update(<String, Object?>{
        'status': 'completed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        poSmoothPushRoute<void>(
          EvaluationScreen(
            requestId: widget.requestId.trim(),
            targetUid: partner,
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('작업 완료 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _workBusy = false);
    }
  }

  Future<void> _closeRecruitment() async {
    if (_closing) return;
    setState(() => _closing = true);
    try {
      await FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId)
          .update(<String, Object?>{
        'status': 'closed',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모집을 마감했습니다.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('마감 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  bool _docStatusClosed(Map<String, dynamic>? data) {
    if (data == null) return false;
    return _collaborationRequestString(data['status']).toLowerCase() ==
        'closed';
  }

  Widget _actionButton({
    required String label,
    required VoidCallback? onPressed,
    bool filled = false,
  }) {
    final padding =
        const EdgeInsets.symmetric(vertical: 14);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          padding: padding,
          shape: shape,
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _accent,
        side: BorderSide(color: _accent.withValues(alpha: 0.45)),
        padding: padding,
        shape: shape,
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '내 모집글 관리',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('collaborationRequests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '공고를 불러오지 못했습니다.\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
              ),
            );
          }
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data?.data();
          if (data == null && snap.hasData) {
            return Center(
              child: Text(
                '공고가 삭제되었거나 없습니다.',
                style: textTheme.bodyMedium,
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _collaborationRequestDetailFieldsCard(
                textTheme: textTheme,
                data: data,
                showStatus: true,
              ),
              const SizedBox(height: 20),
              if (_requestStatusLower(data) == 'matched') ...[
                _actionButton(
                  label: _workBusy ? '처리 중…' : '작업 시작',
                  filled: true,
                  onPressed: _workBusy ? null : _onStartWork,
                ),
                const SizedBox(height: 10),
              ],
              if (_requestStatusLower(data) == 'in_progress') ...[
                _actionButton(
                  label: _workBusy ? '처리 중…' : '작업 완료',
                  filled: true,
                  onPressed: _workBusy || data == null
                      ? null
                      : () => _onCompleteWorkAndEvaluate(data),
                ),
                const SizedBox(height: 10),
              ],
              _actionButton(
                label: '지원 업체 보기',
                onPressed: () {
                  Navigator.of(context).push(poSmoothPushRoute<void>(
                    RequestApplicationsScreen(requestId: widget.requestId),
                  ));
                },
              ),
              const SizedBox(height: 10),
              _actionButton(
                label: '추천 업체 보기',
                filled: true,
                onPressed: data == null
                    ? null
                    : () {
                        Navigator.of(context).push(poSmoothPushRoute<void>(
                          MatchingScreen(
                            requestId: widget.requestId,
                            workType: _collaborationDisplayTitle(data),
                            location: _collaborationRequestString(data['location']),
                            description:
                                _collaborationRequestString(data['description']),
                          ),
                        ));
                      },
              ),
              const SizedBox(height: 10),
              _actionButton(
                label: '모집글 수정',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('모집글 수정은 준비 중입니다.')),
                  );
                },
              ),
              const SizedBox(height: 10),
              _actionButton(
                label: _closing ? '처리 중…' : '모집 마감',
                onPressed: (_closing || _docStatusClosed(data))
                    ? null
                    : _closeRecruitment,
              ),
              const SizedBox(height: 10),
              _actionButton(
                label: '협업 완료 기록',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('협업 완료 기록은 준비 중입니다.')),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 협업 완료 후 파트너 평가.
class EvaluationScreen extends StatefulWidget {
  const EvaluationScreen({
    super.key,
    required this.requestId,
    required this.targetUid,
  });

  final String requestId;
  final String targetUid;

  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  static const Color _accent = Color(0xFF007AFF);

  late final Map<String, double> _scores = <String, double>{
    for (final String k in collaborationReviewScoreKeys) k: 8,
  };

  final TextEditingController _commentCtrl = TextEditingController();

  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final target = widget.targetUid.trim();
    final rid = widget.requestId.trim();
    if (target.isEmpty || rid.isEmpty) return;

    final docId = collaborationReviewDocId(user.uid, rid);
    if (docId.isEmpty) return;

    setState(() => _submitting = true);
    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(target)
          .collection('reviews')
          .doc(docId);

      final existing = await docRef.get();
      final scoresMap = <String, int>{
        for (final String k in collaborationReviewScoreKeys)
          k: (_scores[k] ?? 8).round().clamp(1, 10),
      };

      final payload = <String, Object?>{
        'reviewerUid': user.uid,
        'requestId': rid,
        'scores': scoresMap,
        'comment': _commentCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!existing.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await docRef.set(payload, SetOptions(merge: true));
      await collaborationRecomputeUserAverageRating(target);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('평가가 완료되었습니다.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('평가 저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _sliderRow(TextTheme textTheme, String key) {
    final label =
        collaborationReviewScoreLabelsKo[key] ?? key;
    final v = (_scores[key] ?? 8).clamp(1.0, 10.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${v.round()}',
              style: textTheme.titleSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: v,
          min: 1,
          max: 10,
          divisions: 9,
          activeColor: _accent,
          onChanged: _submitting
              ? null
              : (double nv) => setState(() => _scores[key] = nv),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '협업 평가',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text(
            '항목별 1~10점을 선택한 뒤, 총평을 남겨 주세요.',
            style: textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          for (final String k in collaborationReviewScoreKeys)
            _sliderRow(textTheme, k),
          Text(
            '총평',
            style: textTheme.labelSmall?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentCtrl,
            minLines: 4,
            maxLines: 10,
            enabled: !_submitting,
            decoration: InputDecoration(
              hintText: '협업 경험을 간단히 적어 주세요',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _accent, width: 1.4),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_submitting ? '저장 중…' : '평가 제출'),
          ),
        ],
      ),
    );
  }
}

/// 타 사용자 모집글: 의뢰인 정보 확인·채팅 진입 등.
class PartnerRequestDetailScreen extends StatefulWidget {
  const PartnerRequestDetailScreen({
    super.key,
    required this.requestId,
    required this.ownerUid,
    this.ownerEmailFromRequest,
  });

  final String requestId;
  final String ownerUid;
  final String? ownerEmailFromRequest;

  @override
  State<PartnerRequestDetailScreen> createState() =>
      _PartnerRequestDetailScreenState();
}

class _PartnerRequestDetailScreenState extends State<PartnerRequestDetailScreen> {
  static const Color _accent = Color(0xFF007AFF);

  bool _loadingOwner = true;
  bool _favorited = false;
  bool _favoriteBusy = false;
  String _ownerDisplayName = '불러오는 중…';
  String _ownerRegions = '미등록';
  String _ownerBizShop = '미등록';
  String _ownerPrimaryCat = '미등록';
  String _ownerPhoneRaw = '';

  @override
  void initState() {
    super.initState();
    _loadOwnerProfile();
    _loadFavoriteRequestInterest();
  }

  Future<void> _loadFavoriteRequestInterest() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final rid = widget.requestId.trim();
    if (me == null || rid.isEmpty || !mounted) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(me).get();
      final raw = snap.data()?['favoriteRequestIds'];
      final set = raw is Iterable
          ? raw
              .whereType<String>()
              .map((String s) => s.trim())
              .where((String s) => s.isNotEmpty)
              .toSet()
          : <String>{};
      if (!mounted) return;
      setState(() => _favorited = set.contains(rid));
    } on Object {
      if (!mounted) return;
    }
  }

  Future<void> _toggleFavoriteRequestInterest() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    final rid = widget.requestId.trim();
    if (me == null || rid.isEmpty || _favoriteBusy) return;
    setState(() => _favoriteBusy = true);
    try {
      final willAdd = !_favorited;
      await FirebaseFirestore.instance.collection('users').doc(me).set(
            <String, Object?>{
              'favoriteRequestIds': willAdd
                  ? FieldValue.arrayUnion([rid])
                  : FieldValue.arrayRemove([rid]),
            },
            SetOptions(merge: true),
          );
      if (!mounted) return;
      setState(() => _favorited = willAdd);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            willAdd ? '관심 모집에 추가했습니다.' : '관심 모집을 해제했습니다.',
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장하지 못했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _loadOwnerProfile() async {
    final uid = widget.ownerUid.trim();
    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _loadingOwner = false;
          _ownerDisplayName = '의뢰업체 정보 없음';
          _ownerRegions = '미등록';
          _ownerBizShop = '미등록';
          _ownerPrimaryCat = '미등록';
          _ownerPhoneRaw = '';
        });
      }
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = snap.data();
      if (!mounted) return;
      setState(() {
        _loadingOwner = false;
        if (data == null) {
          final fbEmail = widget.ownerEmailFromRequest?.trim() ?? '';
          _ownerDisplayName =
              fbEmail.isNotEmpty ? fbEmail : '등록 프로필 없음';
          _ownerRegions = '미등록';
          _ownerBizShop = '미등록';
          _ownerPrimaryCat = '미등록';
          _ownerPhoneRaw = '';
        } else {
          _ownerDisplayName = poHomeUserCardTitle(data);
          final regLine = _matchingUserRegionsLine(data);
          _ownerRegions =
              regLine == '-' || regLine.isEmpty ? '미등록' : regLine;
          final bn = _matchingFieldStr(data['businessName']);
          final sn = _matchingFieldStr(data['shopName']);
          _ownerBizShop = [bn, sn]
              .where((String s) => s.isNotEmpty)
              .join(' · ');
          if (_ownerBizShop.isEmpty) _ownerBizShop = '미등록';
          final pc = _matchingFieldStr(data['primaryCategory']);
          _ownerPrimaryCat = pc.isEmpty ? '미등록' : pc;
          _ownerPhoneRaw = poUserPrimaryPhone(data);
        }
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loadingOwner = false;
        _ownerDisplayName = '정보를 불러오지 못했습니다';
        _ownerRegions = '미등록';
        _ownerBizShop = '미등록';
        _ownerPrimaryCat = '미등록';
        _ownerPhoneRaw = '';
      });
    }
  }

  void _dialOwnerPhone() {
    final raw = _ownerPhoneRaw.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록된 전화번호가 없습니다.')),
      );
      return;
    }
    final sanitized = raw.replaceAll(RegExp(r'[^\d+]'), '');
    _launchBusinessPhone(Uri.parse('tel:$sanitized'));
  }

  Widget _ownerCard(TextTheme textTheme) {
    final emailLine = widget.ownerEmailFromRequest?.trim() ?? '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '의뢰업체',
              style: textTheme.labelSmall?.copyWith(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            if (_loadingOwner)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else ...[
              Text(
                _ownerDisplayName,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              if (emailLine.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  emailLine,
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              _collaborationDetailLabeledBlock(
                textTheme: textTheme,
                label: '사업자·매장',
                body: _ownerBizShop,
              ),
              const SizedBox(height: 10),
              _collaborationDetailLabeledBlock(
                textTheme: textTheme,
                label: '대표 시공분야',
                body: _ownerPrimaryCat,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined,
                      size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _ownerRegions,
                      style: textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _collaborationDetailLabeledBlock(
                textTheme: textTheme,
                label: '연락처',
                body: _ownerPhoneRaw.trim().isEmpty ? '미등록' : _ownerPhoneRaw,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ownerUid = widget.ownerUid.trim();
    final chatPartnerUid =
        ownerUid.isNotEmpty ? ownerUid : 'test_partner';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '협업 요청 상세',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('collaborationRequests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, reqSnap) {
          if (reqSnap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '공고를 불러오지 못했습니다.\n${reqSnap.error}',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
              ),
            );
          }
          if (reqSnap.connectionState == ConnectionState.waiting &&
              !reqSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final reqData = reqSnap.data?.data();
          final chatTitle = reqData == null
              ? '협업 요청'
              : _collaborationDisplayTitle(reqData);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _collaborationRequestDetailFieldsCard(
                textTheme: textTheme,
                data: reqData,
                showStatus: true,
              ),
              const SizedBox(height: 16),
              _ownerCard(textTheme),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _loadingOwner ? null : _dialOwnerPhone,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('전화하기'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  final meUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  if (meUid.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('로그인이 필요합니다.')),
                    );
                    return;
                  }
                  final triChatId = collaborationApplicationChatFirestoreId(
                    widget.requestId,
                    chatPartnerUid,
                    meUid,
                  );
                  Navigator.of(context).push(poSmoothPushRoute<void>(
                    ChatScreen(
                      requestId: widget.requestId,
                      partnerUid: chatPartnerUid,
                      requestTitle: chatTitle,
                      partnerDisplayName: _loadingOwner ||
                              _ownerDisplayName == '불러오는 중…'
                          ? null
                          : (_ownerDisplayName.isEmpty
                              ? null
                              : _ownerDisplayName),
                      chatFirestoreDocId:
                          triChatId.isEmpty ? null : triChatId,
                    ),
                  ));
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('채팅 문의'),
              ),
              const SizedBox(height: 10),
              Builder(
                builder: (context) {
                  final meUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                  if (meUid.isEmpty) {
                    return FilledButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('로그인이 필요합니다.')),
                        );
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('협업 가능'),
                    );
                  }
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('collaborationRequests')
                        .doc(widget.requestId)
                        .collection('applications')
                        .doc(meUid)
                        .snapshots(),
                    builder: (context, appSnap) {
                      final hasApp = appSnap.hasData &&
                          appSnap.data != null &&
                          appSnap.data!.exists;
                      return FilledButton(
                        onPressed: () {
                          Navigator.of(context).push(poSmoothPushRoute<void>(
                            ApplyToRequestScreen(
                              requestId: widget.requestId,
                            ),
                          ));
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(hasApp ? '지원 수정' : '협업 가능'),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _favoriteBusy ? null : _toggleFavoriteRequestInterest,
                icon: Icon(
                  _favorited ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _accent,
                ),
                label: Text(_favoriteBusy ? '처리 중…' : '즐겨찾기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 파트너: 협업 공고 지원서 작성·수정.
class ApplyToRequestScreen extends StatefulWidget {
  const ApplyToRequestScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<ApplyToRequestScreen> createState() => _ApplyToRequestScreenState();
}

class _ApplyToRequestScreenState extends State<ApplyToRequestScreen> {
  static const Color _accent = Color(0xFF007AFF);

  final TextEditingController _priceCtrl = TextEditingController();
  final TextEditingController _scheduleCtrl = TextEditingController();
  final TextEditingController _materialCtrl = TextEditingController();
  final TextEditingController _messageCtrl = TextEditingController();

  bool _phoneVisible = true;
  bool _loading = true;
  bool _submitting = false;
  String? _initError;
  Map<String, dynamic>? _requestData;
  bool _hasExistingApplication = false;
  bool _blockAccepted = false;

  @override
  void dispose() {
    _priceCtrl.dispose();
    _scheduleCtrl.dispose();
    _materialCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loading = false;
        _initError = '로그인이 필요합니다.';
      });
      return;
    }

    try {
      final reqRef = FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim());
      final reqSnap = await reqRef.get();
      final reqData = reqSnap.data();
      if (!reqSnap.exists || reqData == null) {
        setState(() {
          _loading = false;
          _initError = '공고를 찾을 수 없습니다.';
        });
        return;
      }

      final ownerUid = _collaborationRequestString(reqData['ownerUid']);
      if (ownerUid.isNotEmpty && ownerUid == user.uid) {
        setState(() {
          _loading = false;
          _initError = '본인이 등록한 공고에는 지원할 수 없습니다.';
        });
        return;
      }

      final appSnap =
          await reqRef.collection('applications').doc(user.uid).get();
      final appData = appSnap.data();

      if (appSnap.exists && appData != null) {
        final p = appData['proposedPrice'];
        if (p is num) {
          _priceCtrl.text =
              p % 1 == 0 ? '${p.toInt()}' : p.toString();
        } else {
          final s = collaborationFormatProposedPrice(p);
          _priceCtrl.text = s == '미등록' ? '' : s;
        }
        _scheduleCtrl.text =
            _collaborationRequestString(appData['availableSchedule']);
        _materialCtrl.text =
            _collaborationRequestString(appData['materialOffer']);
        _messageCtrl.text = _collaborationRequestString(appData['message']);
        final vis = appData['isPhoneVisible'];
        _phoneVisible = vis is! bool || vis;
      }

      final st =
          _collaborationRequestString(appData?['status']).toLowerCase();
      final accepted = appSnap.exists && st == 'accepted';

      setState(() {
        _loading = false;
        _requestData = reqData;
        _hasExistingApplication = appSnap.exists;
        _blockAccepted = accepted;
      });
    } on Object catch (e) {
      setState(() {
        _loading = false;
        _initError = '불러오기 실패: $e';
      });
    }
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.4),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Future<void> _submit() async {
    if (_blockAccepted || _submitting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final price = collaborationParseProposedPrice(_priceCtrl.text);
    if (price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제안 금액(숫자)을 입력해 주세요.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final appRef = FirebaseFirestore.instance
          .collection('collaborationRequests')
          .doc(widget.requestId.trim())
          .collection('applications')
          .doc(user.uid);

      final existingSnap = await appRef.get();
      final curStatus =
          _collaborationRequestString(existingSnap.data()?['status'])
              .toLowerCase();
      if (existingSnap.exists && curStatus == 'accepted') {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채택된 지원은 수정할 수 없습니다.')),
        );
        setState(() => _submitting = false);
        return;
      }

      final profileSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final prof = profileSnap.data();

      final applicantDisplayName = poHomeUserCardTitle(prof ?? {});
      final applicantPhone = poUserPrimaryPhone(prof ?? {});
      final applicantPrimaryCategory =
          _matchingFieldStr(prof?['primaryCategory']);
      final applicantSearchCategories =
          collaborationUserSearchCategoriesList(prof);

      final payload = <String, Object?>{
        'applicationId': user.uid,
        'requestId': widget.requestId.trim(),
        'applicantUid': user.uid,
        'applicantEmail': user.email ?? '',
        'applicantDisplayName': applicantDisplayName,
        'applicantPhone': applicantPhone,
        'applicantPrimaryCategory': applicantPrimaryCategory,
        'applicantSearchCategories': applicantSearchCategories,
        'proposedPrice': price,
        'availableSchedule': _scheduleCtrl.text.trim(),
        'materialOffer': _materialCtrl.text.trim(),
        'message': _messageCtrl.text.trim(),
        'isPhoneVisible': _phoneVisible,
        'status': 'pending',
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!existingSnap.exists) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await appRef.set(payload, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('협업 지원이 제출되었습니다.')),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('제출 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '협업 지원하기',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _initError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _initError!,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    if (_blockAccepted)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: Colors.green.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(
                              '채택된 지원입니다. 내용을 수정할 수 없습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.green.shade900,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '공고 정보',
                              style: textTheme.labelSmall?.copyWith(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '공고 제목',
                              body: _requestData == null
                                  ? '미등록'
                                  : _collaborationDisplayTitle(_requestData!),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '작업 지역',
                              body: _collaborationReqMissingStr(
                                  _requestData, 'location',),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '일정',
                              body: _collaborationReqMissingStr(
                                  _requestData, 'date',),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '자재 조건',
                              body: _collaborationReqMissingStr(
                                  _requestData, 'materialCondition',),
                            ),
                            const SizedBox(height: 12),
                            _collaborationDetailLabeledBlock(
                              textTheme: textTheme,
                              label: '희망 금액',
                              body: _collaborationReqMissingStr(
                                  _requestData, 'price',),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      '지원 내용',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: _fieldDecoration('예: 300000'),
                      enabled: !_blockAccepted,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _scheduleCtrl,
                      decoration:
                          _fieldDecoration('예: 오늘 오후 3시 가능'),
                      enabled: !_blockAccepted,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _materialCtrl,
                      keyboardType: TextInputType.multiline,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _fieldDecoration(
                        '예: PPF 필름 지참 가능 / 랩핑 필름은 의뢰자 제공 필요',
                      ),
                      enabled: !_blockAccepted,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _messageCtrl,
                      keyboardType: TextInputType.multiline,
                      minLines: 5,
                      maxLines: 10,
                      decoration: _fieldDecoration(
                        '협업 가능 조건을 간단히 입력하세요',
                      ),
                      enabled: !_blockAccepted,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '전화 공개 여부',
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        Switch(
                          value: _phoneVisible,
                          onChanged: _blockAccepted
                              ? null
                              : (bool v) => setState(() => _phoneVisible = v),
                          activeTrackColor: _accent.withValues(alpha: 0.35),
                          activeThumbColor: _accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed:
                          (_blockAccepted || _submitting) ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_submitting
                          ? '저장 중…'
                          : (_hasExistingApplication
                              ? '지원 수정'
                              : '지원 제출')),
                    ),
                  ],
                ),
    );
  }
}

/// 모집 작성자: 지원 업체 목록.
class RequestApplicationsScreen extends StatefulWidget {
  const RequestApplicationsScreen({super.key, required this.requestId});

  final String requestId;

  @override
  State<RequestApplicationsScreen> createState() =>
      _RequestApplicationsScreenState();
}

class _RequestApplicationsScreenState extends State<RequestApplicationsScreen> {
  static const Color _accent = Color(0xFF007AFF);

  String? _busyApplicationId;

  Future<void> _accept({
    required BuildContext context,
    required String applicantUid,
    required DocumentReference<Map<String, dynamic>> appRef,
    required DocumentReference<Map<String, dynamic>> reqRef,
  }) async {
    if (_busyApplicationId != null) return;
    setState(() => _busyApplicationId = applicantUid);
    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final reqSnap = await transaction.get(reqRef);
        final rd = reqSnap.data();
        final st =
            _collaborationRequestString(rd?['status']).toLowerCase();
        final sel = _collaborationRequestString(rd?['selectedApplicantUid']);
        if (st == 'matched' &&
            sel.isNotEmpty &&
            sel != applicantUid) {
          throw StateError('matched_other');
        }
        transaction.set(
          appRef,
          <String, Object?>{
            'status': 'accepted',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        transaction.set(
          reqRef,
          <String, Object?>{
            'status': 'matched',
            'selectedApplicantUid': applicantUid,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지원을 채택했습니다.')),
      );
    } on StateError catch (e) {
      if (!context.mounted) return;
      final msg = e.message == 'matched_other'
          ? '이미 다른 업체와 매칭된 공고입니다.'
          : e.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('채택 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyApplicationId = null);
    }
  }

  Future<void> _reject({
    required BuildContext context,
    required String applicantUid,
    required DocumentReference<Map<String, dynamic>> appRef,
  }) async {
    if (_busyApplicationId != null) return;
    setState(() => _busyApplicationId = applicantUid);
    try {
      await appRef.set(<String, Object?>{
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('지원을 거절했습니다.')),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('거절 처리 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyApplicationId = null);
    }
  }

  void _openChat({
    required BuildContext context,
    required String ownerUid,
    required String applicantUid,
    required Map<String, dynamic> reqData,
    required String applicantName,
  }) {
    final chatId = collaborationApplicationChatFirestoreId(
      widget.requestId.trim(),
      ownerUid,
      applicantUid,
    );
    if (chatId.isEmpty) return;
    Navigator.of(context).push(poSmoothPushRoute<void>(
      ChatScreen(
        requestId: widget.requestId.trim(),
        partnerUid: applicantUid,
        requestTitle: _collaborationDisplayTitle(reqData),
        partnerDisplayName:
            applicantName.isEmpty ? null : applicantName,
        chatFirestoreDocId: chatId,
      ),
    ));
  }

  void _dialApplicant(BuildContext context, Map<String, dynamic> app) {
    final visible = app['isPhoneVisible'] == true;
    final raw = _collaborationRequestString(app['applicantPhone']);
    if (!visible || raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('전화번호가 공개되지 않았습니다.'),
        ),
      );
      return;
    }
    final sanitized = raw.replaceAll(RegExp(r'[^\d+]'), '');
    _launchBusinessPhone(Uri.parse('tel:$sanitized'));
  }

  int _tsCompare(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ad = a.data()['createdAt'];
    final bd = b.data()['createdAt'];
    if (ad is Timestamp && bd is Timestamp) {
      return bd.compareTo(ad);
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final me = FirebaseAuth.instance.currentUser?.uid;

    if (me == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Colors.black87,
          title: Text(
            '지원 업체 목록',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: Center(
          child: Text(
            '로그인이 필요합니다.',
            style: textTheme.bodyMedium,
          ),
        ),
      );
    }

    final reqRef = FirebaseFirestore.instance
        .collection('collaborationRequests')
        .doc(widget.requestId.trim());

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '지원 업체 목록',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: reqRef.snapshots(),
        builder: (context, reqSnap) {
          if (reqSnap.hasError) {
            return Center(child: Text('${reqSnap.error}'));
          }
          if (reqSnap.connectionState == ConnectionState.waiting &&
              !reqSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final reqData = reqSnap.data?.data();
          if (reqData == null) {
            return const Center(child: Text('공고를 찾을 수 없습니다.'));
          }
          final ownerUid = _collaborationRequestString(reqData['ownerUid']);
          if (ownerUid.isEmpty || ownerUid != me) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '이 공고의 작성자만 지원 목록을 볼 수 있습니다.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
              ),
            );
          }

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: reqRef.collection('applications').snapshots(),
            builder: (context, appSnap) {
              if (appSnap.hasError) {
                return Center(child: Text('${appSnap.error}'));
              }
              final docs = appSnap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final sorted =
                  List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs)
                    ..sort(_tsCompare);

              if (sorted.isEmpty) {
                return Center(
                  child: Text(
                    '아직 지원한 업체가 없습니다.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                itemCount: sorted.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (ctx, int index) {
                  final doc = sorted[index];
                  final d = doc.data();
                  final applicantUid =
                      _collaborationRequestString(d['applicantUid']);
                  final name =
                      _collaborationRequestString(d['applicantDisplayName']);
                  if (applicantUid.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final busy = _busyApplicationId == applicantUid;
                  final appCats = collaborationApplicantSearchCategoriesList(d);
                  final catLine =
                      appCats.isEmpty ? '미등록' : appCats.join(' · ');
                  final statusRaw =
                      _collaborationRequestString(d['status']);
                  final stLow = statusRaw.toLowerCase();
                  final canDecide =
                      stLow == 'pending' || stLow.isEmpty;

                  final primary = _collaborationReqMissingStr(
                    d, 'applicantPrimaryCategory',);

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            name.isEmpty ? '이름 미등록' : name,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '제안 금액',
                            body: collaborationFormatProposedPrice(
                                d['proposedPrice'],),
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '가능 일정',
                            body: _collaborationReqMissingStr(
                                d, 'availableSchedule',),
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '준비 가능 자재',
                            body: _collaborationReqMissingStr(
                                d, 'materialOffer',),
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '메시지',
                            body: _collaborationReqMissingStr(d, 'message'),
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '대표 시공분야',
                            body: primary,
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '세부 시공분야',
                            body: catLine,
                          ),
                          const SizedBox(height: 10),
                          _collaborationDetailLabeledBlock(
                            textTheme: textTheme,
                            label: '상태',
                            body: collaborationApplicationStatusKo(statusRaw),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _openChat(
                                            context: context,
                                            ownerUid: ownerUid,
                                            applicantUid: applicantUid,
                                            reqData: reqData,
                                            applicantName: name,
                                          ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _accent,
                                    side: BorderSide(
                                        color: _accent.withValues(alpha: 0.45),),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('채팅하기'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => _dialApplicant(context, d),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: _accent,
                                    side: BorderSide(
                                        color: _accent.withValues(alpha: 0.45),),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('전화하기'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: busy || !canDecide
                                      ? null
                                      : () => _accept(
                                            context: context,
                                            applicantUid: applicantUid,
                                            appRef: doc.reference,
                                            reqRef: reqRef,
                                          ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(busy ? '처리 중…' : '채택하기'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: busy || !canDecide
                                      ? null
                                      : () => _reject(
                                            context: context,
                                            applicantUid: applicantUid,
                                            appRef: doc.reference,
                                          ),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    side: BorderSide(
                                        color: Colors.red.shade200,),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12,),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('거절하기'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
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

/// 홈 업체 카드에서 진입하는 업체 상세 프로필.
class CompanyDetailScreen extends StatelessWidget {
  const CompanyDetailScreen({
    super.key,
    required this.partnerUid,
    required this.userData,
  });

  final String partnerUid;
  final Map<String, dynamic> userData;

  static const Color _accent = Color(0xFF007AFF);

  void _requireLoginSnack(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
  }

  void _onPhone(BuildContext context, String? meUid) {
    if (meUid == null) {
      _requireLoginSnack(context);
      return;
    }
    final phoneRaw = poUserPrimaryPhone(userData);
    if (phoneRaw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록된 전화번호가 없습니다.')),
      );
      return;
    }
    final sanitized = phoneRaw.replaceAll(RegExp(r'[^\d+]'), '');
    _launchBusinessPhone(Uri.parse('tel:$sanitized'));
  }

  void _onChat(BuildContext context, String? meUid) {
    if (meUid == null) {
      _requireLoginSnack(context);
      return;
    }
    final name = poHomeUserCardTitle(userData);
    runWithBriefLoading(context, () {
      if (!context.mounted) return;
      Navigator.of(context).push(poSmoothPushRoute<void>(
        ChatScreen(
          requestId: 'direct',
          partnerUid: partnerUid,
          requestTitle: '$name · 문의',
          partnerDisplayName: name,
        ),
      ));
    });
  }

  void _onFavorite(BuildContext context, String? meUid) {
    if (meUid == null) {
      _requireLoginSnack(context);
      return;
    }
    toggleFavoritePartnerUidForMe(context, partnerUid);
  }

  Widget _infoRow(TextTheme textTheme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.black87,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomActions(
    BuildContext context, {
    required String? meUid,
    required bool isFavorite,
  }) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      child: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _onPhone(context, meUid),
                    icon: Icon(Icons.call_outlined, color: _accent, size: 18),
                    label: const Text('전화하기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _onChat(context, meUid),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('채팅하기'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _onFavorite(context, meUid),
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _accent,
              ),
              label: Text(isFavorite ? '즐겨찾기 해제' : '즐겨찾기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _accent,
                side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final me = FirebaseAuth.instance.currentUser?.uid;
    final d = userData;

    final infoBody = DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoRow(
              textTheme,
              '표시 이름',
              _companyProfileFieldOrMissing(d, 'displayName'),
            ),
            _infoRow(
              textTheme,
              '사업자명',
              _companyProfileFieldOrMissing(d, 'businessName'),
            ),
            _infoRow(
              textTheme,
              '매장명',
              _companyProfileFieldOrMissing(d, 'shopName'),
            ),
            _infoRow(
              textTheme,
              '대표자명',
              _companyProfileFieldOrMissing(d, 'ownerName'),
            ),
            _infoRow(
              textTheme,
              '지역',
              _companyProfileRegionsLine(d),
            ),
            _infoRow(
              textTheme,
              '대표 시공분야',
              _companyProfileFieldOrMissing(d, 'primaryCategory'),
            ),
            _infoRow(
              textTheme,
              '메인 카테고리',
              _companyProfileListLine(d, 'mainCategories'),
            ),
            _infoRow(
              textTheme,
              '세부 시공분야',
              _companyProfileListLine(d, 'searchCategories'),
            ),
            _infoRow(
              textTheme,
              '예산 구간',
              _companyProfileFieldOrMissing(d, 'priceRange'),
            ),
            _infoRow(
              textTheme,
              '응답 속도',
              _companyProfileFieldOrMissing(d, 'responseSpeed'),
            ),
            _infoRow(
              textTheme,
              '전화번호',
              _companyProfileFieldOrMissing(d, 'phoneNumber'),
            ),
            _infoRow(
              textTheme,
              '매장 전화',
              _companyProfileFieldOrMissing(d, 'storePhone'),
            ),
            _infoRow(
              textTheme,
              '홈페이지',
              _companyProfileFieldOrMissing(d, 'homepageUrl'),
            ),
            _infoRow(
              textTheme,
              '블로그',
              _companyProfileFieldOrMissing(d, 'blogUrl'),
            ),
            _infoRow(
              textTheme,
              '사업자 인증',
              _companyProfileLicenseStatus(d),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 프로필',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                Text(
                  poHomeUserCardTitle(d),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                infoBody,
                const SizedBox(height: 28),
                Text(
                  '마감 디테일 약속',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                _CompanyFinishDetailsSection(partnerUid: partnerUid),
              ],
            ),
          ),
          if (me != null)
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(me)
                  .snapshots(),
              builder: (context, snap) {
                final raw = snap.data?.data()?['favoritePartnerUids'];
                final fav = <String>{
                  if (raw is Iterable)
                    for (final e in raw)
                      if (e is String && e.trim().isNotEmpty) e.trim(),
                };
                final isFav = fav.contains(partnerUid);
                return _bottomActions(
                  context,
                  meUid: me,
                  isFavorite: isFav,
                );
              },
            )
          else
            _bottomActions(context, meUid: null, isFavorite: false),
        ],
      ),
    );
  }
}

String collaborationChatFirestoreId(String requestId, String partnerUid) =>
    '${requestId.trim()}_${partnerUid.trim()}';

bool _poChatMessageIsDeleted(Map<String, dynamic> data) =>
    data['isDeleted'] == true;

/// 갤러리 스와이프용: 완료된 이미지 URL만.
bool _poChatMessageIsGalleryImage(Map<String, dynamic> data) {
  if (_poChatMessageIsDeleted(data)) return false;
  if ((data['type'] as String?)?.trim() != 'image') return false;
  final url = (data['imageUrl'] as String?)?.trim() ?? '';
  if (url.isEmpty) return false;
  final st = data['status'];
  if (st is String) return st == 'complete';
  return true;
}

List<String> _poChatGalleryImageUrls(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final out = <String>[];
  for (final d in docs) {
    if (!_poChatMessageIsGalleryImage(d.data())) continue;
    final u = (d.data()['imageUrl'] as String?)?.trim() ?? '';
    if (u.isNotEmpty) out.add(u);
  }
  return out;
}

int _poChatGalleryStartIndex(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  String tappedDocId,
) {
  var idx = 0;
  var start = 0;
  var found = false;
  for (final d in docs) {
    if (!_poChatMessageIsGalleryImage(d.data())) continue;
    if (d.id == tappedDocId) {
      start = idx;
      found = true;
    }
    idx++;
  }
  return found ? start : 0;
}

/// 채팅 이미지 연속 보기 (PageView).
class ImageGalleryScreen extends StatefulWidget {
  const ImageGalleryScreen({
    super.key,
    required this.imageUrls,
    required this.initialIndex,
  });

  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<ImageGalleryScreen> createState() => _ImageGalleryScreenState();
}

class _ImageGalleryScreenState extends State<ImageGalleryScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final last = widget.imageUrls.length - 1;
    final initial = widget.initialIndex.clamp(0, last < 0 ? 0 : last);
    _currentIndex = initial;
    _pageController = PageController(initialPage: initial);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.imageUrls.length;
    if (n == 0) {
      return const Scaffold(
        body: Center(child: Text('이미지가 없습니다.')),
      );
    }
    final label = '${_currentIndex + 1} / $n';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '닫기',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: n,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (context, i) {
          final u = widget.imageUrls[i];
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: u,
                fit: BoxFit.contain,
                placeholder: (context, _) => const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                ),
                errorWidget: (context, url, error) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '이미지를 불러올 수 없습니다.',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 채팅 말풍선에서 로컬 미리보기만 단일 전체화면.
class _ChatFullScreenImageView extends StatelessWidget {
  const _ChatFullScreenImageView({
    this.imageUrl,
    this.localFilePath,
  });

  final String? imageUrl;
  final String? localFilePath;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim() ?? '';
    final path = localFilePath?.trim() ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: url.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (ctx, _) => const SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                  errorWidget: (context, url, error) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      '이미지를 불러올 수 없습니다.',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : path.isNotEmpty
                  ? Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Text(
                        '파일을 열 수 없습니다.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : const Text(
                      '표시할 이미지가 없습니다.',
                      style: TextStyle(color: Colors.white70),
                    ),
        ),
      ),
    );
  }
}

/// Firestore 메시지 + Storage 이미지 첨부 1:1 채팅.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.requestId,
    required this.partnerUid,
    required this.requestTitle,
    this.partnerDisplayName,
    this.chatFirestoreDocId,
  });

  /// `collaborationRequests` 문서 ID.
  final String requestId;
  /// 대화 상대 `users/{partnerUid}`.
  final String partnerUid;
  final String requestTitle;
  final String? partnerDisplayName;
  /// `chats` 문서 ID. null이면 [requestId]_[partnerUid] 형식.
  final String? chatFirestoreDocId;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const Color _accent = Color(0xFF007AFF);
  /// flutter_image_compress (요구: quality 65, 최대 변 1600).
  static const int _chatImageCompressQuality = 65;
  static const int _chatImageMaxSide = 1600;
  static const int _chatMultiPickMax = 5;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  /// 업로드 완료 전 로컬 미리보기 경로 (문서 id → 압축 파일 경로).
  final Map<String, String> _localPreviewPaths = <String, String>{};
  final Map<String, double> _uploadProgress = <String, double>{};

  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = <String>{};
  bool _shareSelectedBusy = false;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _liveMsgDocs =
      const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  String? _editingMessageId;

  int _lastAppliedMessageLen = -1;

  String get _chatId {
    final custom = widget.chatFirestoreDocId?.trim();
    if (custom != null && custom.isNotEmpty) return custom;
    return collaborationChatFirestoreId(widget.requestId, widget.partnerUid);
  }

  void _syncScrollForMessageCount(int n) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_lastAppliedMessageLen == n) return;
      _lastAppliedMessageLen = n;
      final extent = _scrollController.position.maxScrollExtent;
      if (extent <= 0) return;
      _scrollController.jumpTo(extent);
    });
  }

  String? _resolveImageLocalPath(String docId, Map<String, dynamic> data) {
    final mem = _localPreviewPaths[docId];
    if (mem != null && File(mem).existsSync()) return mem;
    final lp = data['localPath'];
    if (lp is String && lp.trim().isNotEmpty) {
      final path = lp.trim();
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  double? _resolveUploadProgress(String docId, Map<String, dynamic> data) {
    final live = _uploadProgress[docId];
    if (live != null) return live;
    final pr = data['progress'];
    if (pr is num) return pr.toDouble().clamp(0.0, 1.0);
    return null;
  }

  void _openChatImageFullscreen({
    required String? networkUrl,
    required String? localPath,
  }) {
    final u = networkUrl?.trim() ?? '';
    var lp = localPath?.trim() ?? '';
    if (lp.isNotEmpty && !File(lp).existsSync()) lp = '';
    if (u.isEmpty && lp.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => _ChatFullScreenImageView(
          imageUrl: u.isNotEmpty ? u : null,
          localFilePath: lp.isNotEmpty ? lp : null,
        ),
      ),
    );
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _findLiveDoc(String docId) {
    for (final d in _liveMsgDocs) {
      if (d.id == docId) return d;
    }
    return null;
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _toggleMessageSelection(String docId) {
    setState(() {
      if (_selectedMessageIds.contains(docId)) {
        _selectedMessageIds.remove(docId);
        if (_selectedMessageIds.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedMessageIds.add(docId);
      }
    });
  }

  void _openImageGalleryIfComplete(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    String tappedDocId,
  ) {
    final urls = _poChatGalleryImageUrls(allDocs);
    if (urls.isEmpty) return;
    final start =
        _poChatGalleryStartIndex(allDocs, tappedDocId).clamp(0, urls.length - 1);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => ImageGalleryScreen(
          imageUrls: urls,
          initialIndex: start,
        ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _selectedDocsOrdered() {
    final sel = _selectedMessageIds;
    final out = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final d in _liveMsgDocs) {
      if (sel.contains(d.id)) out.add(d);
    }
    return out;
  }

  Future<void> _copySelectedMessages() async {
    final parts = <String>[];
    for (final d in _selectedDocsOrdered()) {
      final m = d.data();
      if (_poChatMessageIsDeleted(m)) continue;
      if ((m['type'] as String?)?.trim() != 'text') continue;
      final t = (m['text'] as String?)?.trim() ?? '';
      if (t.isEmpty || t == '삭제된 메시지입니다.') continue;
      parts.add(t);
    }
    if (parts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('복사할 텍스트가 없습니다.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: parts.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('클립보드에 복사했습니다.')),
    );
  }

  Future<void> _runWithShareLoading(Future<void> Function() task) async {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (ctx) => Center(
        child: CircularProgressIndicator(
          color: Theme.of(ctx).colorScheme.primary,
        ),
      ),
    );
    try {
      await task();
    } finally {
      if (mounted) nav.pop();
    }
  }

  Future<XFile?> _downloadChatImageToTempFile(String imageUrl, int serial) async {
    final trimmed = imageUrl.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    try {
      final response =
          await http.get(uri).timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) return null;
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return null;
      final dir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final name = serial == 0
          ? 'chat_image_$ts.jpg'
          : 'chat_image_${ts}_$serial.jpg';
      final path = p.join(dir.path, name);
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return XFile(path, mimeType: 'image/jpeg');
    } on Object {
      return null;
    }
  }

  Future<void> _shareSelectedMessages() async {
    if (_shareSelectedBusy) return;

    final textParts = <String>[];
    final imageUrls = <String>[];
    for (final d in _selectedDocsOrdered()) {
      final m = d.data();
      if (_poChatMessageIsDeleted(m)) continue;
      final ty = (m['type'] as String?)?.trim() ?? '';
      if (ty == 'text') {
        final t = (m['text'] as String?)?.trim() ?? '';
        if (t.isEmpty || t == '삭제된 메시지입니다.') continue;
        textParts.add(t);
      } else if (ty == 'image') {
        final u = (m['imageUrl'] as String?)?.trim() ?? '';
        if (u.isNotEmpty) imageUrls.add(u);
      }
    }

    final combinedText = textParts.join('\n');
    if (combinedText.isEmpty && imageUrls.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유할 내용이 없습니다.')),
      );
      return;
    }

    final hasText = combinedText.isNotEmpty;
    final hasImageUrls = imageUrls.isNotEmpty;

    if (hasText && hasImageUrls) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            content: const Text(
              '카카오톡은 사진과 텍스트를 동시에 공유할 때 텍스트가 누락될 수 있습니다. 텍스트를 클립보드에 복사한 뒤 사진을 공유합니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('공유'),
              ),
            ],
          );
        },
      );
      if (confirmed != true || !mounted) return;
    }

    if (!mounted) return;
    setState(() {
      _shareSelectedBusy = true;
    });

    Future<void> invokeShare(List<XFile> files, bool anyImageFailed) async {
      if (!mounted) return;

      if (files.isEmpty && combinedText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              anyImageFailed && imageUrls.isNotEmpty
                  ? '일부 이미지를 공유하지 못했습니다.'
                  : '공유할 내용이 없습니다.',
            ),
          ),
        );
        return;
      }

      if (anyImageFailed && imageUrls.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('일부 이미지를 공유하지 못했습니다.')),
        );
      }

      final hasText = combinedText.isNotEmpty;
      final hasFiles = files.isNotEmpty;

      try {
        if (!hasText && hasFiles) {
          // ignore: deprecated_member_use
          await Share.shareXFiles(files);
        } else if (hasText && !hasFiles) {
          // ignore: deprecated_member_use
          await Share.share(combinedText);
        } else if (hasText && hasFiles) {
          await Clipboard.setData(ClipboardData(text: combinedText));
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                '텍스트가 복사되었습니다. 사진 전송 후 채팅창에 붙여넣기 해주세요.',
              ),
            ),
          );
          // ignore: deprecated_member_use
          await Share.shareXFiles(files);
        }
      } on Object {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공유에 실패했습니다.')),
        );
      }
    }

    try {
      if (imageUrls.isEmpty) {
        await invokeShare(const <XFile>[], false);
        return;
      }

      await _runWithShareLoading(() async {
        final files = <XFile>[];
        var anyImageFailed = false;
        for (var i = 0; i < imageUrls.length; i++) {
          final xf = await _downloadChatImageToTempFile(imageUrls[i], i);
          if (xf != null) {
            files.add(xf);
          } else {
            anyImageFailed = true;
          }
        }
        await invokeShare(files, anyImageFailed);
      });
    } finally {
      if (mounted) {
        setState(() {
          _shareSelectedBusy = false;
          _selectionMode = false;
          _selectedMessageIds.clear();
        });
      }
    }
  }

  Future<void> _shareOneMessage(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final m = doc.data();
    if (_poChatMessageIsDeleted(m)) return;
    final ty = (m['type'] as String?)?.trim() ?? '';
    if (ty == 'text') {
      final t = (m['text'] as String?)?.trim() ?? '';
      if (t.isEmpty) return;
      await SharePlus.instance.share(ShareParams(text: t));
    } else if (ty == 'image') {
      final u = (m['imageUrl'] as String?)?.trim() ?? '';
      if (u.isEmpty) return;
      Future<void> shareImage() async {
        final xf = await _downloadChatImageToTempFile(u, 0);
        if (!mounted) return;
        if (xf == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('일부 이미지를 공유하지 못했습니다.')),
          );
          return;
        }
        await SharePlus.instance.share(ShareParams(files: [xf]));
      }

      await _runWithShareLoading(shareImage);
    }
  }

  Future<void> _softDeleteMessageDoc(String docId) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc(docId)
        .update(<String, Object?>{
          'isDeleted': true,
          'text': '삭제된 메시지입니다.',
          'imageUrl': '',
          'thumbnailUrl': '',
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  Future<void> _deleteSelectedMessages() async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    var deleted = 0;
    for (final d in _selectedDocsOrdered()) {
      if (!_documentIsMine(d.data(), me)) continue;
      if (_poChatMessageIsDeleted(d.data())) continue;
      try {
        await _softDeleteMessageDoc(d.id);
        deleted++;
      } on Object catch (_) {}
    }
    if (!mounted) return;
    _exitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted > 0 ? '메시지를 삭제했습니다.' : '삭제할 내 메시지가 없습니다.',
        ),
      ),
    );
  }

  bool _canEditSingleSelectedText() {
    if (_selectedMessageIds.length != 1) return false;
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final id = _selectedMessageIds.first;
    final doc = _findLiveDoc(id);
    if (doc == null) return false;
    final m = doc.data();
    if (_poChatMessageIsDeleted(m)) return false;
    if (!_documentIsMine(m, me)) return false;
    return (m['type'] as String?)?.trim() == 'text';
  }

  void _startEditSingleSelectedText() {
    final id = _selectedMessageIds.first;
    final doc = _findLiveDoc(id);
    if (doc == null) return;
    final t = (doc.data()['text'] as String?) ?? '';
    setState(() {
      _editingMessageId = id;
      _inputController.text = t;
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  void _cancelTextEdit() {
    setState(() {
      _editingMessageId = null;
      _inputController.clear();
    });
  }

  Future<void> _copyOneTextMessage(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final m = doc.data();
    final t = (m['text'] as String?)?.trim() ?? '';
    if (t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('복사했습니다.')),
    );
  }

  Future<void> _editTextMessageDialog(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!_documentIsMine(doc.data(), me)) return;
    final cur = (doc.data()['text'] as String?) ?? '';
    final controller = TextEditingController(text: cur);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('메시지 수정'),
          content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(hintText: '내용'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );
    if (ok != true || !mounted) {
      controller.dispose();
      return;
    }
    final next = controller.text.trim();
    controller.dispose();
    if (next.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(doc.id)
          .update(<String, Object?>{
            'text': next,
            'isEdited': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('수정하지 못했습니다: $e')),
      );
    }
  }

  Future<void> _confirmDeleteOne(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (!_documentIsMine(doc.data(), me)) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메시지 삭제'),
        content: const Text('이 메시지를 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _softDeleteMessageDoc(doc.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메시지를 삭제했습니다.')),
        );
      }
    }
  }

  Future<void> _onMessageLongPress(String docId) async {
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    final doc = _findLiveDoc(docId);
    if (doc == null) return;
    setState(() {
      _selectionMode = true;
      _selectedMessageIds.add(docId);
    });

    final data = doc.data();
    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isMine = _documentIsMine(data, me);
    final isDel = _poChatMessageIsDeleted(data);
    final ty = (data['type'] as String?)?.trim() ?? '';

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  '메시지',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              if (!isDel && ty == 'text') ...[
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('복사'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_copyOneTextMessage(doc));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('공유'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_shareOneMessage(doc));
                  },
                ),
                if (isMine)
                  ListTile(
                    leading: const Icon(Icons.edit_rounded),
                    title: const Text('수정'),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_editTextMessageDialog(doc));
                    },
                  ),
              ],
              if (!isDel && ty == 'image') ...[
                ListTile(
                  leading: const Icon(Icons.share_rounded),
                  title: const Text('공유'),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_shareOneMessage(doc));
                  },
                ),
                if (isMine &&
                    _normalizedImageStatus(
                          data,
                          (data['imageUrl'] as String?)?.trim() ?? '',
                          _resolveImageLocalPath(doc.id, data),
                        ) ==
                        'failed')
                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('다시 보내기'),
                    onTap: () {
                      Navigator.pop(ctx);
                      unawaited(_retryImageUpload(doc.id));
                    },
                  ),
              ],
              if (isMine && !isDel)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
                  title: Text('삭제', style: TextStyle(color: Colors.red.shade700)),
                  onTap: () {
                    Navigator.pop(ctx);
                    unawaited(_confirmDeleteOne(doc));
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildChatAppBar({
    required TextTheme textTheme,
    required String titlePrimary,
    required String? partnerLabel,
  }) {
    if (_selectionMode) {
      return AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _exitSelectionMode,
          tooltip: '취소',
        ),
        title: Text(
          '${_selectedMessageIds.length}개 선택',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '복사',
            onPressed: _copySelectedMessages,
            icon: const Icon(Icons.copy_rounded),
          ),
          IconButton(
            tooltip: '공유',
            onPressed: _shareSelectedBusy ? null : _shareSelectedMessages,
            icon: const Icon(Icons.share_rounded),
          ),
          if (_canEditSingleSelectedText())
            IconButton(
              tooltip: '수정',
              onPressed: _startEditSingleSelectedText,
              icon: const Icon(Icons.edit_rounded),
            ),
          IconButton(
            tooltip: '삭제',
            onPressed: _deleteSelectedMessages,
            icon: Icon(Icons.delete_outline_rounded, color: Colors.red.shade700),
          ),
        ],
      );
    }

    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: Colors.black87,
      toolbarHeight:
          partnerLabel != null && partnerLabel.isNotEmpty ? 68 : null,
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            titlePrimary,
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (partnerLabel != null && partnerLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              partnerLabel,
              style: textTheme.labelSmall?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: () {
            runWithBriefLoading(context, () {
              if (!context.mounted) return;
              Navigator.of(context).push(poSmoothPushRoute<void>(
                CollaborationCompleteScreen(
                  requestTitle: widget.requestTitle,
                ),
              ));
            });
          },
          child: Text(
            '작업 완료',
            style: textTheme.labelLarge?.copyWith(
              color: _accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  String _normalizedImageStatus(
    Map<String, dynamic> data,
    String url,
    String? localPath,
  ) {
    final r = data['status'];
    if (r is String && r.trim().isNotEmpty) return r.trim();
    if (url.isNotEmpty) return 'complete';
    if (localPath != null) return 'uploading';
    return 'failed';
  }

  Future<File?> _compressChatImage(XFile xFile) async {
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final salt = math.Random().nextInt(1 << 20);
      final target = p.join(dir.path, 'chat_cmp_${stamp}_$salt.jpg');
      final out = await FlutterImageCompress.compressAndGetFile(
        xFile.path,
        target,
        quality: _chatImageCompressQuality,
        minWidth: _chatImageMaxSide,
        minHeight: _chatImageMaxSide,
        format: CompressFormat.jpeg,
      );
      if (out != null) return File(out.path);
    } on Object catch (_) {
      /* fallback */
    }
    try {
      return File(xFile.path);
    } on Object catch (_) {
      return null;
    }
  }

  void _disposeLocalPreviewFile(String docId) {
    final path = _localPreviewPaths.remove(docId);
    _uploadProgress.remove(docId);
    if (path != null) {
      try {
        File(path).deleteSync();
      } on Object catch (_) {}
    }
  }

  Future<void> _executeUploadForMessage({
    required String docId,
    required File file,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final storagePath = 'chat_images/$_chatId/$docId.jpg';
    final ref = FirebaseStorage.instance.ref(storagePath);
    final task = ref.putFile(
      file,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final msgRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc(docId);

    var lastProgressBucket = -1;
    StreamSubscription<TaskSnapshot>? sub;
    sub = task.snapshotEvents.listen((snap) {
      final total = snap.totalBytes;
      if (total <= 0) return;
      final p = (snap.bytesTransferred / total).clamp(0.0, 1.0);
      if (mounted) {
        setState(() => _uploadProgress[docId] = p);
      }
      final bucket = (p * 4).floor().clamp(0, 4);
      if (bucket > lastProgressBucket) {
        lastProgressBucket = bucket;
        unawaited(
          msgRef.update(<String, Object?>{
            'progress': p,
            'updatedAt': FieldValue.serverTimestamp(),
          }),
        );
      }
    });

    try {
      await task;
      final imageUrl = await ref.getDownloadURL();
      await msgRef.update(<String, Object?>{
        'imageUrl': imageUrl,
        'thumbnailUrl': imageUrl,
        'localPath': '',
        'status': 'complete',
        'progress': 1.0,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() {
          _uploadProgress.remove(docId);
          _disposeLocalPreviewFile(docId);
        });
      } else {
        _disposeLocalPreviewFile(docId);
      }
      await _notifyChatRoomSummaryOutbound('사진');
    } on Object catch (e) {
      try {
        await msgRef.update(<String, Object?>{
          'status': 'failed',
          'progress': 0.0,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } on Object catch (_) {}
      if (mounted) {
        setState(() => _uploadProgress.remove(docId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진 전송 실패: $e')),
        );
      }
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _handleOneImageUpload(XFile xFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final file = await _compressChatImage(xFile);
    if (file == null || !await file.exists()) return;

    if (!mounted) return;
    final col = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages');
    final docRef = col.doc();
    final id = docRef.id;

    await docRef.set(<String, Object?>{
      'messageId': id,
      'senderUid': user.uid,
      'senderEmail': user.email ?? '',
      'type': 'image',
      'text': '',
      'imageUrl': '',
      'thumbnailUrl': '',
      'localPath': file.path,
      'status': 'uploading',
      'progress': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;
    setState(() {
      _localPreviewPaths[id] = file.path;
      _uploadProgress[id] = 0.0;
    });

    await _executeUploadForMessage(docId: id, file: file);
  }

  Future<void> _pickAndUploadGalleryImages() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final picker = ImagePicker();
    final List<XFile> pickedRaw;
    try {
      pickedRaw = await picker.pickMultiImage(imageQuality: 85);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진을 선택하지 못했습니다: $e')),
      );
      return;
    }

    final picked = pickedRaw.length > _chatMultiPickMax
        ? pickedRaw.sublist(0, _chatMultiPickMax)
        : pickedRaw;
    if (pickedRaw.length > _chatMultiPickMax && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '한 번에 최대 $_chatMultiPickMax장까지 전송합니다. '
            '처음 $_chatMultiPickMax장만 선택되었습니다.',
          ),
        ),
      );
    }

    if (picked.isEmpty || !mounted) return;
    unawaited(Future.wait(picked.map(_handleOneImageUpload)));
  }

  Future<void> _retryImageUpload(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final path = _localPreviewPaths[docId];
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('다시 보내려면 사진을 새로 선택해 주세요.'),
        ),
      );
      return;
    }
    final f = File(path);
    if (!await f.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('파일을 찾을 수 없어 재시도할 수 없습니다.'),
        ),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(docId)
          .update(<String, Object?>{
            'status': 'uploading',
            'imageUrl': '',
            'thumbnailUrl': '',
            'progress': 0.0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('재시도 준비 실패: $e')),
      );
      return;
    }

    if (mounted) {
      setState(() => _uploadProgress[docId] = 0.0);
    }
    unawaited(_executeUploadForMessage(docId: docId, file: f));
  }

  Future<void> _sendText() async {
    final trimmed = _inputController.text.trim();
    if (trimmed.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final editId = _editingMessageId?.trim();
    if (editId != null && editId.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .collection('messages')
            .doc(editId)
            .update(<String, Object?>{
              'text': trimmed,
              'isEdited': true,
              'updatedAt': FieldValue.serverTimestamp(),
            });
        if (mounted) {
          setState(() {
            _editingMessageId = null;
            _inputController.clear();
          });
        }
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('수정하지 못했습니다: $e')),
        );
      }
      return;
    }

    try {
      _inputController.clear();
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .add(<String, Object?>{
            'senderUid': user.uid,
            'senderEmail': user.email ?? '',
            'type': 'text',
            'text': trimmed,
            'createdAt': FieldValue.serverTimestamp(),
          });
      await _notifyChatRoomSummaryOutbound(trimmed);
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('전송하지 못했습니다: $e')),
      );
    }
  }

  bool _documentIsMine(Map<String, dynamic> data, String myUid) {
    final uid = data['senderUid'];
    return uid is String && uid == myUid;
  }

  Widget _wrapMessageBubble({
    required String docId,
    required Widget child,
    VoidCallback? onTap,
    bool allowLongPress = true,
  }) {
    final selected = _selectedMessageIds.contains(docId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? _accent.withValues(alpha: 0.14) : Colors.transparent,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            onLongPress: allowLongPress
                ? () => unawaited(_onMessageLongPress(docId))
                : null,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _bubbleShell({
    required bool isMine,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment:
            isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageTile(
    QueryDocumentSnapshot<Map<String, dynamic>> docSnap,
    String myUid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
  ) {
    final data = docSnap.data();
    final docId = docSnap.id;
    final textTheme = Theme.of(context).textTheme;
    final isMine = _documentIsMine(data, myUid);

    if (_poChatMessageIsDeleted(data)) {
      return _wrapMessageBubble(
        docId: docId,
        allowLongPress: false,
        onTap: _selectionMode ? () => _toggleMessageSelection(docId) : null,
        child: _bubbleShell(
          isMine: isMine,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                '삭제된 메시지입니다.',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final typeRaw = data['type'];
    final parsedType = typeRaw is String ? typeRaw.trim() : '';

    if (parsedType == 'image') {
      final rawUrl = data['imageUrl'];
      final url = rawUrl is String ? rawUrl.trim() : '';
      final resolvedLocal = _resolveImageLocalPath(docId, data);
      final status = _normalizedImageStatus(data, url, resolvedLocal);
      final progress = _resolveUploadProgress(docId, data);

      if (status == 'failed') {
        return _wrapMessageBubble(
          docId: docId,
          onTap: _selectionMode ? () => _toggleMessageSelection(docId) : null,
          child: _bubbleShell(
            isMine: isMine,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: isMine
                      ? _accent.withValues(alpha: 0.15)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMine ? _accent : Colors.grey.shade300,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: Colors.red.shade700, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '사진을 보내지 못했습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                color: isMine
                                    ? Colors.white70
                                    : Colors.grey.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (isMine) ...[
                        const SizedBox(height: 10),
                        FilledButton.tonal(
                          onPressed: () => _retryImageUpload(docId),
                          child: const Text('재시도'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      final borderClr =
          isMine ? _accent.withValues(alpha: 0.55) : Colors.grey.shade300;
      final hasLocal = resolvedLocal != null &&
          resolvedLocal.isNotEmpty &&
          File(resolvedLocal).existsSync();

      Widget imageChild;
      if (url.isNotEmpty && status == 'complete') {
        imageChild = CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (context, _) => SizedBox(
            height: 180,
            child: Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.8,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ),
          errorWidget: (context, url, error) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '이미지 표시 불가',
              style: textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ),
        );
      } else if (hasLocal) {
        imageChild = Image.file(
          File(resolvedLocal),
          fit: BoxFit.cover,
          errorBuilder: (context, err, st) => Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '미리보기를 불러올 수 없습니다',
              style: textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ),
        );
      } else {
        imageChild = ColoredBox(
          color: Colors.grey.shade200,
          child: SizedBox(
            height: 160,
            child: Center(
              child: Icon(Icons.image_outlined,
                  size: 48, color: Colors.grey.shade500),
            ),
          ),
        );
      }

      final showUploadOverlay =
          status == 'uploading' || (url.isEmpty && hasLocal);

      final canGallery = url.isNotEmpty && status == 'complete';

      return _wrapMessageBubble(
        docId: docId,
        onTap: () {
          if (_selectionMode) {
            _toggleMessageSelection(docId);
            return;
          }
          if (canGallery) {
            _openImageGalleryIfComplete(allDocs, docId);
          } else if (hasLocal) {
            _openChatImageFullscreen(
              networkUrl: url.isNotEmpty ? url : null,
              localPath: resolvedLocal,
            );
          }
        },
        child: _bubbleShell(
          isMine: isMine,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: borderClr, width: 1.2),
                ),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 220, maxWidth: 280),
                  child: Stack(
                    alignment: Alignment.center,
                    fit: StackFit.passthrough,
                    children: [
                      Positioned.fill(
                        child: imageChild,
                      ),
                      if (showUploadOverlay)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                            ),
                            child: Center(
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3.2,
                                  color: Colors.white,
                                  value: (progress != null &&
                                          progress > 0 &&
                                          progress < 1)
                                      ? progress
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final textRaw = data['text'];
    final text =
        textRaw is String ? textRaw.trim() : '';
    if (text.isEmpty) return const SizedBox.shrink();

    final bg = isMine ? _accent : Colors.white;
    final fg = isMine ? Colors.white : Colors.black87;
    final isEdited = data['isEdited'] == true;

    return _wrapMessageBubble(
      docId: docId,
      onTap: _selectionMode ? () => _toggleMessageSelection(docId) : null,
      child: _bubbleShell(
        isMine: isMine,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            border: isMine
                ? null
                : Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isEdited)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '편집됨',
                      style: textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.72),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Text(
                  text,
                  style: textTheme.bodyMedium?.copyWith(
                    color: fg,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _bootstrapChatRoomDocument() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await collaborationEnsureChatRoomShell(
      chatId: _chatId,
      myUid: user.uid,
      partnerUid: widget.partnerUid,
      requestId: widget.requestId,
      requestTitle: widget.requestTitle,
    );
  }

  Future<void> _notifyChatRoomSummaryOutbound(String preview) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final pruned =
        preview.length > 200 ? preview.substring(0, 200) : preview;
    await collaborationTouchChatRoomSummary(
      chatId: _chatId,
      myUid: user.uid,
      partnerUid: widget.partnerUid,
      requestId: widget.requestId,
      requestTitle: widget.requestTitle,
      lastMessagePreview: pruned,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _bootstrapChatRoomDocument());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final partnerLabel =
        widget.partnerDisplayName?.trim();

    final titlePrimary = widget.requestTitle.trim().isEmpty
        ? '채팅'
        : widget.requestTitle.trim();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildChatAppBar(
        textTheme: textTheme,
        titlePrimary: titlePrimary,
        partnerLabel: partnerLabel,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(_chatId)
                    .collection('messages')
                    .orderBy('createdAt', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '메시지를 불러오지 못했습니다.\n${snapshot.error}',
                          style:
                              textTheme.bodyMedium?.copyWith(height: 1.45),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (snapshot.connectionState ==
                          ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final msgDocs = snapshot.data?.docs ?? [];
                  _liveMsgDocs = msgDocs;
                  _syncScrollForMessageCount(msgDocs.length);

                  if (msgDocs.isEmpty) {
                    return Center(
                      child: Text(
                        '메시지를 보내 대화를 시작해 보세요.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: msgDocs.length,
                    itemBuilder: (context, index) {
                      return _buildMessageTile(
                        msgDocs[index],
                        myUid,
                        msgDocs,
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Material(
            color: Colors.white,
            elevation: 8,
            shadowColor: Colors.black26,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_editingMessageId != null)
                    Material(
                      color: _accent.withValues(alpha: 0.1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.edit_note_rounded,
                                size: 22, color: _accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '메시지 수정 중',
                                style: textTheme.labelLarge?.copyWith(
                                  color: _accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _cancelTextEdit,
                              child: const Text('취소'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: '갤러리에서 사진',
                      onPressed: () => unawaited(_pickAndUploadGalleryImages()),
                      icon: Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Colors.grey.shade700,
                      ),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendText(),
                        decoration: InputDecoration(
                          hintText: '메시지 입력',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade500,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sendText,
                      style: IconButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.send_rounded, size: 22),
                    ),
                  ],
                ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> toggleFavoriteCollaborationRequestForMe(
  BuildContext context,
  String requestId,
) async {
  final me = FirebaseAuth.instance.currentUser?.uid;
  final rid = requestId.trim();
  if (me == null || rid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
    return;
  }

  try {
    final ref = FirebaseFirestore.instance.collection('users').doc(me);
    final snap = await ref.get();
    final raw = snap.data()?['favoriteRequestIds'];
    final favList = <String>[
      if (raw is Iterable)
        for (final e in raw)
          if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
    final has = favList.contains(rid);

    await ref.set(
      <String, Object?>{
        'favoriteRequestIds':
            has ? FieldValue.arrayRemove([rid]) : FieldValue.arrayUnion([rid]),
      },
      SetOptions(merge: true),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(has ? '공고 즐겨찾기를 해제했습니다.' : '공고를 즐겨찾기에 추가했습니다.'),
      ),
    );
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('처리하지 못했습니다: $e')),
    );
  }
}

Future<void> toggleFavoritePartnerUidForMe(
    BuildContext context,
    String partnerUid,) async {
  final me = FirebaseAuth.instance.currentUser?.uid;
  final pid = partnerUid.trim();
  if (me == null || pid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
    return;
  }

  try {
    final ref = FirebaseFirestore.instance.collection('users').doc(me);
    final snap = await ref.get();
    final raw = snap.data()?['favoritePartnerUids'];
    final favList = <String>[
      if (raw is Iterable)
        for (final e in raw)
          if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
    final has = favList.contains(pid);

    await ref.set(
      <String, Object?>{
        'favoritePartnerUids':
            has ? FieldValue.arrayRemove([pid]) : FieldValue.arrayUnion([pid]),
      },
      SetOptions(merge: true),
    );

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(has ? '즐겨찾기를 해제했습니다.' : '즐겨찾기에 추가했습니다.'),
      ),
    );
  } on Object catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('처리하지 못했습니다: $e')),
    );
  }
}

/// 협업 요청에 대응 가능한 업체 후보 목록 (`users.searchCategories`).
class MatchingScreen extends StatefulWidget {
  const MatchingScreen({
    super.key,
    required this.requestId,
    required this.workType,
    required this.location,
    required this.description,
  });

  /// Firestore 문서 ID(추후 추적용).
  final String requestId;
  final String workType;
  final String location;
  final String description;

  @override
  State<MatchingScreen> createState() => _MatchingScreenState();
}

class _MatchingScreenState extends State<MatchingScreen> {
  static const Color _accent = Color(0xFF007AFF);

  late Future<List<CollaborationMatchingCandidate>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchCollaborationMatchingCandidates(
      workType: widget.workType,
      requestId: widget.requestId,
    );
  }

  Widget _labeledBlock({
    required TextTheme textTheme,
    required String label,
    required String body,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          style: textTheme.bodyMedium?.copyWith(
            height: 1.45,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '업체 매칭',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: () {
              setState(() {
                _future = _fetchCollaborationMatchingCandidates(
                  workType: widget.workType,
                  requestId: widget.requestId,
                );
              });
            },
            icon: Icon(Icons.refresh_rounded, color: _accent),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _labeledBlock(
                      textTheme: textTheme,
                      label: '작업 종류',
                      body: widget.workType,
                    ),
                    const SizedBox(height: 14),
                    _labeledBlock(
                      textTheme: textTheme,
                      label: '지역',
                      body: widget.location,
                    ),
                    const SizedBox(height: 14),
                    _labeledBlock(
                      textTheme: textTheme,
                      label: '요청 내용',
                      body: widget.description,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  final rid = widget.requestId.trim().isEmpty
                      ? 'test_request'
                      : widget.requestId.trim();
                  Navigator.of(context).push(poSmoothPushRoute<void>(
                    ChatScreen(
                      requestId: rid,
                      partnerUid: 'test_partner',
                      requestTitle: widget.workType,
                      partnerDisplayName: '테스트 상대',
                    ),
                  ));
                },
                icon: Icon(Icons.chat_bubble_outline_rounded, color: _accent),
                label: const Text('채팅 테스트'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Text(
                  '추천 업체',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'searchCategories 일치 업체 중 AI 점수 상위 5곳입니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<CollaborationMatchingCandidate>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        '업체를 불러오지 못했습니다.\n${snapshot.error}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade800,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final rows = snapshot.data ?? <CollaborationMatchingCandidate>[];
                if (rows.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        '조건에 맞는 업체가 아직 없습니다.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade600,
                          height: 1.45,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _MatchingPartnerCard(
                      doc: row.doc,
                      score: row.score,
                      showRecommendBadge: row.score >= 60,
                      collaborationRequestId: widget.requestId,
                      collaborationRequestTitle: widget.workType,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchingPartnerCard extends StatelessWidget {
  const _MatchingPartnerCard({
    required this.doc,
    required this.score,
    required this.showRecommendBadge,
    required this.collaborationRequestId,
    required this.collaborationRequestTitle,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int score;
  final bool showRecommendBadge;

  /// `collaborationRequests` 문서 ID.
  final String collaborationRequestId;
  /// 협업 요청 타이틀(작업 종류 등 · 채팅 라벨).
  final String collaborationRequestTitle;

  static const Color _accent = Color(0xFF007AFF);

  void _onPhone(BuildContext context, Map<String, dynamic> data) {
    final phoneRaw = poUserPrimaryPhone(data);
    if (phoneRaw.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('등록된 전화번호가 없습니다.')),
      );
      return;
    }
    final sanitized = phoneRaw.replaceAll(RegExp(r'[^\d+]'), '');
    _launchBusinessPhone(Uri.parse('tel:$sanitized'));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final data = doc.data();

    final name = poHomeUserCardTitle(data);
    final regions = _matchingUserRegionsLine(data);
    final primary = _matchingFieldStr(data['primaryCategory']);
    final available = _matchingUserAvailable(data);
    final ratingStr = _matchingFormatAverageRatingDisplay(data);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
                      height: 1.35,
                      letterSpacing: -0.2,
                      color: Colors.black87,
                    ),
                  ),
                ),
                if (showRecommendBadge)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Text(
                      '추천',
                      style: textTheme.labelSmall?.copyWith(
                        color: Colors.teal.shade800,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '즐겨찾기 업체로 추가',
                  onPressed: () => toggleFavoritePartnerUidForMe(
                    context,
                    doc.id,
                  ),
                  icon: Icon(
                    Icons.star_outline_rounded,
                    color: _accent,
                  ),
                ),
                if (available)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        '준비 가능',
                        style: textTheme.labelSmall?.copyWith(
                          color: _accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '추천 점수 $score',
              style: textTheme.titleSmall?.copyWith(
                color: _accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.handyman_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    primary.isEmpty ? '미등록' : primary,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade800,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    regions == '-' || regions.isEmpty ? '미등록' : regions,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.star_rounded,
                    size: 18, color: Colors.amber.shade700),
                const SizedBox(width: 4),
                Text(
                  '평점 $ratingStr',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      runWithBriefLoading(context, () {
                        if (!context.mounted) return;
                        final rid = collaborationRequestId.trim().isEmpty
                            ? 'test_request'
                            : collaborationRequestId.trim();
                        final pid = doc.id.trim().isEmpty
                            ? 'test_partner'
                            : doc.id.trim();
                        Navigator.of(context).push(poSmoothPushRoute<void>(
                          ChatScreen(
                            requestId: rid,
                            partnerUid: pid,
                            requestTitle: collaborationRequestTitle,
                            partnerDisplayName: name,
                          ),
                        ));
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('채팅하기'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _onPhone(context, data),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('전화하기'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 작업 완료 후 비고·사진 등록
class CollaborationCompleteScreen extends StatefulWidget {
  const CollaborationCompleteScreen({super.key, required this.requestTitle});

  final String requestTitle;

  @override
  State<CollaborationCompleteScreen> createState() =>
      _CollaborationCompleteScreenState();
}

class _CollaborationCompleteScreenState
    extends State<CollaborationCompleteScreen> {
  static const Color _accent = Color(0xFF007AFF);

  final TextEditingController _reasonController = TextEditingController();
  bool _requestConfirmationToParty = false;

  InputDecoration _reasonFieldDecoration() {
    return InputDecoration(
      labelText: '현장·마감 비고 (선택)',
      hintText: '예: 기존도장 손상으로 등록 기준보다 들뜸이 조금 더 보입니다.',
      hintMaxLines: 6,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade800,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: _accent,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: Colors.white,
      alignLabelWithHint: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }

  void _onSave() {
    runWithBriefLoading(context, () {
      // ignore: avoid_print
      print(
        '글: ${widget.requestTitle}\n'
        '현장·마감 비고: ${_reasonController.text}\n'
        '상대 업체 확인 요청: ${_requestConfirmationToParty ? '예' : '아니오'}',
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(poSmoothPushRoute<void>(
        ReviewScreen(requestTitle: widget.requestTitle),
      ));
    });
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '작업 완료',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.requestTitle,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _accent,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '작업 마친 뒤, 완료 사진이나 현장 상황을 남겨 두면 분쟁 줄이기에 좋아요.',
                    style: textTheme.bodyMedium?.copyWith(
                      height: 1.55,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 20, color: _accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '꼭 쓸 필요 없고, 필요할 때 참고 자료로 쓰실 수 있습니다.',
                              style: textTheme.bodySmall?.copyWith(
                                height: 1.5,
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  CustomPaint(
                    painter: _DashedRoundRectPainter(
                      color: Colors.grey.shade400,
                      strokeWidth: 1.8,
                      radius: 14,
                    ),
                    child: SizedBox(
                      height: 156,
                      width: double.infinity,
                      child: Material(
                        color: Colors.grey.shade50,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: InkWell(
                          onTap: () {
                            runWithBriefLoading(context, () {
                              // ignore: avoid_print
                              print('완료 사진 첨부');
                            });
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline,
                                  size: 40, color: Colors.grey.shade500),
                              const SizedBox(height: 10),
                              Text(
                                '완료 사진 넣기',
                                style: textTheme.titleSmall?.copyWith(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _reasonController,
                    maxLines: 5,
                    minLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: _reasonFieldDecoration(),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    value: _requestConfirmationToParty,
                    onChanged: (v) {
                      setState(() {
                        _requestConfirmationToParty = v ?? false;
                      });
                    },
                    title: Text(
                      '상대 업체에 확인 받기',
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    activeColor: _accent,
                    checkColor: Colors.white,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: FilledButton(
                onPressed: _onSave,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('평가로 이동'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 협업 만족도 평가
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.requestTitle});

  final String requestTitle;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const Color _accent = Color(0xFF007AFF);

  static const List<String> _ratingLabels = [
    '시공 마감',
    '시공 속도',
    'A/S',
    '응답 속도',
    '친절함',
    '가성비',
  ];

  late final List<int> _scores;
  final TextEditingController _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scores = List<int>.filled(_ratingLabels.length, 5);
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _submit() {
    runWithBriefLoading(context, () {
      final parts = <String>[
        '글: ${widget.requestTitle}',
        for (var i = 0; i < _ratingLabels.length; i++)
          '${_ratingLabels[i]}: ${_scores[i]}점',
        '메모: ${_memoController.text}',
      ];
      // ignore: avoid_print
      print(parts.join('\n'));
      if (!mounted) return;
      _goHome(context);
    });
  }

  @override
  void dispose() {
    _memoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '협업 평가',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.requestTitle,
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _accent,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (var i = 0; i < _ratingLabels.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _ReviewRatingRow(
                      label: _ratingLabels[i],
                      score: _scores[i],
                      accent: _accent,
                      onChanged: (v) {
                        setState(() => _scores[i] = v.round());
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextField(
                    controller: _memoController,
                    maxLines: 4,
                    minLines: 3,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      labelText: '간단 후기',
                      hintText: '시공 속도나 소통 같은 점 적어 주세요',
                      hintStyle:
                          TextStyle(color: Colors.grey.shade500, fontSize: 14),
                      labelStyle: TextStyle(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      floatingLabelStyle: const TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.w600,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      alignLabelWithHint: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _accent, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('평가 등록'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRatingRow extends StatelessWidget {
  const _ReviewRatingRow({
    required this.label,
    required this.score,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final int score;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Text(
                  '$score',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
                Text(
                  ' / 10',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: accent,
                inactiveTrackColor: Colors.grey.shade300,
                thumbColor: accent,
                trackHeight: 3.5,
              ),
              child: Slider(
                value: score.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '$score',
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 전문 시공 협업 공고 등록 폼
class CollaborationRequestCreateScreen extends StatefulWidget {
  const CollaborationRequestCreateScreen({super.key});

  @override
  State<CollaborationRequestCreateScreen> createState() =>
      _CollaborationRequestCreateScreenState();
}

class _CollaborationRequestCreateScreenState
    extends State<CollaborationRequestCreateScreen> {
  static const Color _accent = Color(0xFF007AFF);

  static const List<String> _materialOptions = <String>[
    '전부 제공',
    '일부 제공',
    '업체 준비',
  ];

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String? _selectedMain;
  final Set<String> _selectedSubKeys = <String>{};
  DateTime? _scheduleDate;
  bool _isOnSite = false;
  String _materialCondition = _materialOptions.first;
  bool _isUrgent = false;

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade800,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: _accent,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }

  Widget _sectionCard(TextTheme textTheme, String title, List<Widget> body) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 14),
            ...body,
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final initial = _scheduleDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(now.year - 1, 1, 1)) ? now : initial,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 3, 12, 31),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _accent,
              onPrimary: Colors.white,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _scheduleDate = picked);
    }
  }

  void _selectMain(String main) {
    setState(() {
      _selectedMain = main;
      _selectedSubKeys.clear();
    });
  }

  void _toggleSub(String sub) {
    final main = _selectedMain;
    if (main == null) return;
    setState(() {
      final k = ServiceCategoryCatalog.selectionKey(main, sub);
      final nowSelect = !_selectedSubKeys.contains(k);
      final next = ServiceCategoryCatalog.toggledSelectionSet(
        current: _selectedSubKeys,
        main: main,
        sub: sub,
        selected: nowSelect,
      );
      _selectedSubKeys
        ..clear()
        ..addAll(next);
    });
  }

  void _onSubmit() => _submitCollaborationRequest();

  Future<void> _submitCollaborationRequest() async {
    FocusScope.of(context).unfocus();
    if (!context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    final messenger = ScaffoldMessenger.of(context);
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final title = _titleController.text.trim();
    final location = _locationController.text.trim();
    final description = _descriptionController.text.trim();

    if (title.isEmpty ||
        _selectedMain == null ||
        _selectedMain!.trim().isEmpty ||
        location.isEmpty ||
        description.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('작업 제목·메인 카테고리·지역·상세 내용은 필수입니다.'),
        ),
      );
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    bool dialogOpen = false;
    Object? caught;

    final dateStr =
        _scheduleDate == null ? '' : _formatDate(_scheduleDate!);
    final subs = ServiceCategoryCatalog.distinctSubs(_selectedSubKeys)
        .toList(growable: false);
    final priceText = _priceController.text.trim();

    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.25),
        builder: (ctx) => Center(
          child: CircularProgressIndicator(
            color: Theme.of(ctx).colorScheme.primary,
          ),
        ),
      );
      dialogOpen = true;

      final ref =
          FirebaseFirestore.instance.collection('collaborationRequests').doc();
      final requestId = ref.id;

      final locPack = PoRegionFields.fromRegionFull(location);

      await ref.set(<String, Object?>{
        'requestId': requestId,
        'ownerUid': user.uid,
        'ownerEmail': user.email ?? '',
        'title': title,
        'mainCategory': _selectedMain!,
        'serviceCategories': subs,
        'location': location,
        ...poRegionCollaborationFirestoreMap(locPack),
        'date': dateStr,
        'isOnSite': _isOnSite,
        'materialCondition': _materialCondition,
        'price': priceText,
        'isUrgent': _isUrgent,
        'description': description,
        'workType': title,
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on Object catch (e, st) {
      caught = e;
      debugPrint('$e\n$st');
    } finally {
      if (dialogOpen && context.mounted) {
        navigator.pop();
      }
    }

    if (!context.mounted) return;

    if (caught != null) {
      messenger.showSnackBar(
        SnackBar(content: Text('등록하지 못했습니다: $caught')),
      );
      return;
    }

    _MainShellTabHost.goHomeTab();
    navigator.pop();

    messenger.showSnackBar(
      const SnackBar(content: Text('협업 요청이 등록되었습니다.')),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final subs = _selectedMain == null
        ? const <String>[]
        : ServiceCategoryCatalog.servicesForMain(_selectedMain!);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '협업 공고 작성',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '모집 조건을 구체적으로 적을수록 맞는 파트너와 연결되기 쉽습니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(textTheme, '기본 정보', [
                    TextField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: '작업 제목 *',
                        hint: '예: PPF + 랩핑 협업 구함',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _locationController,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: '지역 *',
                        hint: '예: 서울 강남구',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '메인 카테고리 *',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final main in ServiceCategoryCatalog.mainTitles)
                          FilterChip(
                            label: Text(
                              main,
                              style: textTheme.labelMedium?.copyWith(
                                fontSize: 11.5,
                                height: 1.2,
                              ),
                            ),
                            selected: _selectedMain == main,
                            onSelected: (_) => _selectMain(main),
                            selectedColor: _accent.withValues(alpha: 0.2),
                            checkmarkColor: _accent,
                          ),
                      ],
                    ),
                    if (_selectedMain != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '세부 시공분야 (복수 선택)',
                        style: textTheme.labelMedium?.copyWith(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          for (final sub in subs)
                            FilterChip(
                              label: Text(sub),
                              selected: _selectedSubKeys.contains(
                                ServiceCategoryCatalog.selectionKey(
                                  _selectedMain!,
                                  sub,
                                ),
                              ),
                              onSelected: (_) => _toggleSub(sub),
                              selectedColor: _accent.withValues(alpha: 0.2),
                              checkmarkColor: _accent,
                            ),
                        ],
                      ),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(textTheme, '일정 · 현장', [
                    OutlinedButton.icon(
                      onPressed: _pickScheduleDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 20),
                      label: Text(
                        _scheduleDate == null
                            ? '일정 선택 (DatePicker)'
                            : '일정: ${_formatDate(_scheduleDate!)}',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _accent,
                        side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '출장 여부',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(
                          value: false,
                          label: Text('방문 시공'),
                          icon: Icon(Icons.storefront_outlined, size: 18),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          label: Text('출장 시공'),
                          icon: Icon(Icons.local_shipping_outlined, size: 18),
                        ),
                      ],
                      selected: <bool>{_isOnSite},
                      onSelectionChanged: (set) {
                        setState(() => _isOnSite = set.first);
                      },
                      style: ButtonStyle(
                        foregroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? _accent
                              : Colors.black87,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(textTheme, '조건 · 금액', [
                    Text(
                      '자재 조건',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '자재 제공 범위',
                      style: textTheme.labelMedium?.copyWith(
                        color: Colors.grey.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final o in _materialOptions)
                          ChoiceChip(
                            label: Text(o),
                            selected: _materialCondition == o,
                            onSelected: (_) =>
                                setState(() => _materialCondition = o),
                            selectedColor: _accent.withValues(alpha: 0.2),
                            labelStyle: textTheme.labelLarge?.copyWith(
                              color: _materialCondition == o
                                  ? _accent
                                  : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: '희망 금액 (선택)',
                        hint: '숫자만 입력 (원 단위 등)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '긴급 모집',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '리스트에 긴급 배지로 표시됩니다.',
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                      value: _isUrgent,
                      activeTrackColor: _accent.withValues(alpha: 0.45),
                      activeThumbColor: _accent,
                      onChanged: (v) => setState(() => _isUrgent = v),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(textTheme, '상세 내용', [
                    TextField(
                      controller: _descriptionController,
                      maxLines: 6,
                      minLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: _fieldDecoration(
                        label: '상세 내용 *',
                        hint:
                            '작업 범위, 차종, 필요 인력, 소통 방식 등 구체적으로 적어 주세요.',
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: FilledButton(
                onPressed: _onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('협업 요청 등록'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 사업자명 → 매장이름 → 대표자명 → 별명 순으로 앱에 표시할 이름을 고릅니다.
String computePoAppDisplayName({
  required String businessName,
  required String storeName,
  required String representativeName,
  required String nickname,
}) {
  String t(String v) => v.trim();
  if (t(businessName).isNotEmpty) return t(businessName);
  if (t(storeName).isNotEmpty) return t(storeName);
  if (t(representativeName).isNotEmpty) return t(representativeName);
  if (t(nickname).isNotEmpty) return t(nickname);
  return '이름을 입력해주세요';
}

/// 업체 · 프로필 정보 관리
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const Color _accent = Color(0xFF007AFF);

  late final TextEditingController _loginEmailController;
  late final TextEditingController _googleNameController;
  late final TextEditingController _bizRegNumberController;
  late final TextEditingController _businessNameController;
  late final TextEditingController _repNameController;
  late final TextEditingController _businessPhoneController;
  late final TextEditingController _storeNameController;
  late final TextEditingController _nicknameController;
  late final TextEditingController _appDisplayNameController;

  /// 선택된 서비스 라인: `메인\u001f서브`(내부 키, Firestore에는 펼쳐서 저장).
  var _selectedServiceKeys = <String>{};

  /// 서브 라벨 기준 선택(체크) 순서 — searchCategories · categoryPriority · primary 에 사용.
  var _orderedSubLabels = <String>[];

  /// 협업 매칭용(별도 폼 미노출 — 기본값으로 유지 가능).
  var _matchingIsAvailable = true;
  final List<String> _matchingRegions = [];
  String _matchingPriceRange = '';
  String _matchingResponseSpeed = '';

  void _onProfileFieldChanged() {
    _appDisplayNameController.text = computePoAppDisplayName(
      businessName: _businessNameController.text,
      storeName: _storeNameController.text,
      representativeName: _repNameController.text,
      nickname: _nicknameController.text,
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade800,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: _accent,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }

  InputDecoration _readonlyFieldDecoration({
    required String label,
    required String hint,
  }) {
    return _fieldDecoration(label: label, hint: hint).copyWith(
      fillColor: Colors.grey.shade50,
    );
  }

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _loginEmailController = TextEditingController(text: user?.email ?? '-');
    _googleNameController =
        TextEditingController(text: user?.displayName ?? '-');
    _bizRegNumberController = TextEditingController();
    _businessNameController = TextEditingController();
    _repNameController = TextEditingController();
    _businessPhoneController = TextEditingController();
    _storeNameController = TextEditingController();
    _nicknameController = TextEditingController();
    _appDisplayNameController = TextEditingController();
    _onProfileFieldChanged();
    _businessNameController.addListener(_onProfileFieldChanged);
    _storeNameController.addListener(_onProfileFieldChanged);
    _repNameController.addListener(_onProfileFieldChanged);
    _nicknameController.addListener(_onProfileFieldChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadFirestoreProfile();
    });
  }

  /// Firestore 문서 문자열 필드 로드 후 컨트롤러 및 시공 분야 선택 반영.
  Future<void> _loadFirestoreProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    DocumentSnapshot<Map<String, dynamic>>? snap;
    try {
      snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
    } catch (_) {
      snap = null;
    }

    if (!mounted) return;
    final data = snap?.data();
    if (data == null) return;
    _applyFirestoreProfile(data);
  }

  String? _firestoreTrimmedText(dynamic raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

  void _hydrateEditableField(TextEditingController c, Map<String, dynamic> d,
      List<String> fieldKeys) {
    for (final key in fieldKeys) {
      final text = _firestoreTrimmedText(d[key]);
      if (text != null) {
        if (c.text != text) c.text = text;
        break;
      }
    }
  }

  /// `users/{uid}` 문서를 현재 폼에 합류(충돌 시 Firestore 우선 적용 후 표시 이름 재계산).
  void _applyFirestoreProfile(Map<String, dynamic> doc) {
    _hydrateEditableField(_bizRegNumberController, doc, const ['bizRegNumber']);
    _hydrateEditableField(_businessNameController, doc,
        const ['businessName']);
    _hydrateEditableField(
      _repNameController,
      doc,
      const ['representativeName', 'repName'],
    );
    _hydrateEditableField(_businessPhoneController, doc,
        const ['businessPhone']);
    _hydrateEditableField(_storeNameController, doc, const ['storeName']);
    _hydrateEditableField(_nicknameController, doc, const ['nickname']);

    final nextKeys = ServiceCategoryCatalog.selectionKeysFromFirestore(
      serviceCategories: doc['serviceCategories'],
    );

    setState(() {
      _selectedServiceKeys = nextKeys;
      final subs = ServiceCategoryCatalog.distinctSubs(nextKeys);
      _orderedSubLabels = _restoreSubOrderFromDoc(doc, subs);
      _hydrateMatchingFields(doc);
    });
    _onProfileFieldChanged();
  }

  List<String> _restoreSubOrderFromDoc(
      Map<String, dynamic> doc, Set<String> validSubs,) {
    if (validSubs.isEmpty) return [];
    final fromPriority = _subOrderFromCategoryPriority(
      doc['categoryPriority'],
      validSubs,
    );
    if (fromPriority.isNotEmpty) {
      final rest =
          validSubs.where((s) => !fromPriority.contains(s)).toList()..sort();
      return [...fromPriority, ...rest];
    }
    final fromSearch =
        _subOrderFromSearchCategories(doc['searchCategories'], validSubs);
    if (fromSearch.isNotEmpty) {
      final rest =
          validSubs.where((s) => !fromSearch.contains(s)).toList()..sort();
      return [...fromSearch, ...rest];
    }
    final alpha = validSubs.toList()..sort();
    return alpha;
  }

  /// `categoryPriority` 맵 값(숫자) 오름차순으로 서브 목록 생성.
  List<String> _subOrderFromCategoryPriority(
      dynamic raw, Set<String> validSubs,) {
    if (raw is! Map) return [];

    final rows = <MapEntry<String, int>>[];
    for (final rawEntry in raw.entries) {
      final k = rawEntry.key;
      final v = rawEntry.value;
      if (k is! String || v is! num) continue;
      final sub = k.trim();
      if (!validSubs.contains(sub)) continue;
      rows.add(MapEntry(sub, v.round()));
    }
    if (rows.isEmpty) return [];
    rows.sort((a, b) => a.value.compareTo(b.value));

    final out = <String>[];
    final seen = <String>{};
    for (final row in rows) {
      if (seen.add(row.key)) out.add(row.key);
    }
    return out;
  }

  /// `searchCategories` 배열 순서를 유지하되, 현재 선택에 없는 라벨은 제외.
  List<String> _subOrderFromSearchCategories(
      dynamic raw, Set<String> validSubs,) {
    if (raw is! List<dynamic>) return [];
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      if (item is! String) continue;
      final sub = item.trim();
      if (!validSubs.contains(sub)) continue;
      if (seen.add(sub)) out.add(sub);
    }
    return out;
  }

  void _hydrateMatchingFields(Map<String, dynamic> doc) {
    final av = doc['isAvailable'];
    _matchingIsAvailable = av is bool ? av : true;

    final normalized = PoRegionFields.fromUserMap(doc);
    _matchingRegions.clear();
    if (normalized.regionFull.isNotEmpty) {
      _matchingRegions.add(normalized.regionFull);
    } else {
      final reg = doc['regions'];
      if (reg is List<dynamic>) {
        _matchingRegions.addAll(
          reg
              .whereType<String>()
              .map((String s) => s.trim())
              .where((String s) => s.isNotEmpty),
        );
      }
    }

    final pr = doc['priceRange'];
    _matchingPriceRange = pr is String ? pr.trim() : '';

    final rs = doc['responseSpeed'];
    _matchingResponseSpeed = rs is String ? rs.trim() : '';
  }

  /// 체크 집합이 바뀐 뒤 서브 순서 유지 · 신규는 맨 뒤.
  void _syncOrderedSubLabels(Set<String> newKeys) {
    final subs = ServiceCategoryCatalog.distinctSubs(newKeys);
    _orderedSubLabels.removeWhere((String s) => !subs.contains(s));
    for (final s in subs) {
      if (!_orderedSubLabels.contains(s)) {
        _orderedSubLabels.add(s);
      }
    }
  }

  List<String> _buildSearchCategories() =>
      List<String>.from(_orderedSubLabels);

  String _computePrimaryCategory() =>
      _orderedSubLabels.isEmpty ? '' : _orderedSubLabels.first;

  Map<String, int> _buildCategoryPriority() => <String, int>{
        for (var i = 0; i < _orderedSubLabels.length; i++)
          _orderedSubLabels[i]: i + 1,
      };

  void _toggleServiceSelection(String main, String sub, bool selected) {
    setState(() {
      _selectedServiceKeys = ServiceCategoryCatalog.toggledSelectionSet(
        current: _selectedServiceKeys,
        main: main,
        sub: sub,
        selected: selected,
      );
      _syncOrderedSubLabels(_selectedServiceKeys);
    });
  }

  Widget _buildConstructionAreasSection(TextTheme textTheme) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        dividerColor: Colors.grey.shade200,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0;
                  i < ServiceCategoryCatalog.mainTitles.length;
                  i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.grey.shade200,
                  ),
                _ConstructionMainCategoryTile(
                  mainTitle: ServiceCategoryCatalog.mainTitles[i],
                  selectedKeys: _selectedServiceKeys,
                  accent: _accent,
                  textTheme: textTheme,
                  onToggle: _toggleServiceSelection,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _persistUserProfileFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('저장할 수 없습니다. 로그인이 필요합니다.');
    }

    final mainCategories =
        ServiceCategoryCatalog.buildMainCategoriesList(_selectedServiceKeys);
    final serviceCategories =
        ServiceCategoryCatalog.buildServiceMaps(_selectedServiceKeys);

    final searchCategories = _buildSearchCategories();
    final primaryCategory = _computePrimaryCategory();
    final categoryPriority = _buildCategoryPriority();

    final regionLine = _matchingRegions
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .join(' ');
    final regionPack = PoRegionFields.fromRegionFull(regionLine);

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      <String, Object?>{
        'bizRegNumber': _bizRegNumberController.text.trim(),
        'businessName': _businessNameController.text.trim(),
        'representativeName': _repNameController.text.trim(),
        'businessPhone': _businessPhoneController.text.trim(),
        'storeName': _storeNameController.text.trim(),
        'nickname': _nicknameController.text.trim(),
        'appDisplayName': _appDisplayNameController.text.trim(),
        'mainCategories': mainCategories,
        'serviceCategories': serviceCategories,
        'searchCategories': searchCategories,
        'primaryCategory': primaryCategory,
        'categoryPriority': categoryPriority,
        'isAvailable': _matchingIsAvailable,
        ...poRegionUserFirestoreMap(regionPack),
        'priceRange': _matchingPriceRange,
        'responseSpeed': _matchingResponseSpeed,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _saveProfileTap() async {
    FocusScope.of(context).unfocus();
    if (!context.mounted) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    bool dialogOpen = false;
    Object? caught;

    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.25),
        builder: (ctx) => Center(
          child: CircularProgressIndicator(
            color: Theme.of(ctx).colorScheme.primary,
          ),
        ),
      );
      dialogOpen = true;
      await _persistUserProfileFirestore();
    } on Object catch (e) {
      caught = e;
    } finally {
      if (dialogOpen && context.mounted) {
        navigator.pop();
      }
    }

    if (!context.mounted) return;
    final msg =
        caught == null ? '저장했습니다' : '저장하지 못했습니다: $caught';
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _businessNameController.removeListener(_onProfileFieldChanged);
    _storeNameController.removeListener(_onProfileFieldChanged);
    _repNameController.removeListener(_onProfileFieldChanged);
    _nicknameController.removeListener(_onProfileFieldChanged);
    _loginEmailController.dispose();
    _googleNameController.dispose();
    _bizRegNumberController.dispose();
    _businessNameController.dispose();
    _repNameController.dispose();
    _businessPhoneController.dispose();
    _storeNameController.dispose();
    _nicknameController.dispose();
    _appDisplayNameController.dispose();
    super.dispose();
  }

  Widget _sectionLabel(String title, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        title,
        style: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  Widget _buildAvatarHeader(TextTheme textTheme) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = user?.photoURL;
    return Center(
      child: Column(
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.person_outline_rounded,
                      size: 44,
                      color: Colors.grey.shade500,
                    ),
                  )
                : Icon(
                    Icons.storefront_outlined,
                    size: 44,
                    color: Colors.grey.shade500,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            '프로필 사진 · 로고',
            style: textTheme.labelMedium?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          MyApp.appBarTitle,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildAvatarHeader(textTheme),
                  const SizedBox(height: 20),
                  _sectionLabel('[로그인 계정 정보]', textTheme),
                  TextField(
                    readOnly: true,
                    enableInteractiveSelection: true,
                    controller: _loginEmailController,
                    decoration: _readonlyFieldDecoration(
                      label: '로그인 이메일',
                      hint: 'Google 로그인 계정',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    readOnly: true,
                    enableInteractiveSelection: true,
                    controller: _googleNameController,
                    decoration: _readonlyFieldDecoration(
                      label: 'Google 이름',
                      hint: '표시 이름',
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('[사업자 인증 정보]', textTheme),
                  TextField(
                    controller: _bizRegNumberController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '사업자등록번호',
                      hint: '000-00-00000',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _businessNameController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '사업자명',
                      hint: '등록 상호 입력',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _repNameController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '대표자명',
                      hint: '대표자 이름',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _businessPhoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '휴대폰번호',
                      hint: '예: 010-0000-0000',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '사업자등록증 인증 상태',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 20,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          '미인증 · 서류 제출 대기',
                          style: textTheme.labelMedium?.copyWith(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('[매장/브랜드 정보]', textTheme),
                  TextField(
                    controller: _storeNameController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '매장이름',
                      hint: '매장 상호 또는 지점명',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nicknameController,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(
                      label: '별명',
                      hint: '앱에서 부를 이름',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    readOnly: true,
                    controller: _appDisplayNameController,
                    decoration: _readonlyFieldDecoration(
                      label: '앱 표시 이름',
                      hint: '위 항목 기준으로 자동 계산됩니다',
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionLabel('[시공 분야]', textTheme),
                  Text(
                    '메인을 탭해서 펼치고, 세부 분야를 체크하면 바로 반영됩니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildConstructionAreasSection(textTheme),
                  const SizedBox(height: 22),
                  _sectionLabel('[마감 디테일]', textTheme),
                  Text(
                    '시공 마감 기준·사진을 등록하면 업체 프로필에 노출됩니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      runWithBriefLoading(context, () {
                        if (!context.mounted) return;
                        Navigator.of(context).push(poSmoothPushRoute<void>(
                          const FinishDetailCreateScreen(),
                        ));
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    label: const Text('마감 디테일 등록'),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              height: 54,
              width: double.infinity,
                child: FilledButton(
                onPressed: _saveProfileTap,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('정보 저장'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 마감 디테일 등록 — Storage `finish_details/{uid}/{timestamp}.jpg` 후
/// `users/{uid}/finishDetails/{docId}` 저장.
class FinishDetailCreateScreen extends StatefulWidget {
  const FinishDetailCreateScreen({super.key});

  @override
  State<FinishDetailCreateScreen> createState() =>
      _FinishDetailCreateScreenState();
}

class _FinishDetailCreateScreenState extends State<FinishDetailCreateScreen> {
  static const Color _accent = Color(0xFF007AFF);

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();

  String? _imagePath;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  InputDecoration _decoration({required String label, required String hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
      labelStyle: TextStyle(
        color: Colors.grey.shade800,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: _accent,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (x == null || !mounted) return;
    setState(() => _imagePath = x.path);
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인이 필요합니다.')),
      );
      return;
    }

    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();
    final category = _categoryController.text.trim();
    if (title.isEmpty ||
        description.isEmpty ||
        category.isEmpty ||
        _imagePath == null ||
        _imagePath!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('제목·설명·카테고리·이미지를 모두 입력해 주세요.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance.ref(
        'finish_details/${user.uid}/$timestamp.jpg',
      );
      await storageRef.putFile(
        File(_imagePath!),
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final imageUrl = await storageRef.getDownloadURL();

      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('finishDetails')
          .doc();

      await docRef.set(<String, Object?>{
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'category': category,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('마감 디테일이 등록되었습니다.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('등록에 실패했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '마감 디테일 등록',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '이미지는 Firebase Storage에 저장되며, 완료 후 업체 프로필에 표시됩니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titleController,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      label: '제목',
                      hint: '예: 도어 라인 PPF 마감 기준',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _categoryController,
                    textInputAction: TextInputAction.next,
                    decoration: _decoration(
                      label: '카테고리',
                      hint: '예: PPF · 외장',
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 5,
                    minLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: _decoration(
                      label: '설명',
                      hint: '마감·이물·버블 기준 등',
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickImage,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('갤러리에서 이미지 선택'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _accent,
                      side: BorderSide(color: _accent.withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_imagePath != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Image.file(
                          File(_imagePath!),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              height: 54,
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('등록하기'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConstructionMainCategoryTile extends StatelessWidget {
  const _ConstructionMainCategoryTile({
    required this.mainTitle,
    required this.selectedKeys,
    required this.accent,
    required this.textTheme,
    required this.onToggle,
  });

  final String mainTitle;
  final Set<String> selectedKeys;
  final Color accent;
  final TextTheme textTheme;
  final void Function(String main, String sub, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    final subs = ServiceCategoryCatalog.servicesForMain(mainTitle);
    return ExpansionTile(
      tilePadding: const EdgeInsets.only(left: 12, right: 12),
      collapsedIconColor: Colors.grey.shade600,
      iconColor: accent,
      shape: Border.all(color: Colors.transparent),
      collapsedShape: Border.all(color: Colors.transparent),
      title: Text(
        mainTitle,
        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      childrenPadding: EdgeInsets.zero,
      children: [
        for (final sub in subs)
          CheckboxListTile(
            value:
                selectedKeys.contains(ServiceCategoryCatalog.selectionKey(mainTitle, sub)),
            onChanged: (v) => onToggle(mainTitle, sub, v ?? false),
            title: Text(
              sub,
              style: textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            activeColor: accent,
          ),
      ],
    );
  }
}

class _DashedRoundRectPainter extends CustomPainter {
  const _DashedRoundRectPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 1.5,
  });

  static const double _dashLength = 6;
  static const double _gapLength = 4;

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      math.max(0.0, size.width - strokeWidth),
      math.max(0.0, size.height - strokeWidth),
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundRectPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.radius != radius ||
      oldDelegate.strokeWidth != strokeWidth;
}

class _CollaborationCard extends StatelessWidget {
  const _CollaborationCard({
    required this.title,
    required this.region,
    required this.when,
    this.accentLine = '',
    this.titleStatusChip,
    this.showUrgentBadge = false,
    this.description = '',
    required this.onTap,
  });

  final String title;
  final String region;
  final String when;
  /// 상태가 마감 등일 때 강조 보조 줄(홈).
  final String accentLine;
  /// 모집중/마감/완료 칩(요청 탭 등).
  final String? titleStatusChip;
  final bool showUrgentBadge;
  final String description;
  final VoidCallback onTap;

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.white,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                Text(
                                  title,
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                    height: 1.35,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                if (showUrgentBadge)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      '긴급',
                                      style: textTheme.labelSmall?.copyWith(
                                        color: Colors.red.shade800,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                if (titleStatusChip != null &&
                                    titleStatusChip!.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color:
                                              _accent.withValues(alpha: 0.25)),
                                    ),
                                    child: Text(
                                      titleStatusChip!,
                                      style: textTheme.labelSmall?.copyWith(
                                        color: _accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.grey.shade400,
                            size: 22,
                          ),
                        ],
                      ),
                      if (accentLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          accentLine,
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _accent,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(Icons.place_outlined,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            region,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              when,
                              style: textTheme.labelSmall?.copyWith(
                                color: _accent,
                                fontWeight: FontWeight.w600,
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
          ],
        ),
      ),
    );
  }
}

class _SocialLoginButton extends StatelessWidget {
  const _SocialLoginButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.borderSide,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;
  final BorderSide? borderSide;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: LoginScreen._btnHeight,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(LoginScreen._btnRadius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(LoginScreen._btnRadius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LoginScreen._btnRadius),
              border: borderSide != null
                  ? Border.fromBorderSide(borderSide!)
                  : null,
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: foregroundColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
