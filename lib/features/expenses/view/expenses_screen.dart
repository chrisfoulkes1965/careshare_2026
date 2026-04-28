import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";
import "package:url_launcher/url_launcher.dart";

import "../../../core/theme/app_colors.dart";
import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../../profile/profile_cubit.dart";
import "../../profile/profile_state.dart";
import "../cubit/expenses_cubit.dart";
import "../cubit/expenses_state.dart";
import "../models/care_group_expense.dart";
import "../repository/expenses_repository.dart";

const _kCategories = <String, String>{
  "general": "General",
  "medical": "Medical",
  "equipment": "Equipment",
  "transport": "Transport",
  "other": "Other",
};

const _kCurrencies = <String>["GBP", "EUR", "USD"];

bool _canViewExpenses(CareGroupMember? me) {
  if (me == null) {
    return false;
  }
  return me.roles.contains("principal_carer") ||
      me.roles.contains("financial_manager") ||
      me.roles.contains("power_of_attorney") ||
      me.roles.contains("care_group_administrator");
}

bool _canEditExpenses(CareGroupMember? me) {
  if (me == null) {
    return false;
  }
  return me.roles.contains("principal_carer") ||
      me.roles.contains("financial_manager") ||
      me.roles.contains("care_group_administrator");
}

String _formatMoney(double amount, String currency) {
  final whole = amount == amount.roundToDouble();
  final a = whole ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2);
  return "$currency $a";
}

String _formatDate(DateTime d) {
  return "${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}";
}

String _permissionHint(String message) {
  if (message.contains("permission-denied") || message.contains("PERMISSION_DENIED")) {
    return "You may not have permission to change expenses. Principal and financial managers can add and edit.";
  }
  return message;
}

double? _parseAmount(String s) {
  final t = s.trim().replaceAll(",", ".");
  if (t.isEmpty) {
    return null;
  }
  return double.tryParse(t);
}

const int _kMaxReceiptBytes = 10 * 1024 * 1024;

Future<void> _openReceiptUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return;
  }
  if (!await canLaunchUrl(uri)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not open the receipt link.")),
      );
    }
    return;
  }
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

bool _isPdfName(String? name) {
  if (name == null) {
    return false;
  }
  return name.toLowerCase().endsWith(".pdf");
}

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is! ProfileReady) {
          return const Scaffold(
            body: Center(child: Text("Loading your profile…")),
          );
        }
        final cg = state.activeCareGroupDataId;
        if (cg == null || cg.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text("Expenses")),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "You need a care group to track expenses. Complete setup first.",
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final membersCg = state.activeCareGroupMemberDocId ?? cg;
        final myUid = state.profile.uid;
        return StreamBuilder<List<CareGroupMember>>(
          stream: context.read<MembersRepository>().watchMembers(membersCg),
          builder: (context, memSnap) {
            return _ExpensesGate(
              careGroupId: cg,
              myUid: myUid,
              members: memSnap.data,
            );
          },
        );
      },
    );
  }
}

class _ExpensesGate extends StatelessWidget {
  const _ExpensesGate({
    required this.careGroupId,
    required this.myUid,
    required this.members,
  });

  final String careGroupId;
  final String myUid;
  final List<CareGroupMember>? members;

  @override
  Widget build(BuildContext context) {
    if (members == null) {
      return const Scaffold(
        appBar: _ExpensesAppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    CareGroupMember? me;
    for (final m in members!) {
      if (m.userId == myUid) {
        me = m;
        break;
      }
    }
    if (!_canViewExpenses(me)) {
      return const Scaffold(
        appBar: _ExpensesAppBar(),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              "Expense history is visible to principal carers, financial managers, and those with power of attorney. "
              "Ask a principal carer if you need access.",
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return BlocProvider(
      key: ObjectKey(careGroupId),
      create: (context) => ExpensesCubit(
        repository: context.read<ExpensesRepository>(),
        careGroupId: careGroupId,
      )..subscribe(),
      child: _ExpensesView(
        canEdit: _canEditExpenses(me),
      ),
    );
  }
}

class _ExpensesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ExpensesAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text("Expenses"),
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
    );
  }
}

class _ExpensesView extends StatelessWidget {
  const _ExpensesView({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ExpensesCubit, ExpensesState>(
      listenWhen: (p, c) => c is ExpensesFailure,
      listener: (context, state) {
        if (state is ExpensesFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_permissionHint(state.message))),
          );
        }
      },
      builder: (context, state) {
        final canCompose = canEdit && (state is ExpensesEmpty || state is ExpensesDisplay);
        return Scaffold(
          appBar: const _ExpensesAppBar(),
          body: SafeArea(
            child: _ExpensesBody(state: state, canEdit: canEdit),
          ),
          floatingActionButton: canCompose
              ? FloatingActionButton(
                  onPressed: () => _openExpenseEditor(context, null, canEdit: true),
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }
}

class _ExpensesBody extends StatelessWidget {
  const _ExpensesBody({required this.state, required this.canEdit});

  final ExpensesState state;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    if (state is ExpensesInitial || state is ExpensesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is ExpensesEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "No expenses recorded yet. "
            "Add purchases, care-related costs, or equipment here so the team has a clear picture.",
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (state case final ExpensesDisplay display) {
      final list = display.list;
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final e = list[i];
          final subtitle = <String>[_formatDate(e.spentAt)];
          if (e.category != null && e.category!.isNotEmpty) {
            final c = e.category!.toLowerCase();
            final label = _kCategories[c] ?? e.category;
            if (label != null && label.isNotEmpty) {
              subtitle.add(label);
            }
          }
          if (e.payee != null && e.payee!.isNotEmpty) {
            subtitle.add(e.payee!);
          }
          if (e.notes != null && e.notes!.isNotEmpty) {
            var n = e.notes!;
            if (n.length > 64) {
              n = "${n.substring(0, 64)}…";
            }
            subtitle.add(n);
          }
          final ru = e.receiptUrl?.trim();
          return Card(
            child: ListTile(
              leading: ru != null && ru.isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        ru,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const CircleAvatar(
                          backgroundColor: AppColors.tealLight,
                          child: Icon(
                            Icons.receipt_long_outlined,
                            color: AppColors.tealPrimary,
                          ),
                        ),
                      ),
                    )
                  : const CircleAvatar(
                      backgroundColor: AppColors.tealLight,
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: AppColors.tealPrimary,
                      ),
                    ),
              title: Text(e.title),
              subtitle: Text(
                subtitle.join(" · "),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                _formatMoney(e.amount, e.currency),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              isThreeLine: subtitle.length > 1,
              onTap: () => _openExpenseEditor(
                context,
                e,
                canEdit: canEdit,
              ),
            ),
          );
        },
      );
    }
    if (state case final ExpensesFailure failure) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _permissionHint(failure.message),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

Future<void> _openExpenseEditor(
  BuildContext context,
  CareGroupExpense? existing, {
  required bool canEdit,
}) async {
  final isNew = existing == null;
  final expense = existing;
  final titleC = TextEditingController(text: expense?.title ?? "");
  final amountC = TextEditingController(
    text: expense != null
        ? (expense.amount == expense.amount.roundToDouble()
            ? expense.amount.toStringAsFixed(0)
            : expense.amount.toStringAsFixed(2))
        : "",
  );
  var currency = expense?.currency ?? "GBP";
  if (!_kCurrencies.contains(currency)) {
    currency = "GBP";
  }
  var spentAt = expense?.spentAt ?? DateTime.now();
  var categoryKey = expense?.category?.toLowerCase();
  if (categoryKey != null &&
      categoryKey.isNotEmpty &&
      !_kCategories.containsKey(categoryKey)) {
    categoryKey = null;
  }
  final payeeC = TextEditingController(text: expense?.payee ?? "");
  final notesC = TextEditingController(text: expense?.notes ?? "");

  if (!context.mounted) {
    return;
  }
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
          minChildSize: 0.45,
          maxChildSize: 0.95,
          initialChildSize: 0.75,
          builder: (ctx, scroll) {
            PlatformFile? pendingReceipt;
            var removeReceipt = false;
            final initialReceiptUrl = expense?.receiptUrl?.trim();
            return StatefulBuilder(
              builder: (ctx, setModal) {
                if (!canEdit) {
                  final ex = expense;
                  if (ex == null) {
                    return const SizedBox.shrink();
                  }
                  return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        ex.title,
                        style: Theme.of(ctx).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatMoney(ex.amount, ex.currency),
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text("Date: ${_formatDate(spentAt)}"),
                      if (ex.category != null && ex.category!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          "Category: ${_kCategories[ex.category!.toLowerCase()] ?? ex.category}",
                        ),
                      ],
                      if (ex.payee != null && ex.payee!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text("Payee: ${ex.payee}"),
                      ],
                      if (ex.notes != null && ex.notes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text("Notes", style: Theme.of(ctx).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(ex.notes!),
                      ],
                      if (ex.receiptUrl != null && ex.receiptUrl!.trim().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text("Receipt", style: Theme.of(ctx).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => _openReceiptUrl(ctx, ex.receiptUrl!.trim()),
                          icon: const Icon(Icons.open_in_new_outlined),
                          label: const Text("View receipt"),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text("Close"),
                        ),
                      ),
                    ],
                  );
                }
                return ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      isNew ? "New expense" : "Edit expense",
                      style: Theme.of(ctx).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: "Title",
                        hintText: "e.g. mobility scooter repair",
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: amountC,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: "Amount",
                            ),
                            onChanged: (_) => setModal(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: "Currency",
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: currency,
                                isExpanded: true,
                                items: _kCurrencies
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(c),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setModal(() {
                                      currency = v;
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("Date spent"),
                      subtitle: Text(_formatDate(spentAt)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: spentAt,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setModal(() {
                            spentAt = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                            );
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 4),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: "Category (optional)",
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: categoryKey,
                          isExpanded: true,
                          hint: const Text("None"),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text("None"),
                            ),
                            ..._kCategories.keys.map(
                              (k) => DropdownMenuItem(
                                value: k,
                                child: Text(_kCategories[k]!),
                              ),
                            ),
                          ],
                          onChanged: (v) => setModal(() {
                            categoryKey = v;
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: payeeC,
                      decoration: const InputDecoration(
                        labelText: "Payee (optional)",
                        hintText: "Shop, clinic, or person",
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesC,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: "Notes (optional)",
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Receipt (optional)",
                      style: Theme.of(ctx).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    if (pendingReceipt != null) ...[
                      () {
                        final f = pendingReceipt!;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_isPdfName(f.name))
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.tealLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.picture_as_pdf_outlined,
                                  size: 32,
                                  color: AppColors.tealPrimary,
                                ),
                              )
                            else if (f.bytes != null && f.bytes!.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  f.bytes!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.tealLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.insert_drive_file_outlined,
                                  color: AppColors.tealPrimary,
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                f.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            TextButton(
                              onPressed: () => setModal(() {
                                pendingReceipt = null;
                              }),
                              child: const Text("Clear"),
                            ),
                          ],
                        );
                      }(),
                    ] else if (!removeReceipt &&
                        initialReceiptUrl != null &&
                        initialReceiptUrl.isNotEmpty) ...[
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              initialReceiptUrl,
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.tealLight,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.insert_drive_file_outlined,
                                  color: AppColors.tealPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: () =>
                                _openReceiptUrl(ctx, initialReceiptUrl),
                            child: const Text("View"),
                          ),
                          TextButton(
                            onPressed: () => setModal(() {
                              removeReceipt = true;
                            }),
                            child: const Text("Remove"),
                          ),
                          TextButton(
                            onPressed: () async {
                              final r = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: const [
                                  "jpg",
                                  "jpeg",
                                  "png",
                                  "webp",
                                  "heic",
                                  "pdf",
                                ],
                                withData: true,
                              );
                              if (r == null || r.files.isEmpty) {
                                return;
                              }
                              final f = r.files.first;
                              if (f.size > _kMaxReceiptBytes) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Receipt must be 10 MB or smaller."),
                                    ),
                                  );
                                }
                                return;
                              }
                              if (f.bytes == null || f.bytes!.isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Could not read the file. Try again."),
                                    ),
                                  );
                                }
                                return;
                              }
                              setModal(() {
                                pendingReceipt = f;
                                removeReceipt = false;
                              });
                            },
                            child: const Text("Replace"),
                          ),
                        ],
                      ),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: () async {
                          final r = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: const [
                              "jpg",
                              "jpeg",
                              "png",
                              "webp",
                              "heic",
                              "pdf",
                            ],
                            withData: true,
                          );
                          if (r == null || r.files.isEmpty) {
                            return;
                          }
                          final f = r.files.first;
                          if (f.size > _kMaxReceiptBytes) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Receipt must be 10 MB or smaller."),
                                ),
                              );
                            }
                            return;
                          }
                          if (f.bytes == null || f.bytes!.isEmpty) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Could not read the file. Try again."),
                                ),
                              );
                            }
                            return;
                          }
                          setModal(() {
                            pendingReceipt = f;
                            removeReceipt = false;
                          });
                        },
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text("Attach receipt"),
                      ),
                    ],
                    if (removeReceipt &&
                        initialReceiptUrl != null &&
                        initialReceiptUrl.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        "Current receipt will be removed when you save.",
                        style: TextStyle(
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        if (!isNew) ...[
                          TextButton(
                            onPressed: () async {
                              final go = await showDialog<bool>(
                                context: ctx,
                                builder: (d) => AlertDialog(
                                  title: const Text("Delete expense?"),
                                  content: const Text(
                                    "This cannot be undone. You need principal or financial manager access in your security rules.",
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
                                  await context
                                      .read<ExpensesCubit>()
                                      .deleteExpense(expense!.id);
                                  if (ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _permissionHint(e.toString()),
                                        ),
                                      ),
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
                            if (titleC.text.trim().isEmpty) {
                              return;
                            }
                            final am = _parseAmount(amountC.text);
                            if (am == null || am <= 0) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Enter a valid amount greater than zero."),
                                  ),
                                );
                              }
                              return;
                            }
                            final cubit = context.read<ExpensesCubit>();
                            try {
                              if (isNew) {
                                await cubit.addExpense(
                                  title: titleC.text,
                                  amount: am,
                                  currency: currency,
                                  spentAt: spentAt,
                                  category: categoryKey,
                                  payee: payeeC.text,
                                  notes: notesC.text,
                                  receipt: pendingReceipt,
                                );
                              } else {
                                await cubit.updateExpense(
                                  expenseId: expense!.id,
                                  title: titleC.text,
                                  amount: am,
                                  currency: currency,
                                  spentAt: spentAt,
                                  category: categoryKey,
                                  payee: payeeC.text,
                                  notes: notesC.text,
                                  receipt: pendingReceipt,
                                  removeReceipt: removeReceipt,
                                  previousReceiptUrl: initialReceiptUrl,
                                );
                              }
                              if (ctx.mounted) {
                                Navigator.of(ctx).pop();
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(_permissionHint(e.toString())),
                                  ),
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
            );
          },
        ),
      );
    },
  );
}
