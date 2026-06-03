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

class _CollaborationCard extends StatelessWidget {
  const _CollaborationCard({
    required this.title,
    required this.region,
    required this.when,
    required this.deadlineLine,
    this.accentLine = '',
    this.titleStatusChip,
    this.showUrgentBadge = false,
    this.description = '',
    required this.onTap,
  });

  final String title;
  final String region;
  final String when;
  final String deadlineLine;
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
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.event_available_outlined,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '모집 마감 · $deadlineLine',
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
          ],
        ),
      ),
    );
  }
}

