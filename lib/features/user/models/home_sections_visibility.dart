import "package:equatable/equatable.dart";

/// Stable ids for persisted homepage blocks (Firestore + reorder UI).
/// Add new sections here first, then wiring in [HomeSectionsVisibility].
abstract final class HomeSectionId {
  static const todaysNeeds = "todaysNeeds";
  static const calendarEvents = "calendarEvents";
  static const tasks = "tasks";
  static const medications = "medications";
  static const expenses = "expenses";
  static const urgentTasks = "urgentTasks";
  static const recentActivity = "recentActivity";

  static const List<String> canonicalOrder = [
    todaysNeeds,
    calendarEvents,
    tasks,
    medications,
    expenses,
    urgentTasks,
    recentActivity,
  ];

  static const Set<String> allIds = {
    todaysNeeds,
    calendarEvents,
    tasks,
    medications,
    expenses,
    urgentTasks,
    recentActivity,
  };
}

/// Controls which blocks appear on the care group home landing page and in what order.
/// Stored under `users/{uid}.homeSections` in Firestore. Omitted bool keys mean “show”.
final class HomeSectionsVisibility extends Equatable {
  const HomeSectionsVisibility({
    this.todaysNeeds = true,
    this.calendarEvents = true,
    this.tasks = true,
    this.medications = true,
    this.expenses = true,
    this.urgentTasks = true,
    this.recentActivity = true,
    this.sectionOrder,
  });

  /// “Today’s needs” member row.
  final bool todaysNeeds;

  /// Linked calendar + team meetings on the home strip.
  final bool calendarEvents;

  /// Upcoming tasks strip.
  final bool tasks;

  /// Medication reminder strip.
  final bool medications;

  /// Expense preview strip.
  final bool expenses;

  /// “Urgent tasks” list.
  final bool urgentTasks;

  /// Notes / journal / task activity.
  final bool recentActivity;

  /// User preferred vertical order. When null/empty, [resolvedSectionOrder] uses
  /// [HomeSectionId.canonicalOrder].
  final List<String>? sectionOrder;

  bool isSectionVisible(String id) {
    switch (id) {
      case HomeSectionId.todaysNeeds:
        return todaysNeeds;
      case HomeSectionId.calendarEvents:
        return calendarEvents;
      case HomeSectionId.tasks:
        return tasks;
      case HomeSectionId.medications:
        return medications;
      case HomeSectionId.expenses:
        return expenses;
      case HomeSectionId.urgentTasks:
        return urgentTasks;
      case HomeSectionId.recentActivity:
        return recentActivity;
      default:
        return true;
    }
  }

  /// Normalized top-to-bottom order for the home page.
  List<String> get resolvedSectionOrder =>
      normalizeSectionOrderList(sectionOrder);

  static List<String> normalizeSectionOrderList(List<String>? stored) {
    final base = List<String>.from(HomeSectionId.canonicalOrder);
    if (stored == null || stored.isEmpty) {
      return base;
    }
    final seen = <String>{};
    final out = <String>[];
    for (final id in stored) {
      if (HomeSectionId.allIds.contains(id) && seen.add(id)) {
        out.add(id);
      }
    }
    for (final id in base) {
      if (!seen.contains(id)) {
        out.add(id);
      }
    }
    return out;
  }

  static HomeSectionsVisibility fromFirestoreMap(Object? raw) {
    if (raw == null || raw is! Map) {
      return const HomeSectionsVisibility();
    }
    final m = Map<String, dynamic>.from(raw);
    bool getB(String k) {
      final v = m[k];
      if (v is bool) {
        return v;
      }
      return true;
    }

    bool readBool({required String k, required String fallback}) {
      if (m.containsKey(k)) {
        return getB(k);
      }
      return getB(fallback);
    }

    final calendarEvents = readBool(k: _kCalendarEvents, fallback: _kComingUp);
    final tasksVis = readBool(k: _kTasks, fallback: _kTasksStrip);
    final medicationsVis = readBool(k: _kMedications, fallback: _kMedsStrip);
    final expensesVis = readBool(k: _kExpenses, fallback: _kExpensesStrip);

    List<String>? order;
    final rawOrder = m[_kSectionOrder];
    if (rawOrder is List) {
      order = rawOrder.map((e) => e.toString()).toList();
    }

    return HomeSectionsVisibility(
      todaysNeeds: getB(_kTodaysNeeds),
      calendarEvents: calendarEvents,
      tasks: tasksVis,
      medications: medicationsVis,
      expenses: expensesVis,
      urgentTasks: getB(_kUrgentTasks),
      recentActivity: getB(_kRecentActivity),
      sectionOrder: order,
    );
  }

  Map<String, dynamic> toFirestoreUpdate() {
    return {
      _kTodaysNeeds: todaysNeeds,
      _kCalendarEvents: calendarEvents,
      _kTasks: tasks,
      _kMedications: medications,
      _kExpenses: expenses,
      _kUrgentTasks: urgentTasks,
      _kRecentActivity: recentActivity,
      _kSectionOrder: resolvedSectionOrder,
    };
  }

  HomeSectionsVisibility copyWith({
    bool? todaysNeeds,
    bool? calendarEvents,
    bool? tasks,
    bool? medications,
    bool? expenses,
    bool? urgentTasks,
    bool? recentActivity,
    List<String>? sectionOrder,
  }) {
    return HomeSectionsVisibility(
      todaysNeeds: todaysNeeds ?? this.todaysNeeds,
      calendarEvents: calendarEvents ?? this.calendarEvents,
      tasks: tasks ?? this.tasks,
      medications: medications ?? this.medications,
      expenses: expenses ?? this.expenses,
      urgentTasks: urgentTasks ?? this.urgentTasks,
      recentActivity: recentActivity ?? this.recentActivity,
      sectionOrder: sectionOrder ?? this.sectionOrder,
    );
  }

  @override
  List<Object?> get props => [
        todaysNeeds,
        calendarEvents,
        tasks,
        medications,
        expenses,
        urgentTasks,
        recentActivity,
        sectionOrder,
      ];
}

const String _kTodaysNeeds = "todaysNeeds";
const String _kComingUp = "comingUp";
const String _kCalendarEvents = "calendarEvents";
const String _kTasksStrip = "tasksStrip";
const String _kTasks = "tasks";
const String _kMedsStrip = "medicationsStrip";
const String _kMedications = "medications";
const String _kExpensesStrip = "expensesStrip";
const String _kExpenses = "expenses";
const String _kUrgentTasks = "urgentTasks";
const String _kRecentActivity = "recentActivity";
const String _kSectionOrder = "sectionOrder";
