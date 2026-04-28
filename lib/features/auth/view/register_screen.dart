import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/constants/app_constants.dart";
import "../../../core/invite/invitation_landing_preview.dart";
import "../../../core/invite/pending_invitation_store.dart";
import "../../../core/theme/app_assets.dart";
import "../../../core/theme/app_colors.dart";
import "../bloc/auth_bloc.dart";
import "../bloc/auth_event.dart";
import "../bloc/auth_state.dart";
import "../repository/auth_repository.dart";
import "widgets/invitation_landing_panel.dart";

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  var _routeParamsApplied = false;

  InvitationLandingPreview? _invitePreview;
  bool _inviteLoading = false;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_onEmailEdited);
  }

  void _onEmailEdited() {
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeParamsApplied) {
      return;
    }
    _routeParamsApplied = true;
    final q = GoRouterState.of(context).uri.queryParameters;
    final e = q["email"]?.trim();
    if (e != null && e.isNotEmpty) {
      _emailController.text = e;
    }
    unawaited(PendingInvitationStore.saveFromQueryIfPresent(q["invite"]));

    final invite = q["invite"]?.trim();
    if (invite != null &&
        invite.isNotEmpty &&
        context.read<AuthRepository>().isAuthAvailable) {
      unawaited(_loadInvitePreview(invite));
    }
  }

  Future<void> _loadInvitePreview(String invitationId) async {
    setState(() {
      _inviteLoading = true;
      _invitePreview = null;
    });
    try {
      final p = await InvitationLandingPreview.load(invitationId);
      if (!mounted) {
        return;
      }
      setState(() {
        _invitePreview = p;
        _inviteLoading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _invitePreview = null;
        _inviteLoading = false;
      });
    }
  }

  void _submitGoogle() {
    context.read<AuthBloc>().add(const AuthSignInWithGoogleRequested());
  }

  void _openSignIn() {
    final qp = GoRouterState.of(context).uri.queryParameters;
    final inv = qp["invite"]?.trim();
    final e = _emailController.text.trim();
    if (inv != null && inv.isNotEmpty) {
      if (e.isNotEmpty) {
        context.go(
          "/sign-in?email=${Uri.encodeComponent(e)}&invite=${Uri.encodeComponent(inv)}",
        );
      } else {
        context.go("/sign-in?invite=${Uri.encodeComponent(inv)}");
      }
    } else if (e.isNotEmpty) {
      context.go("/sign-in?email=${Uri.encodeComponent(e)}");
    } else {
      context.go("/sign-in");
    }
  }

  @override
  void dispose() {
    _emailController.removeListener(_onEmailEdited);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firebaseReady = context.read<AuthRepository>().isAuthAvailable;
    final inviteParam =
        GoRouterState.of(context).uri.queryParameters["invite"];
    final hasInvite =
        inviteParam != null && inviteParam.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text("Create account")),
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
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
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
                          hasInvite
                              ? "Finish creating your password to join the care team."
                              : "Create your account to get started",
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppColors.grey500,
                                  ),
                        ),
                        if (_inviteLoading) ...[
                          const SizedBox(height: 14),
                          const LinearProgressIndicator(minHeight: 2),
                        ],
                        if (!firebaseReady)
                          Padding(
                            padding: const EdgeInsets.only(top: 14),
                            child: Text(
                              "Firebase did not initialise. Run `flutterfire configure` "
                              "and rebuild.",
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        if (_invitePreview != null) ...[
                          const SizedBox(height: 16),
                          InvitationLandingPanel(
                            preview: _invitePreview!,
                          ),
                        ] else if (hasInvite &&
                            !_inviteLoading &&
                            firebaseReady) ...[
                          const SizedBox(height: 16),
                          Text(
                            "This invitation couldn't be loaded. You can still create "
                            "an account with the email your invite was sent to.",
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.grey500),
                          ),
                        ],
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [
                            AutofillHints.newUsername,
                            AutofillHints.email,
                          ],
                          decoration: const InputDecoration(labelText: "Email"),
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
                        if (_invitePreview != null &&
                            _emailController.text.trim().toLowerCase() ==
                                _invitePreview!.invitedEmail) ...[
                          const SizedBox(height: 8),
                          Text(
                            "Invited as ${_invitePreview!.invitedEmail}",
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppColors.grey500,
                                    ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () async {
                                await PendingInvitationStore.clear();
                                if (!context.mounted) return;
                                context.go("/sign-in");
                              },
                              child: const Text(
                                "Not your email?",
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: "Password",
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(
                                  () =>
                                      _obscurePassword = !_obscurePassword,
                                );
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
                              return "Enter a password";
                            }
                            if (value.length < 8) {
                              return "Use at least 8 characters";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscureConfirm,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: "Confirm password",
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(
                                  () =>
                                      _obscureConfirm = !_obscureConfirm,
                                );
                              },
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return "Confirm your password";
                            }
                            if (value != _passwordController.text) {
                              return "Passwords don't match";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed:
                              firebaseReady ? _submitEmailRegister : null,
                          child: const Text("Create account"),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: firebaseReady ? _submitGoogle : null,
                          icon: const Icon(Icons.login),
                          label: const Text("Continue with Google"),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _openSignIn,
                          child: const Text("Back to sign in"),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _submitEmailRegister() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(
          AuthRegisterWithEmailRequested(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ),
        );
  }
}
