import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/foundation.dart";
import "package:google_sign_in/google_sign_in.dart";

/// All Firebase Auth access for the app lives here (no Auth calls from UI).
class AuthRepository {
  AuthRepository({required bool firebaseReady}) : _firebaseReady = firebaseReady;

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

  Future<void> signInWithGoogle() async {
    _ensureFirebase();
    if (kIsWeb) {
      throw UnsupportedError(
        "Google sign-in on web is not wired in this scaffold yet. Use email/password, "
        "or add a web OAuth flow (redirect/popup) via Firebase Auth.",
      );
    }

    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw const GoogleSignInCancelledException();
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await FirebaseAuth.instance.signInWithCredential(credential);
  }

  Future<void> signOut() async {
    if (!_firebaseReady) return;
    await Future.wait([
      FirebaseAuth.instance.signOut(),
      if (!kIsWeb) GoogleSignIn().signOut(),
    ]);
  }

  Future<void> sendPasswordResetEmail(String email) async {
    _ensureFirebase();
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  void _ensureFirebase() {
    if (!_firebaseReady) {
      throw StateError("Firebase is not initialised. Run flutterfire configure.");
    }
  }
}

final class GoogleSignInCancelledException implements Exception {
  const GoogleSignInCancelledException();
}
