import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter_bloc/flutter_bloc.dart";
import "package:go_router/go_router.dart";
import "package:url_launcher/url_launcher.dart";

import "../../../core/formatting/currency_format.dart";
import "../../../core/theme/app_colors.dart";
import "../../members/models/care_group_member.dart";
import "../../members/repository/members_repository.dart";
import "../../profile/cubit/profile_cubit.dart";
import "../../profile/cubit/profile_state.dart";
import "../cubit/expenses_cubit.dart";
import "../cubit/expenses_state.dart";
import "../models/care_group_expense.dart"
    show CareGroupExpense, ExpenseClaimStatus;
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
  return me.roles.contains("financial_manager");
}

bool _canEditExpenses(CareGroupMember? me) {
  if (me == null) {
    return false;
  }
  return me.roles.contains("principal_carer") ||
      me.roles.contains("financial_manager") ||
      me.roles.contains("care_group_administrator");
}

/// Principal, financial manager, or care group administrator — matches expense review rules.
bool _canReviewExpenseClaims(CareGroupMember? me) => _canEditExpenses(me);

String _memberDisplayName(List<CareGroupMember> members, String uid) {
  for (final m in members) {
    if (m.userId == uid) {
      return m.displayName;
    }
  }
  return "Member";
}

Widget _expenseStatusChip(BuildContext context, CareGroupExpense e) {
  final t = Theme.of(context);
  late final String label;
  late final Color bg;
  late final Color fg;
  switch (e.expenseStatus) {
    case ExpenseClaimStatus.submitted:
      label = "Submitted";
      bg = t.colorScheme.secondaryContainer;
      fg = t.colorScheme.onSecondaryContainer;
      break;
    case ExpenseClaimStatus.rejected:
      label = "Rejected";
      bg = t.colorScheme.errorContainer;
      fg = t.colorScheme.onErrorContainer;
      break;
    case ExpenseClaimStatus.paid:
      label = "Paid";
      bg = t.colorScheme.primaryContainer;
      fg = t.colorScheme.onPrimaryContainer;
      break;
    default:
      label = "Approved";
      bg = t.colorScheme.surfaceContainerHighest;
      fg = t.colorScheme.onSurfaceVariant;
  }
  return Padding(
    padding: const EdgeInsets.only(left: 8),
    child: Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: fg)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      backgroundColor: bg,
      side: BorderSide.none,
    ),
  );
}

String _formatDate(DateTime d) {
  return "${d.day.toString().padLeft(2, "0")}/${d.month.toString().padLeft(2, "0")}/${d.year}";
}

String _permissionHint(String message) {
  if (message.contains("permission-denied") || message.contains("PERMISSION_DENIED")) {
    return "You may not have permission to change expenses. Principal and financial managers can add and edit. "
        "If you cannot create an expense, add reimbursement payment details under Profile & avatar.";
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
              canCreateExpense:
                  state.profile.hasCompleteExpensePaymentDetails,
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
    required this.canCreateExpense,
  });

  final String careGroupId;
  final String myUid;
  final List<CareGroupMember>? members;
  final bool canCreateExpense;

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
              "Expense history is visible to financial managers only. "
              "Ask someone with that role if you need the list or reimbursement updates.",
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
        canReviewClaims: _canReviewExpenseClaims(me),
        canCreateExpense: canCreateExpense,
        members: members!,
      ),
    );
  }
}

class _ExpensesAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ExpensesAppBar({this.actions});

  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text("Expenses"),
      actions: actions,
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

class _ExpensesView extends StatefulWidget {
  const _ExpensesView({
    required this.canEdit,
    required this.canReviewClaims,
    required this.canCreateExpense,
    required this.members,
  });

  final bool canEdit;
  final bool canReviewClaims;
  final bool canCreateExpense;
  final List<CareGroupMember> members;

  @override
  State<_ExpensesView> createState() => _ExpensesViewState();
}

class _ExpensesViewState extends State<_ExpensesView> {
  bool _groupByMember = false;
  bool _paySelectMode = false;
  final Set<String> _selectedForPay = {};

  Future<void> _confirmPayBatch(BuildContext context) async {
    final ids = _selectedForPay.toList();
    if (ids.isEmpty) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Record payment?"),
        content: Text(
          "Mark ${ids.length} approved expense(s) as paid and notify the submitter by email.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Cancel"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Record payment"),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      return;
    }
    try {
      final claimId =
          await context.read<ExpensesCubit>().markExpensesPaid(ids);
      if (!context.mounted) {
        return;
      }
      setState(() {
        _selectedForPay.clear();
        _paySelectMode = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Payment recorded (reference $claimId). An email was sent to the submitter.",
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_permissionHint(e.toString()))),
      );
    }
  }

  Widget _expenseCard(
    BuildContext context,
    CareGroupExpense e, {
    required bool showMemberSubtitle,
  }) {
    final subtitle = <String>[_formatDate(e.spentAt)];
    if (showMemberSubtitle && e.createdBy.isNotEmpty) {
      subtitle.insert(
        0,
        _memberDisplayName(widget.members, e.createdBy),
      );
    }
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
    final selected = _selectedForPay.contains(e.id);
    final paySlot = widget.canReviewClaims &&
        _paySelectMode &&
        e.isApproved;
    final leading = paySlot
        ? Checkbox(
            value: selected,
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _selectedForPay.add(e.id);
                } else {
                  _selectedForPay.remove(e.id);
                }
              });
            },
          )
        : (widget.canReviewClaims && _paySelectMode)
            ? const SizedBox(width: 48)
            : (ru != null && ru.isNotEmpty
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
                  ));

    return Card(
      child: ListTile(
        leading: leading,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(e.title)),
            _expenseStatusChip(context, e),
          ],
        ),
        subtitle: Text(
          subtitle.join(" · "),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          formatCurrencyAmount(e.amount, e.currency),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        isThreeLine: subtitle.length > 1,
        onTap: paySlot
            ? null
            : () => _openExpenseEditor(
                  context,
                  e,
                  canEdit: widget.canEdit,
                  canReviewClaims: widget.canReviewClaims,
                  submitterDisplayName: e.createdBy.isEmpty
                      ? null
                      : _memberDisplayName(widget.members, e.createdBy),
                ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ExpensesState state) {
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
      if (widget.canReviewClaims &&
          widget.members.isNotEmpty &&
          _groupByMember) {
        final byMember = <String, List<CareGroupExpense>>{};
        for (final e in list) {
          final k = e.createdBy.isEmpty ? "_" : e.createdBy;
          byMember.putIfAbsent(k, () => []).add(e);
        }
        for (final entry in byMember.entries) {
          entry.value.sort((a, b) => b.spentAt.compareTo(a.spentAt));
        }
        final keys = byMember.keys.toList()
          ..sort(
            (a, b) => _memberDisplayName(widget.members, a).toLowerCase().compareTo(
                  _memberDisplayName(widget.members, b).toLowerCase(),
                ),
          );
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: keys.length,
          itemBuilder: (context, i) {
            final uid = keys[i];
            final group = byMember[uid]!;
            final name =
                uid == "_" ? "Unknown member" : _memberDisplayName(widget.members, uid);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Theme.of(context).dividerColor),
                ),
                title: Text(name),
                subtitle: Text("${group.length} expense(s)"),
                children: [
                  for (final e in group) ...[
                    _expenseCard(context, e, showMemberSubtitle: false),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            );
          },
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          return _expenseCard(
            context,
            list[i],
            showMemberSubtitle: false,
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
        final canCompose = widget.canEdit &&
            widget.canCreateExpense &&
            (state is ExpensesEmpty || state is ExpensesDisplay) &&
            !_paySelectMode;
        return Scaffold(
          appBar: _ExpensesAppBar(
            actions: widget.canReviewClaims
                ? [
                    IconButton(
                      tooltip: _groupByMember ? "Flat list" : "Group by member",
                      icon: Icon(
                        _groupByMember
                            ? Icons.view_list_outlined
                            : Icons.groups_outlined,
                      ),
                      onPressed: () =>
                          setState(() => _groupByMember = !_groupByMember),
                    ),
                    IconButton(
                      tooltip:
                          _paySelectMode ? "Exit pay selection" : "Select to pay",
                      icon: Icon(
                        _paySelectMode ? Icons.close : Icons.payments_outlined,
                      ),
                      onPressed: () => setState(() {
                        _paySelectMode = !_paySelectMode;
                        if (!_paySelectMode) {
                          _selectedForPay.clear();
                        }
                      }),
                    ),
                  ]
                : null,
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (widget.canEdit && !widget.canCreateExpense)
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 22,
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Add reimbursement payment details",
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Save your bank details under Profile & avatar before you can submit new expenses.",
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onErrorContainer,
                                      ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                  ),
                                  onPressed: () =>
                                      context.push("/user-settings/profile"),
                                  child: const Text("Open profile"),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (widget.canReviewClaims && _paySelectMode)
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Select approved expenses from one submitter and one currency, then record payment.",
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(child: _buildBody(context, state)),
                if (widget.canReviewClaims &&
                    _paySelectMode &&
                    _selectedForPay.isNotEmpty)
                  Material(
                    elevation: 8,
                    color: Theme.of(context).colorScheme.surface,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 12,
                        bottom: MediaQuery.paddingOf(context).bottom + 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              "${_selectedForPay.length} selected",
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(_selectedForPay.clear),
                            child: const Text("Clear"),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _confirmPayBatch(context),
                            child: const Text("Pay"),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          floatingActionButton: canCompose
              ? FloatingActionButton(
                  onPressed: () => _openExpenseEditor(
                    context,
                    null,
                    canEdit: true,
                    canReviewClaims: widget.canReviewClaims,
                    submitterDisplayName: null,
                  ),
                  child: const Icon(Icons.add),
                )
              : null,
        );
      },
    );
  }
}

Future<void> _openExpenseEditor(
  BuildContext context,
  CareGroupExpense? existing, {
  required bool canEdit,
  required bool canReviewClaims,
  String? submitterDisplayName,
}) async {
  final isNew = existing == null;
  final expense = existing;
  final allowEditForm =
      canEdit && (expense == null || expense.canEditCoreFields);
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
                if (!allowEditForm && expense != null) {
                  final ex = expense;
                  return ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(24),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              ex.title,
                              style: Theme.of(ctx).textTheme.titleLarge,
                            ),
                          ),
                          _expenseStatusChip(ctx, ex),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        formatCurrencyAmount(ex.amount, ex.currency),
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text("Date: ${_formatDate(spentAt)}"),
                      if (ex.createdBy.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          submitterDisplayName != null
                              ? "Submitted by: $submitterDisplayName"
                              : "Submitted by: ${ex.createdBy}",
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
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
                      if (ex.isRejected &&
                          ex.rejectionReason != null &&
                          ex.rejectionReason!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          "Rejection reason",
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(ex.rejectionReason!),
                      ],
                      if (ex.isPaid) ...[
                        const SizedBox(height: 12),
                        Text(
                          "Paid",
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        if (ex.paymentClaimId != null &&
                            ex.paymentClaimId!.isNotEmpty)
                          Text("Claim reference: ${ex.paymentClaimId}"),
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
                    if (!isNew && expense != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _expenseStatusChip(ctx, expense),
                      ),
                    ],
                    if (!isNew &&
                        canReviewClaims &&
                        expense != null &&
                        expense.isSubmitted) ...[
                      const SizedBox(height: 16),
                      Material(
                        color:
                            Theme.of(ctx).colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                "Review this claim",
                                style: Theme.of(ctx).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  FilledButton(
                                    onPressed: () async {
                                      try {
                                        await context
                                            .read<ExpensesCubit>()
                                            .approveExpense(expense.id);
                                        if (ctx.mounted) {
                                          Navigator.of(ctx).pop();
                                        }
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                "Expense approved.",
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                _permissionHint(
                                                  e.toString(),
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text("Approve"),
                                  ),
                                  OutlinedButton(
                                    onPressed: () async {
                                      final reasonC =
                                          TextEditingController();
                                      final ok = await showDialog<bool>(
                                        context: ctx,
                                        builder: (dCtx) => AlertDialog(
                                          title: const Text(
                                            "Reject expense",
                                          ),
                                          content: TextField(
                                            controller: reasonC,
                                            decoration: const InputDecoration(
                                              labelText: "Reason",
                                              hintText:
                                                  "Explain why this claim is not approved",
                                              border: OutlineInputBorder(),
                                            ),
                                            maxLines: 4,
                                            autofocus: true,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(dCtx)
                                                      .pop(false),
                                              child: const Text("Cancel"),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.of(dCtx).pop(true),
                                              child: const Text("Reject"),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok != true || !ctx.mounted) {
                                        return;
                                      }
                                      final r = reasonC.text.trim();
                                      if (r.isEmpty) {
                                        return;
                                      }
                                      try {
                                        await context
                                            .read<ExpensesCubit>()
                                            .rejectExpense(
                                              expenseId: expense.id,
                                              rejectionReason: r,
                                            );
                                        if (ctx.mounted) {
                                          Navigator.of(ctx).pop();
                                        }
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                "Expense rejected. The submitter will receive an email.",
                                              ),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                _permissionHint(
                                                  e.toString(),
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    child: const Text("Reject"),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                        if (!isNew && allowEditForm) ...[
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
