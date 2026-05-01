import "dart:async";



import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/constants/app_constants.dart";
import "../../../core/invite/invite_link_query_params.dart";
import "../../../core/invite/invitation_landing_preview.dart";
import "../../../core/invite/pending_invitation_store.dart";
import "../../../core/theme/app_assets.dart";
import "../../../core/theme/app_colors.dart";
import "../bloc/auth_bloc.dart";
import "../bloc/auth_event.dart";
import "../bloc/auth_state.dart";
import "../invite_link_account_gate.dart";
import "../repository/auth_repository.dart";
import "widgets/invitation_landing_panel.dart";

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
  String? _lastLoadedInvitePreviewId;
  var _inviteMismatchSignOutDone = false;

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
    final routerUri = GoRouterState.of(context).uri;
    final q = mergeInviteLinkQueryParams(
      path: routerUri.path,
      routerUri: routerUri,
    );
    final emailParam = q["email"]?.trim();
    if (emailParam != null &&
        emailParam.isNotEmpty &&
        _emailController.text.trim().isEmpty) {
      _emailController.text = emailParam;
    }
    unawaited(
      PendingInvitationStore.saveFromQueryForPreAuthUsersOnly(
        isAuthenticated:
            context.read<AuthBloc>().state.status == AuthStatus.authenticated,
        invitationId: q["invite"],
      ),
    );

    final effectiveMismatch = Uri(
      path: normalizeAuthPath(routerUri.path),
      queryParameters: q.isEmpty ? null : q,
    );
    if (!_inviteMismatchSignOutDone &&
        inviteSignedLinkNeedsDifferentFirebaseUser(
          authState: context.read<AuthBloc>().state,
          uri: effectiveMismatch,
        )) {
      _inviteMismatchSignOutDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AuthBloc>().add(const AuthSignOutRequested());
      });
    }

    final invite = q["invite"]?.trim();
    if (invite != null &&
        invite.isNotEmpty &&
        invite != _lastLoadedInvitePreviewId &&
        context.read<AuthRepository>().isAuthAvailable) {
      _lastLoadedInvitePreviewId = invite;
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

  @override
  void dispose() {
    _emailController.removeListener(_onEmailEdited);
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
            final routerUri = GoRouterState.of(context).uri;
            final q = mergeInviteLinkQueryParams(
              path: routerUri.path,
              routerUri: routerUri,
            );
            final hasInvite =
                q["invite"] != null && q["invite"]!.trim().isNotEmpty;

            if (hasInvite && state.status == AuthStatus.authenticated) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 20),
                      Text("Joining your care team…"),
                    ],
                  ),
                ),
              );
            }

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
                                  hasInvite
                                      ? "Sign in to accept your invitation"
                                      : "Sign in to coordinate care",
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        color: AppColors.grey500,
                                      ),
                                ),
                                if (_inviteLoading) ...[
                                  const SizedBox(height: 14),
                                  const LinearProgressIndicator(minHeight: 2),
                                ],
                                if (!firebaseReady) ...[
                                  const SizedBox(height: 16),
                                  const _FirebaseSetupBanner(),
                                ],
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
                                    "This invitation couldn't be loaded (it may "
                                    "have expired). You can still sign in or "
                                    "create an account with the email address "
                                    "your invite was sent to.",
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
                                  autofillHints: const [AutofillHints.email],
                                  decoration:
                                      const InputDecoration(labelText: "Email"),
                                  validator: (value) {
                                    if (value == null ||
                                        value.trim().isEmpty) {
                                      return "Enter your email";
                                    }
                                    if (!value.contains("@")) {
                                      return "Enter a valid email";
                                    }
                                    return null;
                                  },
                                ),
                                if (_invitePreview != null &&
                                    _emailController.text
                                            .trim()
                                            .toLowerCase() ==
                                        _invitePreview!.invitedEmail) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    "Invited as ${_invitePreview!.invitedEmail}",
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: AppColors.grey500),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: () async {
                                        await PendingInvitationStore.clear();
                                        if (!context.mounted) {
                                          return;
                                        }
                                        context.go("/sign-in");
                                      },
                                      child: const Text(
                                        "Not your email? Open sign-in without this link",
                                      ),
                                    ),
                                  ),
                                ],
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
                                          final invite = q["invite"]?.trim();
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
                                  label:
                                      const Text("Continue with Google"),
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
    final result =
        await context.read<AuthRepository>().sendPasswordResetEmail(email);
    if (!context.mounted) return;
    if (result.success) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Password reset email sent.")),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(result.message ?? "Something went wrong.")),
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
