import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/constants/app_constants.dart";

import "../../user/models/user_profile.dart";
import "../../../core/theme/app_assets.dart";
import "../../../core/theme/app_colors.dart";
import "../../../core/theme/care_group_header_theme.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "home_landing_view.dart";
import "widgets/care_action_card.dart";

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cubit = context.read<ProfileCubit>();
    final acceptedId = cubit.consumeJustAcceptedCareGroupId();
    final failureMsg = cubit.consumeJustFailedInviteRedeemError();
    if (acceptedId != null) {
      final s = cubit.state;
      String label = "your care team";
      if (s is ProfileReady) {
        for (final o in s.careGroupOptions) {
          if (o.careGroupId == acceptedId) {
            label = o.displayName;
            break;
          }
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Welcome to $label! You can change your name and avatar in Settings.",
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      });
      return;
    }
    if (failureMsg != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "We couldn’t finish accepting your invitation: $failureMsg. "
              "Ask the inviter to resend, or try again from Settings.",
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, profileState) {
        return BlocBuilder<AuthBloc, AuthState>(
          buildWhen: (p, c) => p.user?.uid != c.user?.uid,
          builder: (context, authState) {
            final user = authState.user;
            final email = user?.email ?? "Signed in";

            if (profileState is ProfileLoading) {
              return Scaffold(
                backgroundColor:
                    CareGroupHomePageStyle.fallback.scaffoldBackground,
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            if (profileState is ProfileError) {
              return Scaffold(
                appBar: AppBar(
                  centerTitle: true,
                  title: const Text(AppConstants.appName),
                ),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          profileState.message,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () =>
                              context.read<ProfileCubit>().refresh(),
                          child: const Text("Retry"),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (profileState is ProfileReady) {
              final pr = profileState;
              // Only nag about a "skipped wizard" when the user truly skipped
              // it AND isn't already in a care team (i.e. didn't arrive via
              // an invite). Invitees have `wizardSkipped` set as a routing
              // flag but never saw the wizard.
              final banner = pr.profile.wizardSkipped &&
                  !pr.profile.wizardCompleted &&
                  pr.careGroupOptions.isEmpty;
              final au = authState.user;
              final authSnapshot = au == null
                  ? null
                  : UserProfile.fromAuthSession(
                      uid: au.uid,
                      email: au.email ?? "",
                      displayName: au.displayName,
                      photoUrl: au.photoURL,
                    );
              return Scaffold(
                backgroundColor: resolveCareGroupHomePageStyle(
                  activeThemeArgb: pr.activeCareGroupThemeArgb,
                ).scaffoldBackground,
                body: HomeLandingView(
                  pr: pr,
                  authSnapshot: authSnapshot,
                  email: email,
                  showWizardBanner: banner,
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                centerTitle: true,
                leading: Center(
                  child: Image.asset(
                    AppAssets.logoOnPrimary,
                    height: 28,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
                title: const Text(AppConstants.appName),
                actions: [
                  IconButton(
                    tooltip: "Refresh profile",
                    onPressed: () => context.read<ProfileCubit>().refresh(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      "Hello",
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppColors.grey500,
                          ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "Care",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    CareActionCard(
                      icon: Icons.task_alt_outlined,
                      title: "Tasks",
                      subtitle: "To-dos and shared work for your care group",
                      onTap: () => context.push("/tasks"),
                    ),
                    CareActionCard(
                      icon: Icons.forum_outlined,
                      title: "Group chat",
                      subtitle: "Channel messages for this care team",
                      onTap: () => context.push("/chat"),
                    ),
                    CareActionCard(
                      icon: Icons.payments_outlined,
                      title: "Expenses",
                      subtitle: "Shared spending for this care group",
                      onTap: () => context.push("/expenses"),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
