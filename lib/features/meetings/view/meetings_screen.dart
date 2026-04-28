import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/meetings_cubit.dart";
import "../cubit/meetings_state.dart";
import "../repository/meetings_repository.dart";
import "meeting_editor_sheet.dart";

class MeetingsScreen extends StatelessWidget {
  const MeetingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final cg = state.activeCareGroupDataId;
        if (cg == null || cg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Meetings")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to plan meetings. Complete setup first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey(cg),
          create: (context) => MeetingsCubit(
            repository: context.read<MeetingsRepository>(),
            careGroupId: cg,
          )..subscribe(),
          child: const _MeetingsView(),
        );
      },
    );
  }
}

class _MeetingsView extends StatelessWidget {
  const _MeetingsView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MeetingsCubit, MeetingsState>(
      listener: (context, state) {
        if (state is MeetingsFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        final canCompose = state is MeetingsEmpty || state is MeetingsDisplay;
        return Scaffold(
          appBar: AppBar(
            title: const Text("Meetings"),
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
          body: SafeArea(
            child: _MeetingsBody(state: state),
          ),
          floatingActionButton: canCompose
              ? FloatingActionButton(
                  onPressed: () => MeetingEditorSheet.show(context),
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }
}

class _MeetingsBody extends StatelessWidget {
  const _MeetingsBody({required this.state});

  final MeetingsState state;

  @override
  Widget build(BuildContext context) {
    if (state is MeetingsInitial || state is MeetingsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is MeetingsForbidden) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Multi-party care meetings are not shown in limited “receiving care” mode. "
            "If you are a carer, ask a principal to confirm your care group role.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state is MeetingsEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "No meetings yet. Add scheduled reviews, family discussions, or team check-ins. "
            "Edits: carers and principal carers. Deletion: principal carer only (per your rules).",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state case final MeetingsDisplay display) {
      final items = display.list;
      return BlocBuilder<AuthBloc, AuthState>(
        buildWhen: (p, c) => p.user?.uid != c.user?.uid,
        builder: (context, auth) {
          final selfUid = auth.user?.uid;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final m = items[i];
              final mine = selfUid != null && m.createdBy == selfUid;
              final parts = <String>[];
              if (mine) {
                parts.add("You");
              } else if (m.createdBy.isNotEmpty) {
                parts.add("Organiser");
              }
              if (m.location != null && m.location!.isNotEmpty) {
                parts.add(m.location!);
              }
              if (m.body != null && m.body!.isNotEmpty) {
                final t = m.body!.length > 100 ? "${m.body!.substring(0, 100)}…" : m.body!;
                parts.add(t);
              }
              if (m.meetingAt != null) {
                parts.add(formatMeetingDateTime(m.meetingAt!));
              }
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.groups_2_outlined, color: AppColors.tealPrimary),
                  title: Text(m.title),
                  subtitle: Text(
                    parts.join(" · "),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: parts.length > 2,
                  onTap: () => MeetingEditorSheet.show(context, existing: m),
                ),
              );
            },
          );
        },
      );
    }
    if (state case final MeetingsFailure failure) {
      return Center(child: Text(failure.message));
    }
    return const SizedBox.shrink();
  }
}
