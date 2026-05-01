import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../repository/user_repository.dart";

/// Receives `?token=…` from the verification email and asks the cloud function
/// to mark the matching alternate email as verified. If the user is signed
/// out, prompts them to sign in (the route is allowlisted in the unauth
/// redirect branch so the token is preserved).
class VerifyAlternateEmailScreen extends StatefulWidget {
  const VerifyAlternateEmailScreen({super.key, required this.token});

  final String token;

  @override
  State<VerifyAlternateEmailScreen> createState() =>
      _VerifyAlternateEmailScreenState();
}

class _VerifyAlternateEmailScreenState
    extends State<VerifyAlternateEmailScreen> {
  bool _running = false;
  bool _done = false;
  String? _verifiedAddress;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running || _done) {
      return;
    }
    final auth = context.read<AuthBloc>().state;
    if (auth.status != AuthStatus.authenticated) {
      return;
    }
    if (widget.token.isEmpty) {
      setState(() {
        _error = "Verification link is missing its token.";
        _done = true;
      });
      return;
    }
    setState(() => _running = true);
    try {
      final repo = context.read<UserRepository>();
      final addr = await repo.confirmAlternateEmailVerification(
        token: widget.token,
      );
      if (!mounted) return;
      try {
        await context.read<ProfileCubit>().refresh();
      } catch (_) {/* ignore */}
      setState(() {
        _verifiedAddress = addr.isEmpty ? null : addr;
        _done = true;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _done = true;
        _running = false;
      });
    }
  }

  void _continue() {
    if (!mounted) return;
    context.go("/user-settings/profile");
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, s) {
        if (s.status == AuthStatus.authenticated && !_running && !_done) {
          _run();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text("Verify email")),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: BlocBuilder<AuthBloc, AuthState>(
              builder: (context, auth) {
                if (auth.status != AuthStatus.authenticated) {
                  return _signInPrompt(context);
                }
                return _verificationBody(context);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _signInPrompt(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.lock_outline, size: 48),
        const SizedBox(height: 16),
        Text(
          "Sign in to verify this email address",
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          "Use the same CareShare account that asked for the verification link.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => context.go("/sign-in"),
          child: const Text("Sign in"),
        ),
      ],
    );
  }

  Widget _verificationBody(BuildContext context) {
    if (!_done) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text("Verifying your email address…"),
        ],
      );
    }
    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(
            "We couldn't verify the link",
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _continue,
            child: const Text("Back to profile"),
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.verified, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        Text(
          _verifiedAddress != null
              ? "${_verifiedAddress!} is verified"
              : "Email verified",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _continue,
          child: const Text("Continue"),
        ),
      ],
    );
  }
}
