import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PathMetric;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/firestore_utils.dart';
import '../core/navigation.dart';
import '../core/layout_utils.dart';
import '../models/collaboration_matching_candidate.dart';
import '../region_normalize.dart';
import '../service_category_catalog.dart';
import '../utils/collaboration_utils.dart';

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

/// AI 추천 매칭: 업체 문서 + 계산된 점수.
