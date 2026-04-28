import "package:flutter/material.dart";

import "../../../core/care/role_label.dart";

/// Result from [showInviteEmailRolesDialog].
typedef InviteEmailRolesResult = ({String email, List<String> roles});

/// Invite flow: recipient email plus which [kAssignableCareGroupRoles] they will receive.
Future<InviteEmailRolesResult?> showInviteEmailRolesDialog(BuildContext context) {
  return showDialog<InviteEmailRolesResult>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _InviteEmailRolesDialog(),
  );
}

class _InviteEmailRolesDialog extends StatefulWidget {
  const _InviteEmailRolesDialog();

  @override
  State<_InviteEmailRolesDialog> createState() =>
      _InviteEmailRolesDialogState();
}

class _InviteEmailRolesDialogState extends State<_InviteEmailRolesDialog> {
  final _emailCtl = TextEditingController();
  final _selected = <String>{"carer"};

  @override
  void dispose() {
    _emailCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Invite by email"),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _emailCtl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "Email address",
                  hintText: "name@example.com",
                ),
                autofocus: true,
              ),
              const SizedBox(height: 14),
              Text(
                "Roles for this person",
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                "Choose what they can do after they accept. You can change "
                "this later under People.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              for (final r in kAssignableCareGroupRoles)
                CheckboxListTile(
                  dense: true,
                  value: _selected.contains(r),
                  onChanged: (v) {
                    setState(() {
                      if (v ?? false) {
                        _selected.add(r);
                      } else {
                        _selected.remove(r);
                        if (_selected.isEmpty) {
                          _selected.add("carer");
                        }
                      }
                    });
                  },
                  title: Text(careGroupRoleLabel(r)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        FilledButton(
          onPressed: () {
            final e = _emailCtl.text.trim();
            if (!e.contains("@")) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Enter a valid email address.")),
              );
              return;
            }
            final roles = normalizeAssignableCareGroupRoles(
              _selected.toList(),
            );
            Navigator.of(context).pop(
              (email: e, roles: roles),
            );
          },
          child: const Text("Send invite"),
        ),
      ],
    );
  }
}
