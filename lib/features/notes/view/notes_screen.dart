import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/notes_cubit.dart";
import "../cubit/notes_state.dart";
import "../models/care_group_note.dart";
import "../repository/notes_repository.dart";

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final cg = state.profile.activeCareGroupId;
        if (cg == null || cg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Notes")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to use shared notes. Complete setup first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey(cg),
          create: (context) => NotesCubit(
            repository: context.read<NotesRepository>(),
            careGroupId: cg,
          )..subscribe(),
          child: const _NotesView(),
        );
      },
    );
  }
}

class _NotesView extends StatelessWidget {
  const _NotesView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Notes"),
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
        child: BlocConsumer<NotesCubit, NotesState>(
          listener: (context, state) {
            if (state is NotesFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            if (state is NotesInitial || state is NotesLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is NotesEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "No notes yet. Add updates for other carers, medical context, or legal items (only principals and people with the right access can read legal / sensitive content).",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (state is NotesDisplay) {
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final n = state.list[i];
                  final isLegal = n.category == "legal" || n.sensitive == true;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        isLegal ? Icons.gavel : Icons.note_alt_outlined,
                        color: isLegal
                            ? Theme.of(context).colorScheme.tertiary
                            : AppColors.tealPrimary,
                      ),
                      title: Text(n.title),
                      subtitle: Text(
                        [
                          n.type,
                          if (n.body != null && n.body!.isNotEmpty) n.body!,
                          if (n.createdAt != null) _formatDate(n.createdAt!),
                        ].where((e) => e.isNotEmpty).join(" · "),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: n.body != null && n.body!.length > 40,
                      onTap: () => _openEditor(context, n),
                    ),
                  );
                },
              );
            }
            if (state is NotesFailure) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatDate(DateTime d) {
    return "${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}";
  }

  Future<void> _openEditor(BuildContext context, CareGroupNote? existing) async {
    final isNew = existing == null;
    final titleC = TextEditingController(text: existing?.title ?? "");
    final bodyC = TextEditingController(text: existing?.body ?? "");
    var type = existing?.type ?? "general";
    if (!const {"general", "medical", "visit"}.contains(type)) {
      type = "general";
    }
    var legal = existing?.category == "legal";

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
              return StatefulBuilder(
                builder: (ctx, setLocal) {
                  return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        isNew ? "New note" : "Edit note",
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: titleC,
                        decoration: const InputDecoration(labelText: "Title"),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String>(type),
                        initialValue: type,
                        decoration: const InputDecoration(labelText: "Type"),
                        items: const [
                          DropdownMenuItem(value: "general", child: Text("General")),
                          DropdownMenuItem(value: "medical", child: Text("Medical")),
                          DropdownMenuItem(value: "visit", child: Text("Visit / appointment")),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => type = v);
                        },
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: legal,
                        onChanged: (v) {
                          setLocal(() => legal = v ?? false);
                        },
                        title: const Text("Mark as legal / highly sensitive (restricted read)"),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: bodyC,
                        minLines: 4,
                        maxLines: 12,
                        decoration: const InputDecoration(
                          labelText: "Body",
                          alignLabelWithHint: true,
                        ),
                        textCapitalization: TextCapitalization.sentences,
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
                                    title: const Text("Delete note?"),
                                    content: const Text(
                                      "Deletion may require principal or power-of-attorney access in your Firestore rules.",
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
                                    await context.read<NotesCubit>().deleteNote(existing.id);
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
                              final cubit = context.read<NotesCubit>();
                              try {
                                if (isNew) {
                                  await cubit.addNote(
                                    title: titleC.text,
                                    type: type,
                                    body: bodyC.text,
                                    legalCategory: legal ? "legal" : null,
                                  );
                                } else {
                                  await cubit.updateNote(
                                    noteId: existing.id,
                                    title: titleC.text,
                                    type: type,
                                    body: bodyC.text,
                                    legalCategory: legal ? "legal" : null,
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
              );
            },
          ),
        );
      },
    );
  }
}
