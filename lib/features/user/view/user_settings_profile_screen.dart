import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/avatars/avatar_choices.dart";
import "../../../core/theme/app_colors.dart";
import "../../auth/bloc/auth_bloc.dart";
import "../../auth/repository/auth_repository.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../models/user_profile.dart";
import "../repository/user_repository.dart";
import "widgets/care_user_avatar.dart";

class UserSettingsProfileScreen extends StatefulWidget {
  const UserSettingsProfileScreen({super.key});

  @override
  State<UserSettingsProfileScreen> createState() =>
      _UserSettingsProfileScreenState();
}

class _UserSettingsProfileScreenState extends State<UserSettingsProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _saving = false;
  bool _avatarBusy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.read<ProfileCubit>().state;
    if (s is ProfileReady) {
      final n = s.profile.displayName;
      if (_nameController.text != n) {
        _nameController.text = n;
      }
    }
  }

  Future<void> _saveName() async {
    if (_saving) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final t = _nameController.text.trim();
    final authRepo = context.read<AuthRepository>();
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _saving = true);
    try {
      await authRepo.updateDisplayName(t);
      if (!mounted) {
        return;
      }
      await userRepo.updateProfileFields(
        session.uid,
        {"displayName": t},
      );
      if (!mounted) {
        return;
      }
      await profileCubit.refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Display name saved.")),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickAvatar(int oneBased) async {
    if (_avatarBusy) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final userRepo = context.read<UserRepository>();
    final authRepo = context.read<AuthRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _avatarBusy = true);
    try {
      await userRepo.setAvatarPreset(session.uid, oneBased);
      if (!mounted) {
        return;
      }
      await authRepo.updatePhotoUrl(null);
      if (!mounted) {
        return;
      }
      await profileCubit.refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Avatar updated. Your sign-in photo was cleared to show this image.")),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  Future<void> _useAccountPhoto() async {
    if (_avatarBusy) {
      return;
    }
    final session = context.read<AuthBloc>().state.user;
    if (session == null) {
      return;
    }
    final url = session.photoURL?.trim();
    if (url == null || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  "No profile photo is available from your sign-in account.")),
        );
      }
      return;
    }
    final authRepo = context.read<AuthRepository>();
    final userRepo = context.read<UserRepository>();
    final profileCubit = context.read<ProfileCubit>();
    setState(() => _avatarBusy = true);
    try {
      await authRepo.updatePhotoUrl(url);
      if (!mounted) {
        return;
      }
      await userRepo.setProfilePhotoUrl(session.uid, url);
      if (!mounted) {
        return;
      }
      await profileCubit.refresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Using your sign-in account photo in CareShare.")),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _avatarBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, ps) {
        if (ps is! ProfileReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final p = ps.profile;
        final session = context.watch<AuthBloc>().state.user;
        if (session == null) {
          return const Scaffold(body: Center(child: Text("Not signed in.")));
        }
        final authFallback = UserProfile.fromAuthSession(
          uid: session.uid,
          email: session.email ?? "",
          displayName: session.displayName,
          photoUrl: session.photoURL,
        );
        return Scaffold(
          appBar: AppBar(
            title: const Text("Profile & avatar"),
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
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: CareUserAvatar(
                  radius: 48,
                  profile: p,
                  authFallback: authFallback,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Display name",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Form(
                key: _formKey,
                child: TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "How you appear in this home",
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return "Enter a name";
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _saveName,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Save name"),
              ),
              const SizedBox(height: 32),
              Text(
                "Profile picture in CareShare",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (session.photoURL != null &&
                  session.photoURL!.trim().isNotEmpty) ...[
                OutlinedButton.icon(
                  onPressed: _avatarBusy ? null : _useAccountPhoto,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text("Use my sign-in account photo (Google)"),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                "Or choose a preset (shown for you in CareShare, not your Google account):",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.grey500,
                    ),
              ),
              const SizedBox(height: 12),
              if (_avatarBusy)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                )
              else
                Center(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      for (var n = 1; n <= kSetupAvatarCount; n++)
                        InkWell(
                          onTap: () => _pickAvatar(n),
                          borderRadius: BorderRadius.circular(8),
                          child: Material(
                            color: setupAvatarBackground(n),
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: buildSetupAvatarImage(
                                    n,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
