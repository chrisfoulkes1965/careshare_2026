import "package:flutter/material.dart";
import "package:go_router/go_router.dart";

import "../core/invite/invite_link_query_params.dart";
import "../features/auth/bloc/auth_bloc.dart";
import "../features/auth/bloc/auth_state.dart";
import "../features/auth/invite_link_account_gate.dart";
import "../features/auth/view/invite_existing_user_screen.dart";
import "../features/auth/view/register_screen.dart";
import "../features/auth/view/sign_in_screen.dart";
import "../features/care_pathway/view/pathways_screen.dart";
import "../features/home/view/coming_soon_screen.dart";
import "../features/care_group/view/care_group_select_screen.dart";
import "../features/home/view/home_screen.dart";
import "../features/calendar/view/calendar_screen.dart";
import "../features/chat/view/channel_chat_screen.dart";
import "../features/chat/view/chat_channels_screen.dart";
import "../features/contacts/view/contacts_screen.dart";
import "../features/documents/view/document_library_screen.dart";
import "../features/gallery/view/photo_gallery_screen.dart";
import "../features/expenses/view/expenses_screen.dart";
import "../features/invitations/view/invitations_screen.dart";
import "../features/journal/view/journal_screen.dart";
import "../features/medications/view/medication_dose_confirm_screen.dart";
import "../features/medications/view/medications_screen.dart";
import "../features/meetings/view/meetings_screen.dart";
import "../features/members/view/members_screen.dart";
import "../features/notes/view/notes_screen.dart";
import "../features/tasks/view/tasks_screen.dart";
import "../features/user/view/care_group_settings_screen.dart";
import "../features/user/view/user_settings_care_groups_screen.dart";
import "../features/user/view/user_settings_profile_screen.dart";
import "../features/user/view/user_settings_alerts_screen.dart";
import "../features/user/view/user_settings_homepage_screen.dart";
import "../features/user/view/user_settings_security_screen.dart";
import "../features/user/view/verify_alternate_email_screen.dart";
import "../features/user/view/create_care_group_screen.dart";
import "../features/profile/cubit/profile_cubit.dart";
import "../features/profile/cubit/profile_state.dart";
import "../features/setup_wizard/view/setup_wizard_view.dart";
import "session_refresh.dart";

abstract final class AppRouteNames {
  static const signIn = "signIn";
  static const register = "register";
  static const inviteExistingUser = "inviteExistingUser";
  static const home = "home";
  static const setup = "setup";
  static const comingSoon = "comingSoon";
  static const tasks = "tasks";
  static const calendar = "calendar";
  static const chat = "chat";
  static const chatChannel = "chatChannel";
  static const expenses = "expenses";
  static const careGroupSettings = "careGroupSettings";
  static const pathways = "pathways";
  static const invitations = "invitations";
  static const notes = "notes";
  static const members = "members";
  static const journal = "journal";
  static const contacts = "contacts";
  static const meetings = "meetings";
  static const documentLibrary = "documentLibrary";
  static const medications = "medications";
  static const photoGallery = "photoGallery";
  static const selectCareGroup = "selectCareGroup";
  static const medicationDose = "medicationDose";
  static const userSettingsProfile = "userSettingsProfile";
  static const userSettingsCareGroups = "userSettingsCareGroups";
  static const userSettingsCreateCareGroup = "userSettingsCreateCareGroup";
  static const userSettingsHomepage = "userSettingsHomepage";
  static const userSettingsAlerts = "userSettingsAlerts";
  static const userSettingsSecurity = "userSettingsSecurity";
  static const verifyEmail = "verifyEmail";
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
          final sync = inviteAuthScreenSyncRedirectTarget(
            matchedLocation: loc,
            uri: state.uri,
          );
          if (sync != null) {
            return sync;
          }
          if (inviteUriPointsAtAuthScreenWithInvite(state.uri) &&
              loc == state.uri.path) {
            return null;
          }
          if (loc == "/loading") return null;
          return "/loading";
        }

        if (authState.status == AuthStatus.unauthenticated) {
          final effUri = effectiveInviteAwareUri(state.uri);
          final norm = normalizeAuthPath(effUri.path);
          if (norm == "/sign-in" &&
              effUri.queryParameters["invite"]?.trim().isNotEmpty == true) {
            return Uri(
              path: "/register",
              queryParameters: effUri.queryParameters,
            ).toString();
          }
          if (loc == "/sign-in" ||
              loc == "/register" ||
              loc == "/invite-existing-user" ||
              loc == "/verify-email") {
            return null;
          }
          return "/sign-in";
        }

        if (profileState is ProfileError) {
          if (loc == "/home") return null;
          return "/home";
        }

        if (profileState is ProfileLoading ||
            profileState is ProfileAnonymous) {
          /// Invite deep links must not bounce to [/loading]: that drops query
          /// params before sign-in can run [inviteSignedLinkNeedsDifferentFirebaseUser]
          /// and [SignInScreen] mismatch sign-out, and it strips `?invite=` so the
          /// inline invite-join step is not shown after register.
          final isAuthScreen = loc == "/sign-in" ||
              loc == "/register" ||
              loc == "/invite-existing-user";
          if (authState.status == AuthStatus.authenticated && isAuthScreen) {
            final eff = effectiveInviteAwareUri(state.uri);
            final hasInvite =
                (eff.queryParameters["invite"]?.trim() ?? "").isNotEmpty;
            if (hasInvite) {
              return null;
            }
            if (inviteSignedLinkNeedsDifferentFirebaseUser(
              authState: authState,
              uri: state.uri,
            )) {
              return null;
            }
          }
          return loc == "/loading" ? null : "/loading";
        }

        if (profileState is ProfileReady) {
          final profile = profileState.profile;
          final pr = profileState;

          // Email verification links must reach [VerifyAlternateEmailScreen]
          // even before the wizard is completed, so a brand-new user clicking
          // their first verification link doesn't get bounced into setup.
          if (loc == "/verify-email") {
            return null;
          }

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

          if (state.uri.path == "/select-care-group" &&
              state.uri.queryParameters["picker"] != "1") {
            return "/home";
          }

          if (loc.startsWith("/setup") && profile.wizardCompleted) {
            if (state.uri.queryParameters["edit"] != "1") {
              return "/home";
            }
          }

          if (loc == "/sign-in" ||
              loc == "/register" ||
              loc == "/invite-existing-user") {
            if (inviteSignedLinkNeedsDifferentFirebaseUser(
              authState: authState,
              uri: state.uri,
            )) {
              return null;
            }
          }

          if (loc == "/sign-in" ||
              loc == "/register" ||
              loc == "/loading" ||
              loc == "/invite-existing-user") {
            return "/home";
          }
        }

        return null;
      },
      // Web opens at `/` by default; without this, no [GoRoute] matches and the
      // shell can paint an empty grey frame after the bootstrap spinner.
      routes: [
        GoRoute(
          path: "/",
          redirect: (context, state) => "/loading",
        ),
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
          path: "/invite-existing-user",
          name: AppRouteNames.inviteExistingUser,
          builder: (context, state) => const InviteExistingUserScreen(),
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
            final title =
                state.extra is String ? state.extra! as String : "Feature";
            return ComingSoonScreen(title: title);
          },
        ),
        GoRoute(
          path: "/calendar",
          name: AppRouteNames.calendar,
          builder: (context, state) => const CalendarScreen(),
        ),
        GoRoute(
          path: "/expenses",
          name: AppRouteNames.expenses,
          builder: (context, state) => const ExpensesScreen(),
        ),
        GoRoute(
          path: "/chat",
          name: AppRouteNames.chat,
          builder: (context, state) => const ChatChannelsScreen(),
          routes: [
            GoRoute(
              path: ":channelId",
              name: AppRouteNames.chatChannel,
              builder: (context, state) {
                final id = state.pathParameters["channelId"]!;
                final cg = state.uri.queryParameters["careGroupId"];
                return ChannelChatScreen(
                  channelId: id,
                  careGroupIdFromRoute: cg,
                );
              },
            ),
          ],
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
          path: "/document-library",
          name: AppRouteNames.documentLibrary,
          builder: (context, state) => const DocumentLibraryScreen(),
        ),
        GoRoute(
          path: "/medications",
          name: AppRouteNames.medications,
          builder: (context, state) => const MedicationsScreen(),
        ),
        GoRoute(
          path: "/photo-gallery",
          name: AppRouteNames.photoGallery,
          builder: (context, state) => const PhotoGalleryScreen(),
        ),
        GoRoute(
          path: "/medication-dose",
          name: AppRouteNames.medicationDose,
          builder: (context, state) => const MedicationDoseConfirmScreen(),
        ),
        GoRoute(
          path: "/members",
          name: AppRouteNames.members,
          builder: (context, state) => const MembersScreen(),
        ),
        GoRoute(
          path: "/user-settings/care-group",
          name: AppRouteNames.careGroupSettings,
          builder: (context, state) => const CareGroupSettingsScreen(),
        ),
        GoRoute(
          path: "/user-settings/profile",
          name: AppRouteNames.userSettingsProfile,
          builder: (context, state) => const UserSettingsProfileScreen(),
        ),
        GoRoute(
          path: "/user-settings/care-groups",
          name: AppRouteNames.userSettingsCareGroups,
          builder: (context, state) => const UserSettingsCareGroupsScreen(),
        ),
        GoRoute(
          path: "/user-settings/create-care-group",
          name: AppRouteNames.userSettingsCreateCareGroup,
          builder: (context, state) => const CreateCareGroupScreen(),
        ),
        GoRoute(
          path: "/user-settings/homepage",
          name: AppRouteNames.userSettingsHomepage,
          builder: (context, state) => const UserSettingsHomepageScreen(),
        ),
        GoRoute(
          path: "/user-settings/alerts",
          name: AppRouteNames.userSettingsAlerts,
          builder: (context, state) => const UserSettingsAlertsScreen(),
        ),
        GoRoute(
          path: "/user-settings/security",
          name: AppRouteNames.userSettingsSecurity,
          builder: (context, state) => const UserSettingsSecurityScreen(),
        ),
        GoRoute(
          path: "/verify-email",
          name: AppRouteNames.verifyEmail,
          builder: (context, state) {
            final token = state.uri.queryParameters["token"]?.trim() ?? "";
            return VerifyAlternateEmailScreen(token: token);
          },
        ),
      ],
      errorBuilder: (context, state) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "That page isn’t available in this app.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    state.uri.toString(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => GoRouter.of(context).go("/loading"),
                    child: const Text("Go to app"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
