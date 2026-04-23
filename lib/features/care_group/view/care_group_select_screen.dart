import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";

import "../../../core/theme/app_colors.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../models/care_group_option.dart";

/// Shown when [ProfileReady.requiresCareGroupSelection] is true, or from home
/// with `?picker=1` to switch the active care group.
class CareGroupSelectScreen extends StatelessWidget {
  const CareGroupSelectScreen({super.key, this.pickerMode = false});

  /// `true` when opened from the home "Switch care group" action (user may
  /// already have a valid [UserProfile.activeHouseholdId]).
  final bool pickerMode;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final options = state.careGroupOptions;
        if (options.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Choose a care group")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "No care groups were found for your account. Complete setup, or check that you have accepted an invite.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return _CareGroupList(
          options: options,
          pickerMode: pickerMode,
        );
      },
    );
  }
}

class _CareGroupList extends StatefulWidget {
  const _CareGroupList({
    required this.options,
    required this.pickerMode,
  });

  final List<CareGroupOption> options;
  final bool pickerMode;

  @override
  State<_CareGroupList> createState() => _CareGroupListState();
}

class _CareGroupListState extends State<_CareGroupList> {
  bool _saving = false;
  String? _error;

  Future<void> _select(CareGroupOption o) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<ProfileCubit>().selectActiveCareGroup(o);
      if (!mounted) return;
      if (context.canPop() && widget.pickerMode) {
        context.pop();
      } else {
        context.go("/home");
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not set care group: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: widget.pickerMode,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Choose a care group"),
          leading: widget.pickerMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _saving ? null : () => context.pop(),
                )
              : null,
          automaticallyImplyLeading: !widget.pickerMode,
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.pickerMode
                      ? "Select which care group to use. You can open this list again from the dashboard."
                      : "You are part of more than one care group. Choose which one to open. You can change this later from the dashboard.",
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                ...widget.options.map(
                  (o) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.home_work_outlined,
                          color: AppColors.tealPrimary,
                        ),
                        title: Text(o.displayName),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _saving ? null : () => _select(o),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_saving) const ColoredBox(
              color: Color(0x33FFFFFF),
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
        bottomNavigationBar: _error == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ),
      ),
    );
  }
}
