import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/invitations_cubit.dart";
import "../cubit/invitations_state.dart";
import "../repository/invitation_repository.dart";

class InvitationsScreen extends StatelessWidget {
  const InvitationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final p = state.profile;
        final hid = p.activeHouseholdId;
        final cg = p.activeCareGroupId;
        if (hid == null || hid.isEmpty || cg == null || cg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Invitations")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need an active care group to manage invitations. Finish setup or join a care group first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey("$cg::$hid"),
          create: (context) => InvitationsCubit(
            repository: context.read<InvitationRepository>(),
            careGroupId: cg,
            householdId: hid,
          )..subscribe(),
          child: const _InvitationsView(),
        );
      },
    );
  }
}

class _InvitationsView extends StatelessWidget {
  const _InvitationsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Invitations"),
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
        child: BlocConsumer<InvitationsCubit, InvitationsState>(
          listener: (context, state) {
            if (state is InvitationsFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
          },
          builder: (context, state) {
            if (state is InvitationsInitial || state is InvitationsLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state is InvitationsEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    "No pending or past invitations. Invite a carer or family member by email.",
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (state is InvitationsDisplay) {
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final inv = state.list[i];
                  return Card(
                    child: ListTile(
                      title: Text(inv.invitedEmail),
                      subtitle: Text("Status: ${inv.status}"),
                      leading: const Icon(Icons.mail_outline),
                    ),
                  );
                },
              );
            }
            if (state is InvitationsFailure) {
              return Center(child: Text(state.message));
            }
            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _invite(context),
        child: const Icon(Icons.person_add_alt_1),
      ),
    );
  }

  Future<void> _invite(BuildContext context) async {
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text("Invite by email"),
          content: TextField(
            controller: c,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: "Email address",
            ),
            autofocus: true,
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text),
              child: const Text("Send"),
            ),
          ],
        );
      },
    );
    if (email == null || !email.contains("@") || !context.mounted) return;
    try {
      await context.read<InvitationsCubit>().invite(email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invitation created.")),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}
