import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../auth/repository/auth_repository.dart";

class UserSettingsSecurityScreen extends StatefulWidget {
  const UserSettingsSecurityScreen({super.key});

  @override
  State<UserSettingsSecurityScreen> createState() =>
      _UserSettingsSecurityScreenState();
}

class _UserSettingsSecurityScreenState
    extends State<UserSettingsSecurityScreen> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (a, b) => a.user?.uid != b.user?.uid,
      builder: (context, auth) {
        final u = auth.user;
        if (u == null) {
          return const Scaffold(
            body: Center(child: Text("Not signed in.")),
          );
        }
        final email = u.email;
        final hasPassword = u.providerData.any(
          (p) => p.providerId == "password",
        );
        final hasGoogle = u.providerData.any(
          (p) => p.providerId == "google.com",
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text("Email & security"),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go("/home");
                }
              },
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Email on this account"),
                subtitle: Text(
                  email ?? "—",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w500),
                ),
                trailing: u.emailVerified
                    ? const Icon(Icons.verified, color: Colors.blue)
                    : null,
              ),
              if (u.email != null && !u.emailVerified) ...[
                const SizedBox(height: 4),
                Text(
                  "Check your inbox to verify this email, if you were asked to.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              Text("Sign-in methods",
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              if (hasPassword)
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.email_outlined),
                  title: Text("Email and password"),
                  subtitle: Text(
                      "You can reset your password with the button below."),
                ),
              if (hasGoogle) ...[
                if (hasPassword) const SizedBox(height: 4),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.g_mobiledata, size: 32),
                  title: Text("Google"),
                  subtitle: Text(
                    "Name and profile image can also be managed in your Google account.",
                  ),
                ),
              ],
              if (!hasPassword && !hasGoogle)
                const Text(
                    "Sign-in is linked in another way. Use your provider’s help for account changes.")
              else
                const SizedBox.shrink(),
              if (kIsWeb)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    "On the web, sign-in and password behaviour follows your browser and your provider’s pages.",
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 24),
              if (hasPassword && email != null && email.isNotEmpty)
                FilledButton.tonal(
                  onPressed: _sending
                      ? null
                      : () async {
                          setState(() => _sending = true);
                          final messenger = ScaffoldMessenger.of(context);
                          final result = await context
                              .read<AuthRepository>()
                              .sendPasswordResetEmail(email);
                          if (!mounted) {
                            return;
                          }
                          setState(() => _sending = false);
                          if (result.success) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                    "Password reset email sent. Check your inbox."),
                              ),
                            );
                          } else {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  result.message ?? "Could not send email.",
                                ),
                              ),
                            );
                          }
                        },
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Send password reset email"),
                )
              else if (hasPassword == false)
                Text(
                  "This account is not using an email+password in CareShare, so you cannot set a new password from here. "
                  "If you also use a password, sign in with the method you used to create the account first.",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        );
      },
    );
  }
}
