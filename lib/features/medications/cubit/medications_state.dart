import "package:equatable/equatable.dart";

import "../models/care_group_medication.dart";

sealed class MedicationsState extends Equatable {
  const MedicationsState();

  @override
  List<Object?> get props => [];
}

final class MedicationsInitial extends MedicationsState {
  const MedicationsInitial();
}

final class MedicationsLoading extends MedicationsState {
  const MedicationsLoading();
}

final class MedicationsEmpty extends MedicationsState {
  const MedicationsEmpty();
}

final class MedicationsDisplay extends MedicationsState {
  const MedicationsDisplay({required this.list});

  final List<CareGroupMedication> list;

  @override
  List<Object?> get props => [list];
}

final class MedicationsFailure extends MedicationsState {
  const MedicationsFailure(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
