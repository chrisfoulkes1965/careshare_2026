import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../features/auth/bloc/auth_bloc.dart";
import "../features/auth/bloc/auth_state.dart";
import "../features/auth/view/sign_in_screen.dart";
import "../features/home/view/home_screen.dart";
import "../features/profile/profile_cubit.dart";
import "../features/profile/profile_state.dart";
import "../features/setup_wizard/view/setup_wizard_view.dart";
import "session_refresh.dart";

abstract final class AppRouteNames {
  static const signIn = "signIn";
  static const home = "home";
  static const setup = "setup";
}

abstract final class AppRouter {
  static GoRouter create({
    required AuthBloc authBloc,
    required ProfileCubit profileCubit,
    required SessionRefresh sessionRefresh,
  }) {
    return GoRouter(
      initialLocation: "/loading",
      refreshListenable: sessionRefresh,
      redirect: (BuildContext context, GoRouterState state) {
        final loc = state.matchedLocation;
        final authState = authBloc.state;
        final profileState = profileCubit.state;

        if (authState.status == AuthStatus.unknown) {
          return loc == "/loading" ? null : "/loading";
        }

        if (authState.status == AuthStatus.unauthenticated) {
          if (loc == "/sign-in" || loc == "/loading") return null;
          return "/sign-in";
        }

        if (profileState is ProfileError) {
          if (loc == "/home") return null;
          return "/home";
        }

        if (profileState is ProfileLoading || profileState is ProfileAnonymous) {
          return loc == "/loading" ? null : "/loading";
        }

        if (profileState is ProfileReady) {
          final profile = profileState.profile;

          if (profile.needsWizard) {
            if (!loc.startsWith("/setup")) {
              return "/setup";
            }
            return null;
          }

          if (loc.startsWith("/setup") && profile.wizardCompleted) {
            return "/home";
          }

          if (loc == "/sign-in" || loc == "/loading") {
            return "/home";
          }
        }

        return null;
      },
      routes: [
        GoRoute(
          path: "/loading",
          builder: (context, state) => const _LoadingScreen(),
        ),
        GoRoute(
          path: "/sign-in",
          name: AppRouteNames.signIn,
          builder: (context, state) => const SignInScreen(),
        ),
        GoRoute(
          path: "/setup",
          name: AppRouteNames.setup,
          builder: (context, state) => const SetupWizardHost(),
        ),
        GoRoute(
          path: "/home",
          name: AppRouteNames.home,
          builder: (context, state) => const HomeScreen(),
        ),
      ],
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
