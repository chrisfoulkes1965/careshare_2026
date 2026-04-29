import "package:equatable/equatable.dart";
import "package:firebase_auth/firebase_auth.dart";

enum AuthStatus { unknown, unauthenticated, authenticated }

final class AuthState extends Equatable {
  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
    this.registrationEmailAlreadyInUse = false,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  /// [registrationEmailAlreadyInUse] — email/password sign-up hit `email-already-in-use`;
  /// invitation flows navigate to [/invite-existing-user] instead of only showing an error.
  const AuthState.unauthenticated({
    String? errorMessage,
    bool registrationEmailAlreadyInUse = false,
  }) : this(
          status: AuthStatus.unauthenticated,
          user: null,
          errorMessage: errorMessage,
          registrationEmailAlreadyInUse: registrationEmailAlreadyInUse,
        );

  const AuthState.authenticated(User user)
      : this(
          status: AuthStatus.authenticated,
          user: user,
          registrationEmailAlreadyInUse: false,
        );

  final AuthStatus status;
  final User? user;
  final String? errorMessage;
  final bool registrationEmailAlreadyInUse;

  @override
  List<Object?> get props => [
        status,
        user?.uid,
        errorMessage,
        registrationEmailAlreadyInUse,
      ];
}
