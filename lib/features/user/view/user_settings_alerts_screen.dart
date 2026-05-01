import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";

import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../models/user_alert_preferences.dart";

class UserSettingsAlertsScreen extends StatefulWidget {
  const UserSettingsAlertsScreen({super.key});

  @override
  State<UserSettingsAlertsScreen> createState() => _UserSettingsAlertsScreenState();
}

class _UserSettingsAlertsScreenState extends State<UserSettingsAlertsScreen> {
  UserAlertPreferences? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final base = state.profile.resolvedAlertPreferences;
        _draft ??= base;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Alerts & channels"),
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                "Choose how you want to be reached for each kind of reminder. "
                "Some channels are not fully wired yet — your choices are saved for when they are.",
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Text(
                "Medication reorder",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                "When supply is within the “days before stockout” window you set for this care group "
                "(Prescriptions → inventory icon), CareShare can remind you to restock.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              _channelTile(
                context,
                title: "In-app",
                subtitle: "Banner on home and prompts on the medications screen",
                value: _draft!.medicationReorder.inApp,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationReorder:
                                _draft!.medicationReorder.copyWith(inApp: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "App push notification",
                subtitle: "This device when the app can receive push (not web)",
                value: _draft!.medicationReorder.pushApp,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationReorder:
                                _draft!.medicationReorder.copyWith(pushApp: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "Email",
                subtitle: "Uses your account email when delivery is enabled",
                value: _draft!.medicationReorder.email,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationReorder:
                                _draft!.medicationReorder.copyWith(email: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "SMS",
                subtitle: "Coming soon — preference is saved for later",
                value: _draft!.medicationReorder.sms,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationReorder:
                                _draft!.medicationReorder.copyWith(sms: v),
                          );
                        }),
              ),
              const SizedBox(height: 24),
              Text(
                "Medication due",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                "Scheduled dose reminders on this device, and optional push mirrors if your backend sends them.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              _channelTile(
                context,
                title: "In-app",
                subtitle: "Banners and navigation to confirm doses while using the app",
                value: _draft!.medicationDue.inApp,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationDue: _draft!.medicationDue.copyWith(inApp: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "App push notification",
                subtitle: "Mirror FCM medication messages in the foreground on this device",
                value: _draft!.medicationDue.pushApp,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationDue: _draft!.medicationDue.copyWith(pushApp: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "Email",
                subtitle: "When server-side email delivery is enabled",
                value: _draft!.medicationDue.email,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationDue: _draft!.medicationDue.copyWith(email: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "SMS",
                subtitle: "Coming soon — preference is saved for later",
                value: _draft!.medicationDue.sms,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationDue: _draft!.medicationDue.copyWith(sms: v),
                          );
                        }),
              ),
              const SizedBox(height: 24),
              Text(
                "Medication — missed confirmation",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                "If a scheduled dose is not confirmed in time, principal carers, POA, and group admins can be alerted.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              _channelTile(
                context,
                title: "In-app",
                subtitle:
                    "When wired: in-app summary for missed confirmations. Home prompts use “Medication due” above.",
                value: _draft!.medicationMissed.inApp,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationMissed:
                                _draft!.medicationMissed.copyWith(inApp: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "App push notification",
                subtitle: "When the backend detects a missed confirmation",
                value: _draft!.medicationMissed.pushApp,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationMissed:
                                _draft!.medicationMissed.copyWith(pushApp: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "Email",
                subtitle: "When server-side email delivery is enabled",
                value: _draft!.medicationMissed.email,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationMissed:
                                _draft!.medicationMissed.copyWith(email: v),
                          );
                        }),
              ),
              _channelTile(
                context,
                title: "SMS",
                subtitle: "Coming soon — preference is saved for later",
                value: _draft!.medicationMissed.sms,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _draft = _draft!.copyWith(
                            medicationMissed:
                                _draft!.medicationMissed.copyWith(sms: v),
                          );
                        }),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving || _draft == base
                    ? null
                    : () async {
                        setState(() => _saving = true);
                        try {
                          await context.read<ProfileCubit>().setAlertPreferences(_draft!);
                          if (context.mounted) {
                            setState(() {
                              _saving = false;
                              _draft = null;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Alert preferences saved.")),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setState(() => _saving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(e.toString())),
                            );
                          }
                        }
                      },
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Save"),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _channelTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title),
      subtitle: Text(subtitle),
      contentPadding: EdgeInsets.zero,
    );
  }
}
