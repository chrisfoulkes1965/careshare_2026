import "dart:async" show unawaited;

import "package:firebase_core/firebase_core.dart" show FirebaseException;
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../../core/avatars/avatar_choices.dart";
import "../../../core/constants/app_constants.dart";
import "../../../core/invite/invitation_landing_preview.dart";
import "../../../core/theme/app_assets.dart";
import "../../../core/theme/app_colors.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";

/// Shown after signing in from an email invitation, before home: name + preset avatar.
class InviteProfileScreen extends StatefulWidget {
  const InviteProfileScreen({super.key});

  @override
  State<InviteProfileScreen> createState() => _InviteProfileScreenState();
}

class _InviteProfileScreenState extends State<InviteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int _avatarIndex = 1;
  InvitationLandingPreview? _preview;
  bool _loadingPreview = true;

  @override
  void initState() {
    super.initState();
    final pr = context.read<ProfileCubit>().state;
    if (pr is ProfileReady) {
      _nameController.text = pr.profile.displayName.trim();
      final ai = pr.profile.avatarIndex;
      if (ai != null && ai >= 1) {
        _avatarIndex = ai;
      }
    }
    final id = switch (pr) {
      ProfileReady(:final pendingInvitationId) => pendingInvitationId,
      _ => null,
    };
    if (id != null && id.isNotEmpty) {
      unawaited(_loadPreview(id));
    } else {
      setState(() => _loadingPreview = false);
    }
  }

  Future<void> _loadPreview(String invitationId) async {
    final p = await InvitationLandingPreview.load(invitationId);
    if (!mounted) {
      return;
    }
    setState(() {
      _preview = p;
      _loadingPreview = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    try {
      await context.read<ProfileCubit>().completeInvitationProfile(
            displayName: _nameController.text,
            avatarIndex: _avatarIndex,
          );
    } catch (e) {
      if (!mounted) return;
      final msg = e is StateError
          ? e.message
          : (e is FirebaseException
              ? (e.message ?? e.code)
              : e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Welcome to the care team"),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      AppAssets.logo75,
                      height: 72,
                      filterQuality: FilterQuality.medium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppConstants.appName,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: AppColors.tealPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Tell the team how your name should appear, and pick an avatar.",
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.grey500,
                          ),
                    ),
                    if (_loadingPreview) ...[
                      const SizedBox(height: 24),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    if (!_loadingPreview && _preview != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        "${_preview!.inviterLabel} invited you to ${_preview!.careGroupLabel}.",
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: "Your name",
                        hintText: "Name shown to the care team",
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return "Enter your name";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Choose an avatar",
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 260,
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                        ),
                        itemCount: kSetupAvatarCount,
                        itemBuilder: (context, index) {
                          final n = index + 1;
                          final selected = _avatarIndex == n;
                          final path = setupAvatarAssetPath(n);
                          return InkWell(
                            onTap: () => setState(() => _avatarIndex = n),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.tealPrimary
                                      : AppColors.grey200,
                                  width: selected ? 3 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ColoredBox(color: setupAvatarBackground(n)),
                                    Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: path == null
                                          ? const Icon(Icons.pets, size: 32)
                                          : Image.asset(
                                              path,
                                              fit: BoxFit.contain,
                                              errorBuilder:
                                                  (_, __, ___) => const Icon(
                                                Icons.pets,
                                                size: 32,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
                    BlocConsumer<ProfileCubit, ProfileState>(
                      listenWhen: (p, c) => p != c,
                      listener: (context, state) {
                        if (state is ProfileError &&
                            context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(state.message)),
                          );
                        }
                      },
                      builder: (context, state) {
                        final busy = state is ProfileLoading;
                        return FilledButton(
                          onPressed: busy ? null : _submit,
                          child: busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text("Accept invitation and continue"),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
