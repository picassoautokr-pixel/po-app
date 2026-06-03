import 'dart:math' as math;
import 'dart:ui' show PathMetric;
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
import '../service_category_catalog.dart';

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

