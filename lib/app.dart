import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "core/medication_reminders/medication_notification_service.dart";
import "core/push/careshare_push_service.dart";
import "core/theme/app_theme.dart";
import "core/theme/care_group_header_theme.dart";
import "features/auth/bloc/auth_bloc.dart";
import "features/auth/repository/auth_repository.dart";
import "features/care_pathway/repository/pathways_repository.dart";
import "features/chat/repository/chat_repository.dart";
import "features/contacts/repository/contacts_repository.dart";
import "features/expenses/repository/expenses_repository.dart";
import "features/invitations/repository/invitation_repository.dart";
import "features/journal/repository/journal_repository.dart";
import "features/medications/repository/medication_care_group_settings_repository.dart";
import "features/medications/repository/medications_repository.dart";
import "features/medications/view/medication_dose_route_args.dart";
import "features/meetings/repository/meetings_repository.dart";
import "features/calendar/repository/linked_calendar_events_repository.dart";
import "features/members/repository/members_repository.dart";
import "features/notes/repository/notes_repository.dart";
import "features/profile/cubit/profile_cubit.dart";
import "features/profile/cubit/profile_state.dart";
import "features/setup_wizard/repository/setup_repository.dart";
import "features/settings/repository/group_calendar_service.dart";
import "features/tasks/repository/task_repository.dart";
import "features/user/repository/user_repository.dart";
import "router/app_router.dart";
import "router/session_refresh.dart";

class CareShareApp extends StatefulWidget {
  const CareShareApp({super.key});

  @override
  State<CareShareApp> createState() => _CareShareAppState();
}

class _CareShareAppState extends State<CareShareApp>
    with WidgetsBindingObserver {
  GoRouter? _router;
  SessionRefresh? _sessionRefresh;
  bool _doseNavRegistered = false;
  bool _pushBound = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authBloc = context.read<AuthBloc>();
      final profileCubit = context.read<ProfileCubit>();
      _sessionRefresh ??=
          SessionRefresh(authBloc: authBloc, profileCubit: profileCubit);
      setState(() {
        _router ??= AppRouter.create(
          authBloc: authBloc,
          profileCubit: profileCubit,
          sessionRefresh: _sessionRefresh!,
        );
        if (_router != null && !_pushBound) {
          _pushBound = true;
          CaresharePushService.instance.bind(
            router: _router!,
            userRepository: context.read<UserRepository>(),
            profileCubit: profileCubit,
          );
        }
        if (_router != null && !_doseNavRegistered) {
          _doseNavRegistered = true;
          MedicationNotificationService.instance
              .setDosePayloadHandler((payload) {
            final parts = payload.split("|");
            if (parts.length < 3) {
              return;
            }
            final cg = parts[1];
            final ids = parts[2]
                .split(",")
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            if (ids.isEmpty) {
              return;
            }
            _router!.push(
              "/medication-dose",
              extra: MedicationDoseRouteArgs(
                careGroupId: cg,
                medicationIds: ids,
              ),
            );
          });
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionRefresh?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      MedicationNotificationService.instance.onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    if (router == null) {
      return MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return MaterialApp.router(
      title: "CareShare",
      theme: AppTheme.light(),
      routerConfig: router,
      builder: (context, child) {
        return BlocBuilder<ProfileCubit, ProfileState>(
          buildWhen: (prev, next) {
            if (prev is ProfileReady && next is ProfileReady) {
              return prev.activeCareGroupThemeArgb !=
                  next.activeCareGroupThemeArgb;
            }
            return (prev is ProfileReady) != (next is ProfileReady);
          },
          builder: (context, state) {
            final w = child ?? const SizedBox.shrink();
            if (state is! ProfileReady) {
              return w;
            }
            return Theme(
              data: buildCareGroupAppTheme(
                Theme.of(context),
                activeThemeArgb: state.activeCareGroupThemeArgb,
              ),
              child: w,
            );
          },
        );
      },
    );
  }
}

class CareShareRoot extends StatelessWidget {
  const CareShareRoot({super.key, required this.firebaseReady});

  final bool firebaseReady;

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider(
      create: (_) => AuthRepository(firebaseReady: firebaseReady),
      child: RepositoryProvider(
        create: (_) => UserRepository(firebaseReady: firebaseReady),
        child: RepositoryProvider(
          create: (_) =>
              GroupCalendarService(firebaseReady: firebaseReady),
          child: RepositoryProvider(
            create: (_) => SetupRepository(firebaseReady: firebaseReady),
            child: RepositoryProvider(
              create: (_) => TaskRepository(firebaseReady: firebaseReady),
              child: RepositoryProvider(
              create: (_) => InvitationRepository(firebaseReady: firebaseReady),
              child: RepositoryProvider(
                create: (_) => JournalRepository(firebaseReady: firebaseReady),
                child: RepositoryProvider(
                  create: (_) =>
                      PathwaysRepository(firebaseReady: firebaseReady),
                  child: RepositoryProvider(
                    create: (_) =>
                        NotesRepository(firebaseReady: firebaseReady),
                    child: RepositoryProvider(
                      create: (_) =>
                          MembersRepository(firebaseReady: firebaseReady),
                      child: RepositoryProvider(
                        create: (_) =>
                            ContactsRepository(firebaseReady: firebaseReady),
                        child: RepositoryProvider(
                          create: (_) =>
                              ExpensesRepository(firebaseReady: firebaseReady),
                          child: RepositoryProvider(
                            create: (_) =>
                                ChatRepository(firebaseReady: firebaseReady),
                            child: RepositoryProvider(
                              create: (_) => MeetingsRepository(
                                  firebaseReady: firebaseReady),
                              child: RepositoryProvider(
                                create: (_) => LinkedCalendarEventsRepository(
                                  firebaseReady: firebaseReady,
                                ),
                                child: RepositoryProvider(
                                  create: (_) =>
                                      MedicationCareGroupSettingsRepository(
                                          firebaseReady: firebaseReady),
                                  child: RepositoryProvider(
                                    create: (_) => MedicationsRepository(
                                        firebaseReady: firebaseReady),
                                    child: BlocProvider(
                                      create: (context) => AuthBloc(
                                        repository:
                                            context.read<AuthRepository>(),
                                      ),
                                      child: BlocProvider(
                                        create: (context) => ProfileCubit(
                                          authBloc: context.read<AuthBloc>(),
                                          userRepository:
                                              context.read<UserRepository>(),
                                          invitationRepository: context
                                              .read<InvitationRepository>(),
                                        ),
                                        child: const CareShareApp(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
