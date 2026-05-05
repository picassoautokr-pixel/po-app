part of '../main.dart';

class MyPageTabScreenV2 extends StatelessWidget {
  const MyPageTabScreenV2({super.key});

  static const Color _accent = Color(0xFF007AFF);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fbUser = FirebaseAuth.instance.currentUser;
    final uid = fbUser?.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: uid == null
            ? Center(
                child: Text(
                  '로그인 정보가 없습니다.',
                  style: textTheme.bodyMedium,
                ),
              )
            : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .snapshots(),
                builder: (context, snap) {
                  final data = snap.data?.data();

                  final appName = _matchingFieldStr(data?['appDisplayName']).isEmpty
                      ? '-'
                      : _matchingFieldStr(data?['appDisplayName']);

                  final mainsRaw = data?['mainCategories'];
                  final mains = mainsRaw is Iterable
                      ? mainsRaw.whereType<String>().join(' · ')
                      : '';

                  final searchRaw = data?['searchCategories'];
                  final searchLine = searchRaw is Iterable
                      ? searchRaw.whereType<String>().take(8).join(' · ')
                      : '';

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '마이페이지',
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 20),
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
                                  '로그인 이메일',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                SelectableText(
                                  fbUser?.email ?? '-',
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  '앱 표시 이름',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  appName,
                                  style: textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () {
                            runWithBriefLoading(context, () {
                              if (!context.mounted) return;
                              Navigator.of(context).push(poSmoothPushRoute<void>(
                                const ProfileScreen(),
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
                          child: const Text('프로필 관리'),
                        ),
                        const SizedBox(height: 10),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '사업자 인증 상태',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '미인증 · 서류 제출 대기',
                                  style: textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '시공 분야 요약',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          mains.isEmpty ? '프로필에서 시공 분야를 설정해 주세요.' : mains,
                          style: textTheme.bodyMedium?.copyWith(height: 1.4),
                        ),
                        if (searchLine.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            searchLine,
                            style: textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Text(
                          '개발 도구',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await seedDevFirestoreTestData();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '테스트 데이터가 생성되었습니다.\n'
                                    '매칭 테스트 업체가 생성되었습니다.',
                                  ),
                                ),
                              );
                            } on Object catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('테스트 데이터 생성 실패: $e')),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.deepOrange.shade800,
                            side: BorderSide(
                              color: Colors.deepOrange.withValues(alpha: 0.5),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.dataset_outlined),
                          label: const Text('테스트 데이터 생성'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'users(test_user_*·test_match_user_*) · collaborationRequests(test_request_*)',
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () async {
                            await GoogleSignIn().signOut();
                            await FirebaseAuth.instance.signOut();
                            if (!context.mounted) return;
                            Navigator.of(context).pushAndRemoveUntil(
                              poFadeReplaceRoute<void>(const LoginScreen()),
                              (_) => false,
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.grey.shade800,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('로그아웃'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
