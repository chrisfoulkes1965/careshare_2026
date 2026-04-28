import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/constants/app_constants.dart";
import "../../../core/invite/pending_invitation_store.dart";
import "../../../core/theme/app_assets.dart";
import "../../../core/theme/app_colors.dart";
import "../bloc/auth_bloc.dart";
import "../bloc/auth_event.dart";

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
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Create account")),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
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
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: AppColors.tealPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Create your account to get started",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.grey500,
                          ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.newUsername, AutofillHints.email],
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: "Password",
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() => _obscurePassword = !_obscurePassword);
                          },
                          icon: Icon(
                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
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
                            setState(() => _obscureConfirm = !_obscureConfirm);
                          },
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility : Icons.visibility_off,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Confirm your password";
                        }
                        if (value != _passwordController.text) {
                          return "Passwords do not match";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _submit,
                      child: const Text("Create account"),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text("Back to sign in"),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    context.read<AuthBloc>().add(
          AuthRegisterWithEmailRequested(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          ),
        );
  }
}
