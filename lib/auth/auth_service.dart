import 'package:firebase_auth/firebase_auth.dart';

/// Thin wrapper over [FirebaseAuth] that turns Firebase's error codes into
/// messages worth showing a user.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _run(
      () => _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );
  }

  Future<UserCredential> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final UserCredential credential = await _run(
      () => _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      ),
    );

    final String? name = displayName?.trim();
    if (name != null && name.isNotEmpty) {
      await credential.user?.updateDisplayName(name);
      // The cached User still carries the old (null) name until it is reloaded.
      await credential.user?.reload();
    }

    return credential;
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _run(() => _auth.sendPasswordResetEmail(email: email.trim()));
  }

  Future<void> signOut() => _auth.signOut();

  Future<T> _run<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (error) {
      throw AuthFailure(_messageFor(error), code: error.code);
    }
  }

  static String _messageFor(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'That email address does not look right.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        // Deliberately vague: saying which half was wrong tells an attacker
        // whether an email is registered.
        return 'Email or password is incorrect.';
      case 'email-already-in-use':
        return 'An account already exists for that email. Try logging in.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled for this Firebase '
            'project. Turn it on in Authentication -> Sign-in method.';
      case 'network-request-failed':
        return 'Cannot reach Firebase. Check your internet connection.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return error.message ?? 'Something went wrong (${error.code}).';
    }
  }
}

/// A sign-in or sign-up error that already carries a user-facing message.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code = ''});

  final String message;
  final String code;

  @override
  String toString() => 'AuthFailure($code): $message';
}
