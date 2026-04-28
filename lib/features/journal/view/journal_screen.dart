import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/bloc/auth_state.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/journal_cubit.dart";
import "../cubit/journal_state.dart";
import "../models/journal_entry.dart";
import "../repository/journal_repository.dart";

class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key});

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
            appBar: AppBar(title: const Text("Journal")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to use the journal. Complete setup first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey(cg),
          create: (context) => JournalCubit(
            repository: context.read<JournalRepository>(),
            careGroupId: cg,
          )..subscribe(),
          child: const _JournalView(),
        );
      },
    );
  }
}

class _JournalView extends StatelessWidget {
  const _JournalView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<JournalCubit, JournalState>(
      listener: (context, state) {
        if (state is JournalFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        final canCompose = state is JournalEmpty || state is JournalDisplay;
        return Scaffold(
          appBar: AppBar(
            title: const Text("Journal"),
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
            child: _JournalBody(state: state),
          ),
          floatingActionButton: canCompose
              ? FloatingActionButton(
                  onPressed: () => _openEditor(context, null),
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }
}

class _JournalBody extends StatelessWidget {
  const _JournalBody({required this.state});

  final JournalState state;

  @override
  Widget build(BuildContext context) {
    if (state is JournalInitial || state is JournalLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is JournalForbidden) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "The care journal is only available to people with a carer or organiser role in this care group. "
            "If you use CareShare in a limited “receiving care” mode, use other areas your team has shared with you.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state is JournalEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "No journal entries yet. Add a dated log for handovers, visits, and how things are going.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state case final JournalDisplay display) {
      final entries = display.list;
      return BlocBuilder<AuthBloc, AuthState>(
        buildWhen: (p, c) => p.user?.uid != c.user?.uid,
        builder: (context, auth) {
          final selfUid = auth.user?.uid;
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final e = entries[i];
              final mine = selfUid != null && e.createdBy == selfUid;
              final parts = <String>[];
              if (mine) {
                parts.add("You");
              } else if (e.createdBy.isNotEmpty) {
                parts.add("Carer");
              }
              if (e.body != null && e.body!.isNotEmpty) {
                parts.add(e.body!);
              }
              if (e.createdAt != null) {
                parts.add(_formatDate(e.createdAt!));
              }
              return Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.menu_book_outlined,
                    color: AppColors.tealPrimary,
                  ),
                  title: Text(e.title),
                  subtitle: Text(
                    parts.join(" · "),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: e.body != null && e.body!.length > 50,
                  onTap: () => _openEditor(context, e),
                ),
              );
            },
          );
        },
      );
    }
    if (state case final JournalFailure failure) {
      return Center(child: Text(failure.message));
    }
    return const SizedBox.shrink();
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";
  }
}

Future<void> _openEditor(BuildContext context, JournalEntry? existing) async {
  final isNew = existing == null;
  final titleC = TextEditingController(text: existing?.title ?? "");
  final bodyC = TextEditingController(text: existing?.body ?? "");

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(ctx).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          initialChildSize: 0.75,
          builder: (ctx, scroll) {
            return ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      isNew ? "New entry" : "Edit entry",
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: "Title",
                        hintText: "e.g. Home visit, night shift",
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyC,
                      minLines: 5,
                      maxLines: 14,
                      decoration: const InputDecoration(
                        labelText: "Details",
                        alignLabelWithHint: true,
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Deletion is only allowed for the principal carer (per security rules).",
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: AppColors.grey500,
                          ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (!isNew) ...[
                          TextButton(
                            onPressed: () async {
                              final go = await showDialog<bool>(
                                context: ctx,
                                builder: (d) => AlertDialog(
                                  title: const Text("Delete entry?"),
                                  content: const Text(
                                    "Only the principal carer can delete journal entries. If you are not the principal, this will fail.",
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(d).pop(false),
                                      child: const Text("Cancel"),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.of(d).pop(true),
                                      child: const Text("Delete"),
                                    ),
                                  ],
                                ),
                              );
                              if (go == true && context.mounted) {
                                try {
                                  await context.read<JournalCubit>().deleteEntry(existing.id);
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                }
                              }
                            },
                            child: const Text("Delete"),
                          ),
                          const Spacer(),
                        ],
                        FilledButton(
                          onPressed: () async {
                            if (titleC.text.trim().isEmpty) return;
                            final cubit = context.read<JournalCubit>();
                            try {
                              if (isNew) {
                                await cubit.addEntry(
                                  title: titleC.text,
                                  body: bodyC.text,
                                );
                              } else {
                                await cubit.updateEntry(
                                  entryId: existing.id,
                                  title: titleC.text,
                                  body: bodyC.text,
                                );
                              }
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          },
                          child: Text(isNew ? "Add" : "Save"),
                        ),
                      ],
                    ),
                  ],
                );
          },
        ),
      );
    },
  );
}
