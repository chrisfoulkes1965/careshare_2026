import "dart:async";

import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../../../core/constants/app_constants.dart";
import "../../../core/invite/invite_link_query_params.dart";
import "../../../core/invite/invitation_landing_preview.dart";
import "../../../core/invite/pending_invitation_store.dart";
import "../../../core/theme/app_assets.dart";
import "../../../core/theme/app_colors.dart";
import "widgets/invitation_landing_panel.dart";

/// Shown when someone with an existing CareShare account opens an invite link and
/// tries “Create account” — they must sign in first, then the app can add them
/// to the new care group.
class InviteExistingUserScreen extends StatefulWidget {
  const InviteExistingUserScreen({super.key});

  @override
  State<InviteExistingUserScreen> createState() =>
      _InviteExistingUserScreenState();
}

class _InviteExistingUserScreenState extends State<InviteExistingUserScreen> {
  String? _lastLoadedInvitePreviewId;
  InvitationLandingPreview? _invitePreview;
  bool _inviteLoading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routerUri = GoRouterState.of(context).uri;
    final q = mergeInviteLinkQueryParams(
      path: routerUri.path,
      routerUri: routerUri,
    );
    unawaited(PendingInvitationStore.saveFromQueryIfPresent(q["invite"]));

    final invite = q["invite"]?.trim();
    if (invite != null &&
        invite.isNotEmpty &&
        invite != _lastLoadedInvitePreviewId) {
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

  void _goSignIn() {
    final routerUri = GoRouterState.of(context).uri;
    final q = mergeInviteLinkQueryParams(
      path: routerUri.path,
      routerUri: routerUri,
    );
    final invite = q["invite"]?.trim();
    final email = q["email"]?.trim() ?? "";
    final params = <String, String>{};
    if (invite != null && invite.isNotEmpty) {
      params["invite"] = invite;
    }
    if (email.isNotEmpty) {
      params["email"] = email;
    }
    context.go(
      Uri(
        path: "/sign-in",
        queryParameters: params.isEmpty ? null : params,
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final routerUri = GoRouterState.of(context).uri;
    final q = mergeInviteLinkQueryParams(
      path: routerUri.path,
      routerUri: routerUri,
    );
    final email = q["email"]?.trim() ?? "";

    return Scaffold(
      appBar: AppBar(
        title: const Text("You already have an account"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
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
                  const SizedBox(height: 12),
                  Text(
                    email.isNotEmpty
                        ? "$email already has a ${AppConstants.appName} "
                            "account. Sign in once and we’ll add you to this care team."
                        : "This email already has a CareShare account. "
                            "Sign in to join this group.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.grey900,
                          height: 1.35,
                        ),
                  ),
                  if (_inviteLoading) ...[
                    const SizedBox(height: 14),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  if (_invitePreview != null) ...[
                    const SizedBox(height: 18),
                    InvitationLandingPanel(
                      preview: _invitePreview!,
                      showAccountCreationHints: false,
                    ),
                  ] else if (q["invite"] != null &&
                      q["invite"]!.trim().isNotEmpty &&
                      !_inviteLoading) ...[
                    const SizedBox(height: 18),
                    Text(
                      "We couldn’t reload the invitation preview. You can "
                      "still sign in — your invite will apply after that.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.grey500,
                          ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _goSignIn,
                    child: const Text("Sign in to join this group"),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => context.go(
                      Uri(
                        path: "/register",
                        queryParameters: q.isEmpty ? null : q,
                      ).toString(),
                    ),
                    child: const Text("Back to invitation screen"),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
