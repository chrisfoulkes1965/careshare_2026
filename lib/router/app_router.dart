import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../features/auth/bloc/auth_bloc.dart";
import "../features/auth/bloc/auth_state.dart";
import "../features/auth/view/register_screen.dart";
import "../features/auth/view/sign_in_screen.dart";
import "../features/care_pathway/view/pathways_screen.dart";
import "../features/home/view/coming_soon_screen.dart";
import "../features/care_group/view/care_group_select_screen.dart";
import "../features/home/view/home_screen.dart";
import "../features/contacts/view/contacts_screen.dart";
import "../features/invitations/view/invitations_screen.dart";
import "../features/journal/view/journal_screen.dart";
import "../features/medications/view/medications_screen.dart";
import "../features/meetings/view/meetings_screen.dart";
import "../features/members/view/members_screen.dart";
import "../features/notes/view/notes_screen.dart";
import "../features/tasks/view/tasks_screen.dart";
import "../features/profile/profile_cubit.dart";
import "../features/profile/profile_state.dart";
import "../features/setup_wizard/view/setup_wizard_view.dart";
import "session_refresh.dart";

abstract final class AppRouteNames {
  static const signIn = "signIn";
  static const register = "register";
  static const home = "home";
  static const setup = "setup";
  static const comingSoon = "comingSoon";
  static const tasks = "tasks";
  static const pathways = "pathways";
  static const invitations = "invitations";
  static const notes = "notes";
  static const members = "members";
  static const journal = "journal";
  static const contacts = "contacts";
  static const meetings = "meetings";
  static const medications = "medications";
  static const selectCareGroup = "selectCareGroup";
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
          if (loc == "/sign-in" || loc == "/register") return null;
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
          final pr = profileState;

          if (profile.needsWizard) {
            if (!loc.startsWith("/setup")) {
              return "/setup";
            }
            return null;
          }

          if (pr.requiresCareGroupSelection) {
            if (state.uri.path == "/select-care-group") {
              return null;
            }
            return "/select-care-group";
          }

          if (state.uri.path == "/select-care-group" && state.uri.queryParameters["picker"] != "1") {
            return "/home";
          }

          if (loc.startsWith("/setup") && profile.wizardCompleted) {
            if (state.uri.queryParameters["edit"] != "1") {
              return "/home";
            }
          }

          if (loc == "/sign-in" || loc == "/register" || loc == "/loading") {
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
          path: "/register",
          name: AppRouteNames.register,
          builder: (context, state) => const RegisterScreen(),
        ),
        GoRoute(
          path: "/setup",
          name: AppRouteNames.setup,
          builder: (context, state) => const SetupWizardHost(),
        ),
        GoRoute(
          path: "/select-care-group",
          name: AppRouteNames.selectCareGroup,
          builder: (context, state) {
            final picker = state.uri.queryParameters["picker"] == "1";
            return CareGroupSelectScreen(pickerMode: picker);
          },
        ),
        GoRoute(
          path: "/home",
          name: AppRouteNames.home,
          builder: (context, state) => const HomeScreen(),
        ),
        GoRoute(
          path: "/coming-soon",
          name: AppRouteNames.comingSoon,
          builder: (context, state) {
            final title = state.extra is String ? state.extra! as String : "Feature";
            return ComingSoonScreen(title: title);
          },
        ),
        GoRoute(
          path: "/tasks",
          name: AppRouteNames.tasks,
          builder: (context, state) => const TasksScreen(),
        ),
        GoRoute(
          path: "/pathways",
          name: AppRouteNames.pathways,
          builder: (context, state) => const PathwaysScreen(),
        ),
        GoRoute(
          path: "/invitations",
          name: AppRouteNames.invitations,
          builder: (context, state) => const InvitationsScreen(),
        ),
        GoRoute(
          path: "/notes",
          name: AppRouteNames.notes,
          builder: (context, state) => const NotesScreen(),
        ),
        GoRoute(
          path: "/journal",
          name: AppRouteNames.journal,
          builder: (context, state) => const JournalScreen(),
        ),
        GoRoute(
          path: "/contacts",
          name: AppRouteNames.contacts,
          builder: (context, state) => const ContactsScreen(),
        ),
        GoRoute(
          path: "/meetings",
          name: AppRouteNames.meetings,
          builder: (context, state) => const MeetingsScreen(),
        ),
        GoRoute(
          path: "/medications",
          name: AppRouteNames.medications,
          builder: (context, state) => const MedicationsScreen(),
        ),
        GoRoute(
          path: "/members",
          name: AppRouteNames.members,
          builder: (context, state) => const MembersScreen(),
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
