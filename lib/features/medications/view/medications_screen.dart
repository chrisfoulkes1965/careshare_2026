import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../cubit/medications_state.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/medications_cubit.dart";
import "../models/household_medication.dart";
import "../repository/medications_repository.dart";
import "medication_editor_sheet.dart";

class MedicationsScreen extends StatelessWidget {
  const MedicationsScreen({super.key});

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
            appBar: AppBar(title: const Text("Prescriptions & reminders")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Set up a care group first so your home can store medications and reminders.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return BlocProvider(
          key: ObjectKey(hid),
          create: (context) => MedicationsCubit(
            repository: context.read<MedicationsRepository>(),
            householdId: hid,
          )..subscribe(),
          child: const _MedicationsView(),
        );
      },
    );
  }
}

class _MedicationsView extends StatelessWidget {
  const _MedicationsView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<MedicationsCubit, MedicationsState>(
      listener: (context, state) {
        if (state is MedicationsFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Prescriptions & reminders"),
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
            child: _Body(state: state),
          ),
          floatingActionButton: (state is MedicationsEmpty || state is MedicationsDisplay)
              ? FloatingActionButton(
                  onPressed: () => MedicationEditorSheet.show(context),
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.state});

  final MedicationsState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      MedicationsInitial() || MedicationsLoading() => const Center(
          child: CircularProgressIndicator(),
        ),
      MedicationsFailure(:final message) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(message, textAlign: TextAlign.center),
          ),
        ),
      MedicationsEmpty() => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              "CareShare is not a medical device. Enter details from your own labels or a photo. "
              "If adding reminders fails, your account may need to be a principal carer in this home.",
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(
              "No medications yet. Add one to store doses and (on phone or desktop) get local reminders.",
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      MedicationsDisplay(:final list) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            return _MedCard(m: list[i]);
          },
        ),
    };
  }
}

class _MedCard extends StatelessWidget {
  const _MedCard({required this.m});

  final HouseholdMedication m;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        isThreeLine: m.instructions.isNotEmpty || m.notes.isNotEmpty,
        onTap: () {
          MedicationEditorSheet.show(context, existing: m);
        },
        title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.dosage.isNotEmpty) Text(m.dosage),
            if (m.reminderEnabled) ...[
              const SizedBox(height: 4),
              Text(
                m.reminderTimes.isEmpty
                    ? "Reminders on (add times in edit)"
                    : "Reminders: ${m.reminderTimes.map((t) => "${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}").join(", ")}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (m.instructions.isNotEmpty) Text(m.instructions, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (m.notes.isNotEmpty) Text(m.notes, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            if (m.photoUrl != null && m.photoUrl!.isNotEmpty) const Text("Has photo", style: TextStyle(fontSize: 12)),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: "Delete",
          onPressed: () async {
            final go = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("Delete medication?"),
                content: const Text("Reminders for this item will be rescheduled for your other medications."),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Cancel")),
                  FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Delete")),
                ],
              ),
            );
            if (go == true && context.mounted) {
              try {
                await context.read<MedicationsCubit>().deleteMedication(m.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            }
          },
        ),
      ),
    );
  }
}
