import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "core/medication_reminders/medication_notification_service.dart";
import "core/theme/app_theme.dart";
import "features/auth/bloc/auth_bloc.dart";
import "features/auth/repository/auth_repository.dart";
import "features/care_pathway/repository/pathways_repository.dart";
import "features/contacts/repository/contacts_repository.dart";
import "features/invitations/repository/invitation_repository.dart";
import "features/journal/repository/journal_repository.dart";
import "features/medications/repository/medications_repository.dart";
import "features/meetings/repository/meetings_repository.dart";
import "features/members/repository/members_repository.dart";
import "features/notes/repository/notes_repository.dart";
import "features/profile/profile_cubit.dart";
import "features/setup_wizard/repository/setup_repository.dart";
import "features/tasks/repository/task_repository.dart";
import "features/user/repository/user_repository.dart";
import "router/app_router.dart";
import "router/session_refresh.dart";

class CareShareApp extends StatefulWidget {
  const CareShareApp({super.key});

  @override
  State<CareShareApp> createState() => _CareShareAppState();
}

class _CareShareAppState extends State<CareShareApp> with WidgetsBindingObserver {
  GoRouter? _router;
  SessionRefresh? _sessionRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authBloc = context.read<AuthBloc>();
      final profileCubit = context.read<ProfileCubit>();
      _sessionRefresh ??= SessionRefresh(authBloc: authBloc, profileCubit: profileCubit);
      setState(() {
        _router ??= AppRouter.create(
          authBloc: authBloc,
          profileCubit: profileCubit,
          sessionRefresh: _sessionRefresh!,
        );
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
          create: (_) => SetupRepository(firebaseReady: firebaseReady),
          child: RepositoryProvider(
            create: (_) => TaskRepository(firebaseReady: firebaseReady),
            child: RepositoryProvider(
              create: (_) => InvitationRepository(firebaseReady: firebaseReady),
              child: RepositoryProvider(
                create: (_) => JournalRepository(firebaseReady: firebaseReady),
                child: RepositoryProvider(
                  create: (_) => PathwaysRepository(firebaseReady: firebaseReady),
                  child: RepositoryProvider(
                    create: (_) => NotesRepository(firebaseReady: firebaseReady),
                    child: RepositoryProvider(
                      create: (_) => MembersRepository(firebaseReady: firebaseReady),
                      child: RepositoryProvider(
                        create: (_) => ContactsRepository(firebaseReady: firebaseReady),
                        child: RepositoryProvider(
                          create: (_) => MeetingsRepository(firebaseReady: firebaseReady),
                          child: RepositoryProvider(
                            create: (_) => MedicationsRepository(firebaseReady: firebaseReady),
                            child: BlocProvider(
                              create: (context) => AuthBloc(
                                repository: context.read<AuthRepository>(),
                              ),
                              child: BlocProvider(
                                create: (context) => ProfileCubit(
                                  authBloc: context.read<AuthBloc>(),
                                  userRepository: context.read<UserRepository>(),
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
    );
  }
}
