import "dart:async";

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/constants/app_constants.dart";
import "../../../core/invite/pending_invitation_store.dart";
import "../../../core/theme/app_assets.dart";
import "../../../core/theme/app_colors.dart";
import "../bloc/auth_bloc.dart";
import "../bloc/auth_event.dart";
import "../bloc/auth_state.dart";
import "../repository/auth_repository.dart";

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  var _prefilledRouteEmail = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilledRouteEmail) {
      return;
    }
    final q = GoRouterState.of(context).uri.queryParameters;
    final e = q["email"]?.trim();
    if (e != null && e.isNotEmpty) {
      _emailController.text = e;
    }
    unawaited(PendingInvitationStore.saveFromQueryIfPresent(q["invite"]));
    _prefilledRouteEmail = true;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: BlocConsumer<AuthBloc, AuthState>(
          listenWhen: (previous, current) =>
              previous.errorMessage != current.errorMessage,
          listener: (context, state) {
            final message = state.errorMessage;
            if (message != null && message.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            }
          },
          builder: (context, state) {
            final firebaseReady =
                context.read<AuthRepository>().isAuthAvailable;

            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Image.asset(
                                  AppAssets.logo100,
                                  height: 100,
                                  filterQuality: FilterQuality.medium,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  AppConstants.appName,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: AppColors.tealPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "Sign in to coordinate care",
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: AppColors.grey500,
                                      ),
                                ),
                                if (!firebaseReady) ...[
                                  const SizedBox(height: 16),
                                  const _FirebaseSetupBanner(),
                                ],
                                const SizedBox(height: 32),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  decoration:
                                      const InputDecoration(labelText: "Email"),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return "Enter your email";
                                    }
                                    if (!value.contains("@")) {
                                      return "Enter a valid email";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  autofillHints: const [AutofillHints.password],
                                  decoration: InputDecoration(
                                    labelText: "Password",
                                    suffixIcon: IconButton(
                                      onPressed: () {
                                        setState(() => _obscurePassword =
                                            !_obscurePassword);
                                      },
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                      ),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return "Enter your password";
                                    }
                                    if (value.length < 8) {
                                      return "Use at least 8 characters";
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: firebaseReady
                                        ? () => _sendPasswordReset(context)
                                        : null,
                                    child: const Text("Forgot password?"),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                FilledButton(
                                  onPressed: firebaseReady
                                      ? _submitEmailPassword
                                      : null,
                                  child: const Text("Sign in"),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: firebaseReady
                                      ? () {
                                          final qp = GoRouterState.of(context)
                                              .uri
                                              .queryParameters;
                                          final invite =
                                              qp["invite"]?.trim();
                                          final e = _emailController.text
                                              .trim();
                                          if (invite != null &&
                                              invite.isNotEmpty) {
                                            if (e.isNotEmpty) {
                                              context.push(
                                                "/register?email=${Uri.encodeComponent(e)}&invite=${Uri.encodeComponent(invite)}",
                                              );
                                            } else {
                                              context.push(
                                                "/register?invite=${Uri.encodeComponent(invite)}",
                                              );
                                            }
                                          } else if (e.isNotEmpty) {
                                            context.push(
                                              "/register?email=${Uri.encodeComponent(e)}",
                                            );
                                          } else {
                                            context.push("/register");
                                          }
                                        }
                                      : null,
                                  child: const Text("Create account"),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed:
                                      firebaseReady ? _submitGoogle : null,
                                  icon: const Icon(Icons.login),
                                  label: const Text("Continue with Google"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _submitEmailPassword() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(
          AuthSignInWithEmailRequested(
            email: _emailController.text,
            password: _passwordController.text,
          ),
        );
  }

  void _submitGoogle() {
    context.read<AuthBloc>().add(const AuthSignInWithGoogleRequested());
  }

  Future<void> _sendPasswordReset(BuildContext context) async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains("@")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a valid email first.")),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthRepository>().sendPasswordResetEmail(email);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Password reset email sent.")),
      );
    } on FirebaseAuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message ?? e.code)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }
}

class _FirebaseSetupBanner extends StatelessWidget {
  const _FirebaseSetupBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.amberLight,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          "Firebase did not initialise. Run `flutterfire configure` and rebuild.",
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: AppColors.grey900),
        ),
      ),
    );
  }
}
