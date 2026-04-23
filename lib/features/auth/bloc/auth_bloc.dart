import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../../core/medication_reminders/medication_notification_service.dart";
import "../repository/auth_repository.dart";
import "auth_event.dart";
import "auth_state.dart";

final class AuthBloc extends Bloc<AuthEvent, AuthState> {
  AuthBloc({required AuthRepository repository})
      : _repository = repository,
        super(const AuthState.unknown()) {
    on<AuthSubscriptionRequested>(_onSubscriptionRequested);
    on<AuthUserChanged>(_onUserChanged);
    on<AuthSignInWithEmailRequested>(_onSignInWithEmail);
    on<AuthRegisterWithEmailRequested>(_onRegisterWithEmail);
    on<AuthSignInWithGoogleRequested>(_onSignInWithGoogle);
    on<AuthSignOutRequested>(_onSignOut);

    add(const AuthSubscriptionRequested());
  }

  final AuthRepository _repository;
  StreamSubscription<User?>? _authSub;

  Future<void> _onSubscriptionRequested(
    AuthSubscriptionRequested event,
    Emitter<AuthState> emit,
  ) async {
    await _authSub?.cancel();
    _authSub = null;

    if (!_repository.isAuthAvailable) {
      emit(const AuthState.unauthenticated(
        errorMessage: "Firebase is not configured yet.",
      ));
      return;
    }

    // Resolve the initial auth state immediately so router redirects do not
    // wait forever for the first stream emission on some devices.
    final currentUser = _repository.currentUser;
    if (currentUser == null) {
      emit(const AuthState.unauthenticated());
    } else {
      emit(AuthState.authenticated(currentUser));
    }

    _authSub = _repository.authStateChanges().listen(
      (user) => add(AuthUserChanged(user)),
      onError: (Object error, StackTrace stackTrace) {
        add(const AuthUserChanged(null));
      },
    );
  }

  void _onUserChanged(AuthUserChanged event, Emitter<AuthState> emit) {
    final user = event.user;
    if (user == null) {
      emit(const AuthState.unauthenticated());
    } else {
      emit(AuthState.authenticated(user));
    }
  }

  Future<void> _onSignInWithEmail(
    AuthSignInWithEmailRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _repository.signInWithEmailAndPassword(
        email: event.email,
        password: event.password,
      );
    } on FirebaseAuthException catch (e) {
      emit(AuthState.unauthenticated(errorMessage: e.message ?? e.code));
    } catch (e) {
      emit(AuthState.unauthenticated(errorMessage: e.toString()));
    }
  }

  Future<void> _onRegisterWithEmail(
    AuthRegisterWithEmailRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _repository.createUserWithEmailAndPassword(
        email: event.email,
        password: event.password,
      );
    } on FirebaseAuthException catch (e) {
      emit(AuthState.unauthenticated(errorMessage: e.message ?? e.code));
    } catch (e) {
      emit(AuthState.unauthenticated(errorMessage: e.toString()));
    }
  }

  Future<void> _onSignInWithGoogle(
    AuthSignInWithGoogleRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      await _repository.signInWithGoogle();
    } on GoogleSignInCancelledException {
      // User closed the picker; keep current auth state.
    } on FirebaseAuthException catch (e) {
      emit(AuthState.unauthenticated(errorMessage: e.message ?? e.code));
    } catch (e) {
      emit(AuthState.unauthenticated(errorMessage: e.toString()));
    }
  }

  Future<void> _onSignOut(AuthSignOutRequested event, Emitter<AuthState> emit) async {
    await MedicationNotificationService.instance.cancelAll();
    await _repository.signOut();
  }

  @override
  Future<void> close() async {
    await _authSub?.cancel();
    return super.close();
  }
}
