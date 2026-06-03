import 'dart:async' show StreamSubscription, unawaited;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PathMetric;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

// 모바일 전용 패키지 - 웹에서는 컴파일되지 않음
// ignore: uri_does_not_exist
import 'platform_io.dart' if (dart.library.html) 'platform_web.dart';

import 'dev_firestore_test_seed.dart';
import 'firebase_options.dart';
import 'models/collaboration_matching_candidate.dart';
import 'region_normalize.dart';
import 'service_category_catalog.dart';

part 'tabs/feed_shell_part.dart';
part 'tabs/home_tab_part.dart';
part 'tabs/requests_tab_part.dart';
part 'tabs/chat_tab_part.dart';
part 'tabs/favorite_partners_tab_part.dart';
part 'tabs/my_page_tab_part.dart';
part 'tabs/collaboration_feed_tab_part.dart';
part 'notification_screen_part.dart';
part 'business_verification_screen_part.dart';
part 'admin_screens_part.dart';
part 'business_claim_part.dart';
part 'business_bulk_upload_part.dart';
part 'screens/owner_request_detail_screen.dart';
part 'screens/evaluation_screen.dart';
part 'screens/partner_request_detail_screen.dart';
part 'screens/apply_to_request_screen.dart';
part 'screens/request_applications_screen.dart';
part 'screens/company_detail_screen.dart';
part 'screens/image_gallery_screen.dart';
part 'screens/chat_screen.dart';
part 'screens/matching_screen.dart';
part 'screens/collaboration_complete_screen.dart';
part 'screens/review_screen.dart';
part 'screens/collaboration_request_create_screen.dart';
part 'screens/profile_screen.dart';
part 'screens/finish_detail_create_screen.dart';

// ---------------------------------------------------------------------------
// Firestore 로드 오류 UX — UI에는 일반 문구만, [debugPrint]에 원본 에러.
// ---------------------------------------------------------------------------

const String poFirestoreLoadErrorTitle =
    '데이터를 불러오는 중 문제가 발생했습니다.';
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
          style: tt.bodyMedium?.copyWith(
            color: Colors.grey.shade600,
            height: 1.45,
          ),
        ),
      ],
    ),
  );
}

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
            padding: EdgeInsets.fromLTRB(
              28,
              16,
              28,
              poFullScreenScrollBottomPadding(context),
            ),
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

double _poMediaBottomInset(BuildContext context) =>
    MediaQuery.paddingOf(context).bottom;

/// 풀스크린 스크롤: 시스템 내비/제스처 [padding.bottom] + [extra].
double poFullScreenScrollBottomPadding(BuildContext context,
        {double extra = 100}) =>
    _poMediaBottomInset(context) + extra;

/// [MainShell] 탭 본문 리스트 — 하단 탭·시스템 내비로 가려지지 않게.
double poMainShellTabScrollBottomPadding(BuildContext context,
        {double extra = 110}) =>
    _poMediaBottomInset(context) + extra;

/// 모달 바텀시트 내부 스크롤/고정 패딩.
double poBottomSheetContentBottomPadding(BuildContext context,
        {double extra = 44}) =>
    _poMediaBottomInset(context) + extra;

String _collaborationRequestString(dynamic v) =>
    v is String ? v.trim() : '';

/// 피드·상세·카드 공통: 공고 마감 표시 줄 (`deadlineText` 없으면 `-`).
String _collaborationRecruitmentDeadlineLine(Map<String, dynamic>? data) {
  if (data == null) return '-';
  final t = _collaborationRequestString(data['deadlineText']);
  return t.isEmpty ? '-' : t;
}

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

/// 내 지원 문서 `applications.status` → 통일 표시명.
String collaborationMyApplicationStatusLabelKo(dynamic statusRaw) {
  final s = _collaborationRequestString(statusRaw).toLowerCase();
  if (s.isEmpty) return '승인대기';
  switch (s) {
    case 'pending':
      return '승인대기';
    case 'accepted':
      return '채택됨';
    case 'in_progress':
      return '진행중';
    case 'completed':
    case 'complete':
    case 'done':
      return '완료';
    case 'rejected':
      return '거절됨';
    case 'cancelled':
      return '취소됨';
    default:
      final t = _collaborationRequestString(statusRaw);
      return t.isEmpty ? '승인대기' : t;
  }
}

({Color background, Color foreground}) collaborationMyApplicationBadgeStyle(
  dynamic statusRaw,
) {
  final s = _collaborationRequestString(statusRaw).toLowerCase();
  if (s.isEmpty || s == 'pending') {
    return (
      background: const Color(0xFFE3F2FD),
      foreground: const Color(0xFF1565C0),
    );
  }
  switch (s) {
    case 'accepted':
      return (
        background: const Color(0xFF1976D2),
        foreground: Colors.white,
      );
    case 'in_progress':
      return (
        background: const Color(0xFF2E7D32),
        foreground: Colors.white,
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

/// collaborationRequests/.../applications 의 status 표시용 (작성자·지원목록 카드 등).
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

/// `collectionGroup('applications').where(applicantUid).orderBy('createdAt')` 등 인덱스 안내 문구.
String collaborationApplicationsIndexHint() {
  return 'Firestore 인덱스가 필요할 수 있습니다.\n'
      '콘솔 오류 링크로 복합 인덱스를 생성해 주세요.\n'
      '컬렉션 그룹: applications\n'
      '필드: applicantUid (==), createdAt (desc)';
}

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

/// 앱 내부 알림 — [userId]가 비어 있으면 저장하지 않습니다.
Future<void> createNotification({
  required String userId,
  required String type,
  required String title,
  required String body,
  required String targetId,
  required String targetType,
}) async {
  final uid = userId.trim();
  if (uid.isEmpty) return;

  final ref = FirebaseFirestore.instance.collection('notifications').doc();
  await ref.set(<String, Object?>{
    'notificationId': ref.id,
    'userId': uid,
    'type': type.trim(),
    'title': title.trim(),
    'body': body.trim(),
    'targetId': targetId.trim(),
    'targetType': targetType.trim(),
    'isRead': false,
    'createdAt': FieldValue.serverTimestamp(),
  });
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
      'unreadCountByUser.${myUid.trim()}': 0,
      'unreadCountByUser.$pu': 0,
    },
    SetOptions(merge: true),
  );
}

/// 메시지 발송 직후: 내 미읽음 0, 상대방 미읽음 +1 (`unreadCountByUser`).
Future<void> collaborationApplyOutgoingUnreadCounts({
  required String chatId,
  required String myUid,
  required String partnerUid,
}) async {
  final c = chatId.trim();
  final me = myUid.trim();
  final pu = partnerUid.trim();
  if (c.isEmpty || me.isEmpty || pu.isEmpty || me == pu) return;

  await FirebaseFirestore.instance.collection('chats').doc(c).set(
    <String, Object?>{
      'unreadCountByUser.$me': 0,
      'unreadCountByUser.$pu': FieldValue.increment(1),
    },
    SetOptions(merge: true),
  );
}

/// 채팅방 입장 시 현재 사용자의 미읽음을 0으로 초기화합니다.
Future<void> collaborationResetUnreadForUserInChat({
  required String chatId,
  required String userUid,
}) async {
  final c = chatId.trim();
  final u = userUid.trim();
  if (c.isEmpty || u.isEmpty) return;

  await FirebaseFirestore.instance.collection('chats').doc(c).set(
    <String, Object?>{
      'unreadCountByUser.$u': 0,
    },
    SetOptions(merge: true),
  );
}

/// [chats] 스냅샷에서 현재 사용자 미읽음 합계.
int poChatUnreadTotalForUser(
  QuerySnapshot<Map<String, dynamic>> snap,
  String uid,
) {
  final u = uid.trim();
  if (u.isEmpty) return 0;
  var t = 0;
  for (final d in snap.docs) {
    final raw = d.data()['unreadCountByUser'];
    if (raw is Map<dynamic, dynamic>) {
      final v = raw[u];
      if (v is num) {
        t += v.round().clamp(0, 999999);
      }
    }
  }
  return t;
}

Widget _poChatBottomNavIcon(int unread, {required bool selected}) {
  return Stack(
    clipBehavior: Clip.none,
    alignment: Alignment.topRight,
    children: [
      Icon(
        selected ? Icons.chat_rounded : Icons.chat_bubble_outline_rounded,
      ),
      if (unread > 0)
        Positioned(
          right: -6,
          top: -4,
          child: IgnorePointer(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: unread > 9 ? 5 : 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(999),
              ),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              alignment: Alignment.center,
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
    ],
  );
}

List<BottomNavigationBarItem> _poMainShellBottomNavItems(int chatUnread) {
  return <BottomNavigationBarItem>[
    const BottomNavigationBarItem(
      icon: Icon(Icons.home_outlined),
      activeIcon: Icon(Icons.home_rounded),
      label: '홈',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.handshake_outlined),
      activeIcon: Icon(Icons.handshake),
      label: '구인·협업',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.note_add_outlined),
      activeIcon: Icon(Icons.note_add),
      label: '내 요청',
    ),
    BottomNavigationBarItem(
      icon: _poChatBottomNavIcon(chatUnread, selected: false),
      activeIcon: _poChatBottomNavIcon(chatUnread, selected: true),
      label: '채팅',
    ),
    const BottomNavigationBarItem(
      icon: Icon(Icons.star_border_rounded),
      activeIcon: Icon(Icons.star_rounded),
      label: '즐겨찾기',
    ),
  ];
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
    case 'unverified':
      return 'unverified';
    default:
      return 'unverified';
  }
}

/// UI·마이페이지용: `verifiedBusiness == true` 이면 검증 완료로 간주.
String poBusinessVerificationUiState(Map<String, dynamic>? doc) {
  if (doc == null) return 'unverified';
  final vb = doc['verifiedBusiness'];
  if (vb == true) return 'verified';
  return poNormalizeBusinessVerificationStatus(
    doc['businessVerificationStatus'],
  );
}

bool poBusinessVerificationShowVerifiedBadge(Map<String, dynamic>? d) {
  if (d == null) return false;
  final vb = d['verifiedBusiness'];
  if (vb == true) return true;
  if (poNormalizeBusinessVerificationStatus(d['businessVerificationStatus']) ==
      'verified') {
    return true;
  }
  final legacy = d['businessLicenseStatus'];
  return legacy == true;
}

/// `users.role` 기준 관리자 (기본 사용자는 필드 없음 → 일반 사용자).
///
/// 보안 참고:
/// 관리자 UI는 클라에서만 숨김 처리합니다. 모든 승인/반려 쓰기는
/// [Firestore Security Rules에서 role==admin만 허용]하도록 강화해야 합니다.
bool poIsAdminUser(Map<String, dynamic>? userDoc) =>
    _matchingFieldStr(userDoc?['role']).toLowerCase() == 'admin';

Widget poVerifiedCompanyBadgeChip({double fontSize = 11}) {
  return DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFF1565C0),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(
        '인증업체',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          height: 1.15,
        ),
      ),
    ),
  );
}

/// 마이페이지·프로필 본인용 상태 한 줄 안내.
String poBusinessVerificationMyPageLine(String normalized) {
  switch (normalized) {
    case 'pending':
      return '심사중 · 제출 서류 검토 후 안내합니다.';
    case 'verified':
      return '인증업체 · 사업자 인증이 완료되었습니다.';
    case 'rejected':
      return '반려됨 · 사유 확인 후 재신청할 수 있습니다.';
    case 'unverified':
    default:
      return '미인증 · 사업자 인증 신청을 진행해 주세요.';
  }
}

String _companyProfileLicenseStatus(Map<String, dynamic> d) {
  if (poBusinessVerificationShowVerifiedBadge(d)) return '인증업체';
  final v = d['businessLicenseStatus'];
  if (v is bool && v == true) return '인증업체';
  if (v == null) return '미인증';
  if (v is bool) {
    return v ? '인증업체' : '미인증';
  }
  if (v is String) {
    final t = v.trim();
    if (t.isEmpty) return '미인증';
    final low = t.toLowerCase();
    if (low == 'verified' || low == '인증' || t == '인증업체') return '인증업체';
    return '미인증';
  }
  return '미인증';
}

String _finishDetailFieldStr(dynamic v) =>
    v is String ? v.trim() : '';

/// imageUrl이 실제 이미지 URL인지 검사.
/// Firebase console 링크·에러 문자열은 이미지로 처리하지 않음.
bool _isValidImageUrl(String url) {
  if (url.isEmpty) return false;
  if (!url.startsWith('http')) return false;
  if (url.contains('console.firebase.google.com')) return false;
  if (url.contains('firestore.googleapis.com')) return false;
  return true;
}

/// Firebase 에러 링크·에러 문자열이 포함된 필드 값을 빈 문자열로 처리.
/// 카드 내부에 에러 문자열이 그대로 노출되는 것을 방지.
String _safeTextOrEmpty(dynamic v) {
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

String _formatFinishDetailCreatedAt(dynamic v) {
  final dt = _firestoreAsDateTime(v);
  if (dt == null) return '-';
  return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

Future<void> _confirmDeleteFinishDetail(
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

int _finishDetailCreatedCompare(
  QueryDocumentSnapshot<Map<String, dynamic>> a,
  QueryDocumentSnapshot<Map<String, dynamic>> b,
) {
  final ta = a.data()['createdAt'];
  final tb = b.data()['createdAt'];
  final da = ta is Timestamp ? ta.millisecondsSinceEpoch : 0;
  final db = tb is Timestamp ? tb.millisecondsSinceEpoch : 0;
  return db.compareTo(da);
}

/// 업체 프로필: `users/{partnerUid}/finishDetails` — 인덱스 없이 스냅샷 후 클라이언트 정렬.
class _CompanyFinishDetailsSection extends StatelessWidget {
  const _CompanyFinishDetailsSection({required this.partnerUid});

  final String partnerUid;

  static const Color _accent = Color(0xFF007AFF);

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
          poReportFirestoreSnapshotError(
            'finishDetails_partner_profile',
            snapshot.error!,
          );
          return poFirestoreUserErrorPlaceholder(
            context,
            verticalPadding: 16,
          );
        }

        final rawDocs = snapshot.data?.docs ?? [];
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          rawDocs,
        )..sort(_finishDetailCreatedCompare);

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
                createdAt: docs[i].data()['createdAt'],
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

/// 내 마감 디테일 목록 — MyPage와 ProfileManagement 화면에서 공통으로 사용.
/// [userId]: 조회할 사용자 UID
/// [editable]: true이면 삭제 버튼 표시
class FinishDetailsListWidget extends StatelessWidget {
  const FinishDetailsListWidget({
    super.key,
    required this.userId,
    this.editable = false,
  });

  final String userId;
  final bool editable;

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('finishDetails')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          debugPrint('[FinishDetailsListWidget] Firestore error: ${snapshot.error}');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '내 마감 디테일',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '마감 디테일을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade600,
                  height: 1.45,
                ),
              ),
            ],
          );
        }

        final rawDocs = snapshot.data?.docs ?? [];
        final docs = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          rawDocs,
        )..sort(_finishDetailCreatedCompare);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '내 마감 디테일',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '등록한 사진과 설명을 확인·삭제할 수 있습니다.',
              style: textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 12),
            if (docs.isEmpty)
              Text(
                '아직 등록된 마감 디테일이 없습니다.',
                style: textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade600,
                ),
              )
            else
              for (var i = 0; i < docs.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                _FinishDetailCard(
                  data: docs[i].data(),
                  createdAt: docs[i].data()['createdAt'],
                  accent: _accent,
                  textTheme: textTheme,
                  onImageTap: (url) =>
                      _showFinishDetailImagePreview(context, url),
                  onDelete: editable
                      ? () => _confirmDeleteFinishDetail(
                            context,
                            docs[i].reference,
                          )
                      : null,
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
    this.createdAt,
    required this.accent,
    required this.textTheme,
    required this.onImageTap,
    this.onDelete,
  });

  final Map<String, dynamic> data;
  final dynamic createdAt;
  final Color accent;
  final TextTheme textTheme;
  final void Function(String? url) onImageTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final title = _safeTextOrEmpty(data['title']);
    final description = _safeTextOrEmpty(data['description']);
    final category = _safeTextOrEmpty(data['category']);
    final rawImageUrl = _finishDetailFieldStr(data['imageUrl']);
    final imageUrl = _isValidImageUrl(rawImageUrl) ? rawImageUrl : '';
    final createdLabel = _formatFinishDetailCreatedAt(createdAt);

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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(13)),
            child: Material(
              color: Colors.grey.shade200,
              child: InkWell(
                onTap:
                    imageUrl.isEmpty ? null : () => onImageTap(imageUrl),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: imageUrl.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.image_not_supported_outlined,
                                size: 38,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '등록된 사진 없음',
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          },
                          errorBuilder:
                              (context, error, stackTrace) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                '이미지를 불러오지 못했습니다.',
                                textAlign: TextAlign.center,
                                style: textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
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
                const SizedBox(height: 8),
                Text(
                  description.isEmpty ? '설명 없음' : description,
                  style: textTheme.bodySmall?.copyWith(
                    color:
                        description.isEmpty
                            ? Colors.grey.shade500
                            : Colors.grey.shade800,
                    height: 1.45,
                  ),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    alignment: Alignment.centerLeft,
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
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    '카테고리: 미등록',
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  '등록일 · $createdLabel',
                  style: textTheme.labelSmall?.copyWith(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onDelete,
                    icon:
                        Icon(Icons.delete_outline, color: Colors.red.shade700),
                    label: Text(
                      '삭제',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.shade200),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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

String _collaborationReqPrimaryCategoryDisplay(Map<String, dynamic>? d) {
  if (d == null) return '-';
  final p = _collaborationRequestString(d['primaryCategory']).trim();
  return p.isEmpty ? '-' : p;
}

/// `serviceCategories`에서 세부 시공분야(서브) 위주로 묶음.
String _collaborationReqDetailServiceCategoriesLine(Map<String, dynamic>? d) {
  if (d == null) return '-';
  final raw = d['serviceCategories'];
  if (raw is! List || raw.isEmpty) return '-';
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
        out.add(sub);
      } else if (main.isNotEmpty) {
        out.add(main);
      }
    }
  }
  return out.isEmpty ? '-' : out.join(' · ');
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
            label: '모집 마감',
            body: _collaborationRecruitmentDeadlineLine(data),
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
    deadlineLine: _collaborationRecruitmentDeadlineLine(d),
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
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.event_available_outlined,
                          size: 16, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '모집 마감 · ${_collaborationRecruitmentDeadlineLine(d)}',
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
                        if (!context.mounted) return;
                        await poShowBusinessPhoneSheet(
                            context, u.data() ?? {});
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
  String? _homeSelectedSortOption;
  /// true = 내림차순(↓), false = 오름차순(↑). [기본순]일 때는 UI·정렬에서 무시.
  bool _homeSortDescending = true;

  String? _collabSelectedSortOption;
  bool _collabSortDescending = true;

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

  void _openSortFilterSheet() {
    final isCollabTab = _tabIndex == 1;
    showPoListSortSheet(
      context: context,
      accent: _accent,
      sortChoices: isCollabTab
          ? kPoListSortChoicesCollab
          : kPoListSortChoicesHome,
      initialSelection:
          isCollabTab ? _collabSelectedSortOption : _homeSelectedSortOption,
      initialDescending:
          isCollabTab ? _collabSortDescending : _homeSortDescending,
      onPick: (opt, desc) {
        if (!mounted) return;
        setState(() {
          if (isCollabTab) {
            _collabSelectedSortOption = opt;
            _collabSortDescending = desc;
          } else {
            _homeSelectedSortOption = opt;
            _homeSortDescending = desc;
          }
        });
      },
    );
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
              child: Builder(
                builder: (ctx) {
                  final nUid = FirebaseAuth.instance.currentUser?.uid;
                  Widget headerBody(int unread) => PoMainListHeader(
                        accent: _accent,
                        regionLabel: _regionFilter.isEmpty
                            ? '전체 지역'
                            : _regionFilter,
                        onRegionTap: _pickRegionDialog,
                        searchController: _searchKeywordController,
                        searchFocusNode: _searchKeywordFocusNode,
                        onSearchChanged: () => setState(() {}),
                        onSearchClear: _clearSearchKeyword,
                        onNotificationTap: () =>
                            _openPoNotifications(context),
                        onProfileTap: _onProfileTap,
                        favoritesOnly: _favoritesOnly,
                        onFavoritesOnlyChanged: (bool v) =>
                            setState(() => _favoritesOnly = v),
                        selectedMainCategories:
                            Set<String>.from(_selectedMainCategories),
                        selectedSubKeys: _subKeys,
                        onOpenCategoryFilter: _openCategoryFilterSheet,
                        selectedSortOption: _tabIndex == 1
                            ? _collabSelectedSortOption
                            : _homeSelectedSortOption,
                        sortDescending: _tabIndex == 1
                            ? _collabSortDescending
                            : _homeSortDescending,
                        onOpenSortSheet: _openSortFilterSheet,
                        notificationUnreadCount: unread,
                      );

                  if (nUid == null) {
                    return headerBody(0);
                  }

                  return StreamBuilder<
                      QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('notifications')
                        .where('userId', isEqualTo: nUid)
                        .where('isRead', isEqualTo: false)
                        .snapshots(),
                    builder: (context, nSnap) {
                      if (nSnap.hasError) {
                        poReportFirestoreSnapshotError(
                          'notifications_unread_badge',
                          nSnap.error!,
                        );
                      }
                      var unread = 0;
                      if (!nSnap.hasError &&
                          nSnap.hasData &&
                          nSnap.data != null) {
                        unread = nSnap.data!.docs.length;
                      }
                      return headerBody(unread);
                    },
                  );
                },
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
                    selectedSortOption: _homeSelectedSortOption,
                    sortDescending: _homeSortDescending,
                  ),
                  CollaborationFeedTabBody(
                    regionFilter: _regionFilter,
                    keyword: _searchKeywordController.text.trim(),
                    selectedMainCategories:
                        Set<String>.from(_selectedMainCategories),
                    subKeySet: Set<String>.from(_subKeys),
                    favoritesOnly: _favoritesOnly,
                    selectedSortOption: _collabSelectedSortOption,
                    sortDescending: _collabSortDescending,
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Builder(
          builder: (ctx) {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null || uid.isEmpty) {
              return BottomNavigationBar(
                currentIndex: _tabIndex,
                onTap: (i) => setState(() => _tabIndex = i),
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.white,
                elevation: 8,
                selectedItemColor: _accent,
                unselectedItemColor: Colors.grey.shade600,
                selectedFontSize: 12,
                unselectedFontSize: 11,
                items: _poMainShellBottomNavItems(0),
              );
            }
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('participants', arrayContains: uid)
                  .snapshots(),
              builder: (context, chatSnap) {
                if (chatSnap.hasError) {
                  poReportFirestoreSnapshotError(
                    'chats_unread_badge',
                    chatSnap.error!,
                  );
                }
                var chatUnread = 0;
                if (!chatSnap.hasError &&
                    chatSnap.hasData &&
                    chatSnap.data != null) {
                  chatUnread =
                      poChatUnreadTotalForUser(chatSnap.data!, uid);
                }
                return BottomNavigationBar(
                  currentIndex: _tabIndex,
                  onTap: (i) => setState(() => _tabIndex = i),
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: Colors.white,
                  elevation: 8,
                  selectedItemColor: _accent,
                  unselectedItemColor: Colors.grey.shade600,
                  selectedFontSize: 12,
                  unselectedFontSize: 11,
                  items: _poMainShellBottomNavItems(chatUnread),
                );
              },
            );
          },
        ),
      ),
    );
  }
}













