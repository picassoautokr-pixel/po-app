import 'package:cloud_firestore/cloud_firestore.dart';

/// 협업 매칭 후보 모델.
/// [doc]: Firestore 문서 스냅샷, [score]: 매칭 점수.
class CollaborationMatchingCandidate {
  CollaborationMatchingCandidate({
    required this.doc,
    required this.score,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final int score;
}
