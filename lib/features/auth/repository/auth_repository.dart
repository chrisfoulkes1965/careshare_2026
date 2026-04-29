import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:google_sign_in/google_sign_in.dart";

/// Typed outcome for password reset so views never catch [FirebaseAuthException].
final class PasswordResetSendResult {
  const PasswordResetSendResult.ok()
      : success = true,
        message = null;

  PasswordResetSendResult.error(String msg)
      : success = false,
        message = msg;

  final bool success;
  /// User-facing text when [success] is false.
  final String? message;
}

/// All Firebase Auth access for the app lives here (no Auth calls from UI).
class AuthRepository {
  AuthRepository({required bool firebaseReady})
      : _firebaseReady = firebaseReady;

  static Future<void>? _googleSignInInit;

  final bool _firebaseReady;

  bool get isAuthAvailable => _firebaseReady;

  Stream<User?> authStateChanges() {
    if (!_firebaseReady) {
      return const Stream.empty();
    }
    return FirebaseAuth.instance.authStateChanges();
  }

  User? get currentUser {
    if (!_firebaseReady) return null;
    return FirebaseAuth.instance.currentUser;
  }

  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    _ensureFirebase();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    _ensureFirebase();
    await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signInWithGoogle() async {
    _ensureFirebase();
    if (kIsWeb) {
      // Web: Firebase JS SDK opens the Google OAuth popup (no `google_sign_in` plugin).
      final provider = GoogleAuthProvider();
      provider.addScope("email");
      provider.addScope("profile");
      try {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (_isWebGoogleSignInCancelled(e)) {
          throw const GoogleSignInCancelledException();
        }
        rethrow;
      }
      return;
    }

    // google_sign_in 7+: single instance; [initialize] must complete before [authenticate].
    _googleSignInInit ??= GoogleSignIn.instance.initialize();
    await _googleSignInInit;

    final GoogleSignInAccount googleUser;
    try {
      googleUser = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleSignInCancelledException();
      }
      rethrow;
    }

    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!_firebaseReady) return;
    if (!kIsWeb) {
      _googleSignInInit ??= GoogleSignIn.instance.initialize();
      await _googleSignInInit;
    }
    await Future.wait([
      FirebaseAuth.instance.signOut(),
      if (!kIsWeb) GoogleSignIn.instance.signOut(),
    ]);
  }

  /// Sends a password reset email. [FirebaseAuthException] is handled here —
  /// callers inspect [PasswordResetSendResult.ok] only.
  Future<PasswordResetSendResult> sendPasswordResetEmail(String email) async {
    _ensureFirebase();
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      return const PasswordResetSendResult.ok();
    } on FirebaseAuthException catch (e) {
      return PasswordResetSendResult.error(_passwordResetUserMessage(e));
    } catch (e) {
      return PasswordResetSendResult.error(e.toString());
    }
  }

  /// Updates the signed-in user’s display name in Firebase Auth (and you should sync Firestore in [UserRepository]).
  Future<void> updateDisplayName(String displayName) async {
    _ensureFirebase();
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return;
    }
    final t = displayName.trim();
    await u.updateDisplayName(t.isEmpty ? null : t);
  }

  /// Sets or clears the profile photo on the Auth user record.
  Future<void> updatePhotoUrl(String? url) async {
    _ensureFirebase();
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      return;
    }
    final t = url?.trim();
    await u.updatePhotoURL(t == null || t.isEmpty ? null : t);
  }

  void _ensureFirebase() {
    if (!_firebaseReady) {
      throw StateError(
          "Firebase is not initialised. Run flutterfire configure.");
    }
  }
}

String _passwordResetUserMessage(FirebaseAuthException e) {
  final code = e.code;
  switch (code) {
    case "invalid-email":
      return "Enter a valid email address.";
    case "missing-email":
      return "Enter your email.";
    case "user-not-found":
      return "No account found for this email.";
    default:
      return e.message ?? "Could not send password reset email.";
  }
}

/// User closed the OAuth popup or dismissed the sign-in.
bool _isWebGoogleSignInCancelled(FirebaseAuthException e) {
  switch (e.code) {
    case "popup-closed-by-user":
    case "cancelled-popup-request":
      return true;
    default:
      return false;
  }
}

final class GoogleSignInCancelledException implements Exception {
  const GoogleSignInCancelledException();
}
