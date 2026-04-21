import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/constants/app_constants.dart";
import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_event.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../../setup_wizard/repository/setup_repository.dart";

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            tooltip: "Sign out",
            onPressed: () {
              context.read<AuthBloc>().add(const AuthSignOutRequested());
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: BlocBuilder<AuthBloc, AuthState>(
        buildWhen: (p, c) => p.user?.uid != c.user?.uid,
        builder: (context, authState) {
          final user = authState.user;
          final email = user?.email ?? "Signed in";

          return BlocBuilder<ProfileCubit, ProfileState>(
            builder: (context, profileState) {
              final banner = profileState is ProfileReady &&
                  profileState.profile.wizardSkipped &&
                  !profileState.profile.wizardCompleted;

              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (banner) ...[
                    Material(
                      color: AppColors.tealLight,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Finish setting up CareShare",
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "You skipped the setup wizard. Continue when you are ready so your household, pathways, and invites are configured.",
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () async {
                                final uid = context.read<AuthBloc>().state.user?.uid;
                                if (uid == null) return;
                                final repo = context.read<SetupRepository>();
                                if (repo.isAvailable) {
                                  await repo.resumeWizard(uid);
                                  await context.read<ProfileCubit>().refresh();
                                }
                                if (!context.mounted) return;
                                context.go("/setup");
                              },
                              child: const Text("Continue setup"),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    "You are signed in",
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  if (profileState is ProfileReady) ...[
                    Text(
                      "Household: ${profileState.profile.activeHouseholdId ?? "—"}",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}
