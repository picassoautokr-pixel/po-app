import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/firestore_utils.dart';
import '../core/navigation.dart';
import '../core/layout_utils.dart';

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
    poShowBusinessPhoneSheet(context, data);
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
                if (poBusinessVerificationShowVerifiedBadge(data))
                  Padding(
                    padding: const EdgeInsets.only(right: 4, top: 2),
                    child: poVerifiedCompanyBadgeChip(fontSize: 10),
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
