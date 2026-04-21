import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../bloc/setup_wizard_bloc.dart";
import "../bloc/setup_wizard_event.dart";
import "../bloc/setup_wizard_state.dart";
import "../models/setup_models.dart";
import "../repository/setup_repository.dart";

class SetupWizardHost extends StatefulWidget {
  const SetupWizardHost({super.key});

  @override
  State<SetupWizardHost> createState() => _SetupWizardHostState();
}

class _SetupWizardHostState extends State<SetupWizardHost> {
  SetupWizardBloc? _bloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bloc != null) return;

    final profileState = context.read<ProfileCubit>().state;
    if (profileState is! ProfileReady) return;

    _bloc = SetupWizardBloc(
      profile: profileState.profile,
      authBloc: context.read<AuthBloc>(),
      profileCubit: context.read<ProfileCubit>(),
      setupRepository: context.read<SetupRepository>(),
    );
    setState(() {});
  }

  @override
  void dispose() {
    _bloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = _bloc;
    if (bloc == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return BlocProvider.value(
      value: bloc,
      child: const _SetupWizardScaffold(),
    );
  }
}

class _SetupWizardScaffold extends StatefulWidget {
  const _SetupWizardScaffold();

  @override
  State<_SetupWizardScaffold> createState() => _SetupWizardScaffoldState();
}

class _SetupWizardScaffoldState extends State<_SetupWizardScaffold> {
  PageController? _pageController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageController ??= PageController(
      initialPage: context.read<SetupWizardBloc>().state.step.index,
    );
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pageController = _pageController;
    if (pageController == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final simpleMode = switch (context.read<ProfileCubit>().state) {
      ProfileReady(:final profile) => profile.simpleMode,
      _ => false,
    };

    return MultiBlocListener(
      listeners: [
        BlocListener<SetupWizardBloc, SetupWizardState>(
          listenWhen: (p, c) => p.step != c.step,
          listener: (context, state) {
            pageController.jumpToPage(state.step.index);
          },
        ),
        BlocListener<SetupWizardBloc, SetupWizardState>(
          listenWhen: (p, c) => p.isSubmitting && !c.isSubmitting && c.errorMessage == null,
          listener: (context, state) {
            if (state.step != SetupWizardStep.summary) return;
            final profile = context.read<ProfileCubit>().state;
            if (profile is ProfileReady && profile.profile.wizardCompleted) {
              context.go("/home");
            }
          },
        ),
      ],
      child: BlocBuilder<SetupWizardBloc, SetupWizardState>(
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(
              title: const Text("Set up CareShare"),
              leading: state.step == SetupWizardStep.welcome
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardBackPressed()),
                    ),
              actions: [
                TextButton(
                  onPressed: state.isSubmitting ? null : () => _confirmSkip(context),
                  child: const Text("Skip for now"),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: _WizardProgress(
                    step: state.step,
                    simpleMode: simpleMode,
                  ),
                ),
                if (state.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Material(
                      color: AppColors.redLight,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          state.errorMessage!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: PageView(
                    controller: pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: const [
                      _WelcomeStep(),
                      _PathwaysStep(),
                      _HouseholdStep(),
                      _InvitesStep(),
                      _AvatarStep(),
                      _SummaryStep(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmSkip(BuildContext context) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Skip setup?"),
        content: const Text(
          "You can finish this later from your dashboard. Some features work best once setup is complete.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Skip")),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    final uid = context.read<AuthBloc>().state.user?.uid;
    if (uid == null) return;

    final setupRepo = context.read<SetupRepository>();
    if (!setupRepo.isAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Firebase is not configured.")),
      );
      return;
    }

    await setupRepo.skipWizard(uid);
    await context.read<ProfileCubit>().refresh();
    if (!context.mounted) return;
    context.go("/home");
  }
}

class _WizardProgress extends StatelessWidget {
  const _WizardProgress({required this.step, required this.simpleMode});

  final SetupWizardStep step;
  final bool simpleMode;

  @override
  Widget build(BuildContext context) {
    final total = SetupWizardStep.values.length;
    final index = step.index + 1;

    if (simpleMode) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: index / total,
          minHeight: 10,
          backgroundColor: AppColors.grey200,
          color: AppColors.tealPrimary,
        ),
      );
    }

    return Row(
      children: [
        for (var i = 0; i < total; i++) ...[
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 8,
              decoration: BoxDecoration(
                color: i <= step.index ? AppColors.tealPrimary : AppColors.grey200,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          if (i != total - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Icon(Icons.volunteer_activism, size: 72, color: AppColors.tealPrimary.withOpacity(0.9)),
          const SizedBox(height: 16),
          Text(
            "Welcome to CareShare",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            "We will walk you through pathways, your household, inviting carers, and choosing an avatar. "
            "You can skip at any time and finish later.",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.grey500),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardNextPressed()),
            child: const Text("Get started"),
          ),
        ],
      ),
    );
  }
}

class _PathwaysStep extends StatelessWidget {
  const _PathwaysStep();

  IconData _iconFor(String id) {
    return switch (id) {
      "elderly_care" => Icons.elderly,
      "dementia_care" => Icons.psychology_outlined,
      "short_term_medical" => Icons.local_hospital_outlined,
      "mental_health" => Icons.spa_outlined,
      "physical_disability" => Icons.accessible_forward,
      "palliative_care" => Icons.favorite_border,
      "child_young_person" => Icons.child_care,
      "unemployment_crisis" => Icons.work_outline,
      _ => Icons.health_and_safety_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Care pathways", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "Pick everything that applies. You can change this later in household settings.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: SetupPathways.all.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final p = SetupPathways.all[index];
                final selected = context.select<SetupWizardBloc, bool>(
                  (b) => b.state.selectedPathwayIds.contains(p.id),
                );

                return InkWell(
                  onTap: () => context.read<SetupWizardBloc>().add(SetupWizardPathwayToggled(p.id)),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.tealLight : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: selected ? AppColors.tealPrimary : AppColors.grey200, width: selected ? 2 : 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_iconFor(p.id), color: AppColors.tealPrimary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.title, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              Text(p.description, style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        Checkbox(value: selected, onChanged: (_) {
                          context.read<SetupWizardBloc>().add(SetupWizardPathwayToggled(p.id));
                        }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardBackPressed()),
                  child: const Text("Back"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardNextPressed()),
                  child: const Text("Continue"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HouseholdStep extends StatelessWidget {
  const _HouseholdStep();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Household", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "Name the household and tell us who receives care.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: 12),
          BlocBuilder<SetupWizardBloc, SetupWizardState>(
            buildWhen: (p, c) =>
                p.householdName != c.householdName || p.householdDescription != c.householdDescription,
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SyncedTextField(
                    value: state.householdName,
                    decoration: const InputDecoration(labelText: "Household name"),
                    onChanged: (v) => context.read<SetupWizardBloc>().add(SetupWizardHouseholdNameChanged(v)),
                  ),
                  const SizedBox(height: 12),
                  _SyncedTextField(
                    value: state.householdDescription,
                    decoration: const InputDecoration(labelText: "Description (optional)"),
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (v) => context.read<SetupWizardBloc>().add(SetupWizardHouseholdDescriptionChanged(v)),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text("Care recipients", style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardRecipientAdded()),
                icon: const Icon(Icons.add),
                label: const Text("Add recipient"),
              ),
            ],
          ),
          Expanded(
            child: BlocBuilder<SetupWizardBloc, SetupWizardState>(
              buildWhen: (p, c) => p.recipients != c.recipients,
              builder: (context, state) {
                return ListView.separated(
                  itemCount: state.recipients.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final r = state.recipients[index];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _SyncedTextField(
                                    key: ValueKey("recipient_${r.id}"),
                                    value: r.displayName,
                                    decoration: const InputDecoration(labelText: "Name"),
                                    onChanged: (v) => context.read<SetupWizardBloc>().add(
                                          SetupWizardRecipientNameChanged(id: r.id, name: v),
                                        ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: "Remove",
                                  onPressed: state.recipients.length <= 1
                                      ? null
                                      : () => context.read<SetupWizardBloc>().add(SetupWizardRecipientRemoved(r.id)),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text("Access", style: Theme.of(context).textTheme.labelLarge),
                            const SizedBox(height: 6),
                            SegmentedButton<RecipientAccessMode>(
                              segments: [
                                const ButtonSegment(
                                  value: RecipientAccessMode.managed,
                                  label: Text("Managed profile"),
                                  icon: Icon(Icons.manage_accounts_outlined),
                                ),
                                const ButtonSegment(
                                  value: RecipientAccessMode.limitedApp,
                                  label: Text("Limited app access"),
                                  icon: Icon(Icons.visibility_outlined),
                                ),
                              ],
                              selected: {r.accessMode},
                              onSelectionChanged: (set) {
                                final mode = set.first;
                                context.read<SetupWizardBloc>().add(
                                      SetupWizardRecipientAccessChanged(id: r.id, mode: mode),
                                    );
                              },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              r.accessMode == RecipientAccessMode.managed
                                  ? "Carers manage this profile on their behalf."
                                  : "They can sign in to view their own care information (read-only).",
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.grey500),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardBackPressed()),
                  child: const Text("Back"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardNextPressed()),
                  child: const Text("Continue"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InvitesStep extends StatelessWidget {
  const _InvitesStep();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Invite carers", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "Optional. You can always invite people later.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: 12),
          BlocBuilder<SetupWizardBloc, SetupWizardState>(
            buildWhen: (p, c) => p.inviteEmailInput != c.inviteEmailInput,
            builder: (context, state) {
              return Row(
                children: [
                  Expanded(
                    child: _SyncedTextField(
                      value: state.inviteEmailInput,
                      decoration: const InputDecoration(labelText: "Email address"),
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (v) => context.read<SetupWizardBloc>().add(SetupWizardInviteInputChanged(v)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardInviteAdded()),
                    child: const Text("Add"),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BlocBuilder<SetupWizardBloc, SetupWizardState>(
              buildWhen: (p, c) => p.inviteEmails != c.inviteEmails,
              builder: (context, state) {
                if (state.inviteEmails.isEmpty) {
                  return Center(
                    child: Text(
                      "No invites yet",
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppColors.grey500),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: state.inviteEmails.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final email = state.inviteEmails[index];
                    return ListTile(
                      title: Text(email),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => context.read<SetupWizardBloc>().add(SetupWizardInviteRemoved(email)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardBackPressed()),
                  child: const Text("Back"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardNextPressed()),
                  child: const Text("Continue"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarStep extends StatelessWidget {
  const _AvatarStep();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text("Choose an avatar", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            "Creature avatars from CareShare. You can upload a photo later in your profile.",
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.grey500),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: BlocBuilder<SetupWizardBloc, SetupWizardState>(
              buildWhen: (p, c) => p.avatarIndex != c.avatarIndex,
              builder: (context, state) {
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: 24,
                  itemBuilder: (context, index) {
                    final n = index + 1;
                    final selected = state.avatarIndex == n;
                    return InkWell(
                      onTap: () => context.read<SetupWizardBloc>().add(SetupWizardAvatarSelected(n)),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? AppColors.tealPrimary : AppColors.grey200,
                            width: selected ? 3 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.asset(
                            "assets/images/avatars/avatar$n.jpg",
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: AppColors.tealLight,
                              child: Center(child: Text("$n", style: Theme.of(context).textTheme.titleLarge)),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardBackPressed()),
                  child: const Text("Back"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => context.read<SetupWizardBloc>().add(const SetupWizardNextPressed()),
                  child: const Text("Continue"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: BlocBuilder<SetupWizardBloc, SetupWizardState>(
        builder: (context, state) {
          final pathways = SetupPathways.all
              .where((p) => state.selectedPathwayIds.contains(p.id))
              .map((p) => p.title)
              .join(", ");

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text("You are ready", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                "Here is what we will create for your household.",
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.grey500),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.home_outlined),
                      title: const Text("Household"),
                      subtitle: Text(state.householdName.trim().isEmpty ? "—" : state.householdName.trim()),
                    ),
                    ListTile(
                      leading: const Icon(Icons.route_outlined),
                      title: const Text("Pathways"),
                      subtitle: Text(pathways.isEmpty ? "—" : pathways),
                    ),
                    ListTile(
                      leading: const Icon(Icons.people_outline),
                      title: const Text("Recipients"),
                      subtitle: Text(state.recipients.map((r) => r.displayName.trim()).join(", ")),
                    ),
                    ListTile(
                      leading: const Icon(Icons.mail_outline),
                      title: const Text("Invites"),
                      subtitle: Text(state.inviteEmails.isEmpty ? "None" : state.inviteEmails.join(", ")),
                    ),
                    ListTile(
                      leading: const Icon(Icons.face_retouching_natural),
                      title: const Text("Avatar"),
                      subtitle: Text("Creature #${state.avatarIndex}"),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.isSubmitting
                          ? null
                          : () => context.read<SetupWizardBloc>().add(const SetupWizardBackPressed()),
                      child: const Text("Back"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: state.isSubmitting ? null : () => context.read<SetupWizardBloc>().add(const SetupWizardSubmitted()),
                      child: state.isSubmitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text("Go to dashboard"),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SyncedTextField extends StatefulWidget {
  const _SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.keyboardType,
    this.minLines,
    this.maxLines,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;

  @override
  State<_SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<_SyncedTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(covariant _SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && oldWidget.value != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      decoration: widget.decoration,
      keyboardType: widget.keyboardType,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      onChanged: widget.onChanged,
    );
  }
}
