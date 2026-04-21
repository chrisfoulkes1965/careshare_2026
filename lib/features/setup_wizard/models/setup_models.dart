import "package:equatable/equatable.dart";

enum RecipientAccessMode { managed, limitedApp }

final class RecipientDraft extends Equatable {
  const RecipientDraft({
    required this.id,
    required this.displayName,
    required this.accessMode,
  });

  final String id;
  final String displayName;
  final RecipientAccessMode accessMode;

  Map<String, dynamic> toMap() {
    return {
      "id": id,
      "displayName": displayName,
      "accessMode": accessMode.name,
    };
  }

  static RecipientDraft fromMap(Map<String, dynamic> map) {
    return RecipientDraft(
      id: map["id"] as String,
      displayName: map["displayName"] as String,
      accessMode: RecipientAccessMode.values.firstWhere(
        (e) => e.name == map["accessMode"],
        orElse: () => RecipientAccessMode.managed,
      ),
    );
  }

  @override
  List<Object?> get props => [id, displayName, accessMode];
}

final class CarePathwayOption extends Equatable {
  const CarePathwayOption({
    required this.id,
    required this.title,
    required this.description,
  });

  final String id;
  final String title;
  final String description;

  @override
  List<Object?> get props => [id, title, description];
}

final class SetupPathways {
  static const List<CarePathwayOption> all = [
    CarePathwayOption(
      id: "elderly_care",
      title: "Elderly care",
      description: "General support for an older adult — personal care, appointments, household tasks.",
    ),
    CarePathwayOption(
      id: "dementia_care",
      title: "Dementia care",
      description: "Structured routine support, medication tracking, safety alerts, cognitive activity suggestions.",
    ),
    CarePathwayOption(
      id: "short_term_medical",
      title: "Short-term medical",
      description: "Post-surgery or illness recovery — appointments, medication, physio, wound care.",
    ),
    CarePathwayOption(
      id: "mental_health",
      title: "Mental health",
      description: "Gentle structure, wellbeing check-ins, low-pressure task lists, carer wellbeing emphasis.",
    ),
    CarePathwayOption(
      id: "physical_disability",
      title: "Physical disability",
      description: "Mobility, accessibility needs, equipment management, personal care rota.",
    ),
    CarePathwayOption(
      id: "palliative_care",
      title: "Palliative care",
      description: "Comfort-focused. Reduced task emphasis, journaling, family communication.",
    ),
    CarePathwayOption(
      id: "child_young_person",
      title: "Child / young person",
      description: "Adapted for supporting a child with additional needs.",
    ),
    CarePathwayOption(
      id: "unemployment_crisis",
      title: "Unemployment / crisis",
      description: "Financial management, job search support tasks, wellbeing check-ins.",
    ),
  ];
}

String newRecipientId() => "rcp_${DateTime.now().microsecondsSinceEpoch}";
