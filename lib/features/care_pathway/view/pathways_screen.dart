import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../repository/pathways_repository.dart";

class PathwaysScreen extends StatelessWidget {
  const PathwaysScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final hid = state.profile.activeHouseholdId;
        if (hid == null || hid.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Pathways")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Set up a care group to see the care pathways you selected.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _PathwaysBody(householdId: hid);
      },
    );
  }
}

class _PathwaysBody extends StatelessWidget {
  const _PathwaysBody({required this.householdId});

  final String householdId;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<PathwaysRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text("Care pathways"),
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
      body: FutureBuilder<HouseholdPathwaysSummary>(
        future: repo.getHouseholdPathways(householdId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snap.error.toString(),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return SafeArea(
            child: _PathwaysList(summary: snap.data!),
          );
        },
      ),
    );
  }
}

class _PathwaysList extends StatelessWidget {
  const _PathwaysList({required this.summary});

  final HouseholdPathwaysSummary summary;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (summary.householdName != null) ...[
          Text(
            summary.householdName!,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
        ],
        Text(
          "Your selection",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (summary.selected.isEmpty)
          const Text(
            "No pathways on your home document yet. They are set during setup or care group settings (coming soon).",
          )
        else
          ...summary.selected.map(
            (o) => Card(
              child: ListTile(
                title: Text(o.title),
                subtitle: o.description.isNotEmpty
                    ? Text(o.description)
                    : null,
              ),
            ),
          ),
        const SizedBox(height: 24),
        Text(
          "Library (system)",
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (summary.system.isEmpty)
          Text(
            "No system pathways in Firestore yet. You can add documents under the carePathways collection in the console, or seed them in a later release.",
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          ...summary.system.map(
            (o) => Card(
              child: ListTile(
                title: Text(o.title),
                subtitle: o.description.isNotEmpty
                    ? Text(o.description)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}
