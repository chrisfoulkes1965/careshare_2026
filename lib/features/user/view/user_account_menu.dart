import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_event.dart";
import "../../profile/profile_state.dart";
import "widgets/care_user_avatar.dart";

void showUserAccountMenu(
  BuildContext context, {
  required User user,
  required ProfileState profileState,
}) {
  final p = profileState is ProfileReady ? profileState.profile : null;
  final title = p != null && p.displayName.isNotEmpty
      ? p.displayName
      : (user.displayName?.trim().isNotEmpty == true
          ? user.displayName!
          : (user.email?.split("@").first ?? "You"));
  final sub = p != null && p.email.isNotEmpty ? p.email : (user.email ?? "");

  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: CareUserAvatar(
                    radius: 28,
                    user: user,
                    profile: p,
                  ),
                  title: Text(title),
                  subtitle: sub.isNotEmpty
                      ? Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                ),
                if (p != null) const Divider(),
                if (p != null) ...[
                  ListTile(
                    leading: const Icon(Icons.face_outlined),
                    title: const Text("Profile & avatar"),
                    subtitle:
                        const Text("Display name, photo, or a preset image"),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.push("/user-settings/profile");
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.groups_2_outlined),
                    title: const Text("Care groups & roles"),
                    subtitle: const Text(
                        "Switch your active care team, see your roles"),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      context.push("/user-settings/care-groups");
                    },
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text("Email & security"),
                  subtitle: p != null
                      ? const Text("Password, sign-in methods, and your email")
                      : const Text(
                          "Sign-in, password, and your email on this account"),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.push("/user-settings/security");
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.logout,
                      color: Theme.of(ctx).colorScheme.error),
                  title: Text(
                    "Log out",
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.read<AuthBloc>().add(const AuthSignOutRequested());
                  },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
