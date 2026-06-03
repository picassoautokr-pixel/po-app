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
