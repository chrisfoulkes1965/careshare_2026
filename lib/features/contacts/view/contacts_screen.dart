import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/contacts_cubit.dart";
import "../cubit/contacts_state.dart";
import "../models/household_contact.dart";
import "../repository/contacts_repository.dart";

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

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
            appBar: AppBar(title: const Text("Contacts")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to manage contacts. Complete setup first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey(cg),
          create: (context) => ContactsCubit(
            repository: context.read<ContactsRepository>(),
            careGroupId: cg,
          )..subscribe(),
          child: const _ContactsView(),
        );
      },
    );
  }
}

void _copy(BuildContext context, String label, String value) {
  if (value.isEmpty) return;
  Clipboard.setData(ClipboardData(text: value));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("$label copied")),
  );
}

String _permissionHint(Object e) {
  final s = e.toString();
  if (s.contains("permission-denied") || s.contains("PERMISSION_DENIED")) {
    return "Only principal carers and carers can add or change contacts in your Firestore rules.";
  }
  return s;
}

class _ContactsView extends StatelessWidget {
  const _ContactsView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ContactsCubit, ContactsState>(
      listener: (context, state) {
        if (state is ContactsFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_permissionHint(state.message))),
          );
        }
      },
      builder: (context, state) {
        final canCompose = state is ContactsEmpty || state is ContactsDisplay;
        return Scaffold(
          appBar: AppBar(
            title: const Text("Contacts"),
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
            child: _ContactsBody(state: state),
          ),
          floatingActionButton: canCompose
              ? FloatingActionButton(
                  onPressed: () => _openEditor(context, null),
                  child: const Icon(Icons.person_add_outlined),
                )
              : null,
        );
      },
    );
  }
}

class _ContactsBody extends StatelessWidget {
  const _ContactsBody({required this.state});

  final ContactsState state;

  @override
  Widget build(BuildContext context) {
    if (state is ContactsInitial || state is ContactsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is ContactsEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "No contacts yet. Add GPs, district nurses, family, or trusted trades — everyone in the care group can see this list. "
            "Edits are limited to principal carers and carers in your security rules.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state case final ContactsDisplay display) {
      final list = display.list;
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final c = list[i];
          final subtitle = <String>[];
          if (c.phone != null && c.phone!.isNotEmpty) subtitle.add(c.phone!);
          if (c.email != null && c.email!.isNotEmpty) subtitle.add(c.email!);
          if (c.notes != null && c.notes!.isNotEmpty) {
            final n = c.notes!.length > 80 ? "${c.notes!.substring(0, 80)}…" : c.notes!;
            subtitle.add(n);
          }
          return Card(
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.tealLight,
                child: Icon(Icons.contact_phone_outlined, color: AppColors.tealPrimary),
              ),
              title: Text(c.name),
              subtitle: subtitle.isEmpty
                  ? null
                  : Text(
                      subtitle.join(" · "),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
              isThreeLine: subtitle.length > 1,
              onTap: () => _openEditor(context, c),
            ),
          );
        },
      );
    }
    if (state case final ContactsFailure failure) {
      return Center(child: Text(failure.message));
    }
    return const SizedBox.shrink();
  }
}

Future<void> _openEditor(BuildContext context, CareGroupContact? existing) async {
  final isNew = existing == null;
  final contact = existing;
  final nameC = TextEditingController(text: contact?.name ?? "");
  final phoneC = TextEditingController(text: contact?.phone ?? "");
  final emailC = TextEditingController(text: contact?.email ?? "");
  final notesC = TextEditingController(text: contact?.notes ?? "");

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
          minChildSize: 0.5,
          maxChildSize: 0.95,
          initialChildSize: 0.8,
          builder: (ctx, scroll) {
            return ListView(
              controller: scroll,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  isNew ? "New contact" : "Edit contact",
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameC,
                  decoration: const InputDecoration(
                    labelText: "Name",
                    hintText: "e.g. Dr Smith, home care agency",
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneC,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: "Phone",
                    suffixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                if (!isNew && contact != null && contact.phone != null && contact.phone!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _copy(ctx, "Phone", contact.phone!),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text("Copy phone"),
                    ),
                  ),
                const SizedBox(height: 4),
                TextField(
                  controller: emailC,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Email",
                    suffixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                if (!isNew && contact != null && contact.email != null && contact.email!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _copy(ctx, "Email", contact.email!),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text("Copy email"),
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesC,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: "Notes",
                    alignLabelWithHint: true,
                    hintText: "Address, opening hours, relationship…",
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
                              title: const Text("Delete contact?"),
                              content: const Text(
                                "This cannot be undone. You need carer or principal carer access in your Firestore rules.",
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
                              await context.read<ContactsCubit>().deleteContact(contact!.id);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(_permissionHint(e))),
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
                        if (nameC.text.trim().isEmpty) return;
                        final cubit = context.read<ContactsCubit>();
                        try {
                          if (isNew) {
                            await cubit.addContact(
                              name: nameC.text,
                              phone: phoneC.text,
                              email: emailC.text,
                              notes: notesC.text,
                            );
                          } else {
                            await cubit.updateContact(
                              contactId: contact!.id,
                              name: nameC.text,
                              phone: phoneC.text,
                              email: emailC.text,
                              notes: notesC.text,
                            );
                          }
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_permissionHint(e))),
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
