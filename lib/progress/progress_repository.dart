import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'player_profile.dart';

/// Reads player profiles: your own, and the leaderboard.
///
/// Read-only: profiles are written by the progress Cloud Functions alone (see
/// [ProgressService] and firestore.rules).
class ProgressRepository {
  ProgressRepository({required this.uid, FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _db.collection('profiles');

  /// Your profile, or null until the server has created it.
  Stream<PlayerProfile?> watchProfile() => _profiles
      .doc(uid)
      .snapshots()
      .map(
        (DocumentSnapshot<Map<String, dynamic>> doc) =>
            doc.exists ? PlayerProfile.fromDoc(doc) : null,
      );

  /// The top players by lifetime XP.
  ///
  /// Lifetime XP rather than level, so prestiging never costs a place: a
  /// prestige-1 player at level 3 has done more than anyone at level 99.
  Stream<List<PlayerProfile>> watchLeaderboard({int limit = 50}) => _profiles
      .orderBy('totalXp', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (QuerySnapshot<Map<String, dynamic>> snapshot) =>
            snapshot.docs.map(PlayerProfile.fromDoc).toList(),
      );

  /// Your place on the leaderboard, counting from 1. Ties share a place.
  Future<int> rankOf(PlayerProfile me) async {
    final AggregateQuerySnapshot ahead = await _profiles
        .where('totalXp', isGreaterThan: me.totalXp)
        .count()
        .get();
    return (ahead.count ?? 0) + 1;
  }
}

/// The progress actions the server performs for you.
class ProgressService {
  ProgressService({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;

  /// Must match the region in functions/index.js.
  FirebaseFunctions get _client =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Creates your profile with a random name if you have none yet.
  Future<void> ensureProfile() => _call('ensureProfile');

  /// Changes your name to [adjective] [creature], from the word lists.
  Future<void> setUsername(String adjective, String creature) => _call(
    'setUsername',
    <String, dynamic>{'adjective': adjective, 'creature': creature},
  );

  /// From level 100 back to 1, with one more prestige badge.
  Future<void> prestige() => _call('prestige');

  Future<void> _call(String name, [Map<String, dynamic>? data]) async {
    try {
      await _client.httpsCallable(name).call<dynamic>(data);
    } on FirebaseFunctionsException catch (error) {
      throw ProgressException(
        error.message ?? 'Something went wrong. Please try again.',
        nameTaken: error.code == 'already-exists',
      );
    }
  }
}

/// A progress action failed; [message] is safe to show.
class ProgressException implements Exception {
  const ProgressException(this.message, {this.nameTaken = false});

  final String message;

  /// Someone else already has the requested username.
  final bool nameTaken;

  @override
  String toString() => 'ProgressException: $message';
}
