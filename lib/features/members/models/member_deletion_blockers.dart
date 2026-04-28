/// Result of checking whether a roster entry can be removed from this home.
final class MemberDeletionBlockers {
  const MemberDeletionBlockers({
    this.hasTaskAssignment = false,
    this.hasAuthoredNote = false,
    this.hasAuthoredJournal = false,
    this.isInChatChannel = false,
    this.hasExpenses = false,
  });

  final bool hasTaskAssignment;
  final bool hasAuthoredNote;
  final bool hasAuthoredJournal;
  final bool isInChatChannel;
  final bool hasExpenses;

  bool get canDelete => !hasTaskAssignment &&
      !hasAuthoredNote &&
      !hasAuthoredJournal &&
      !isInChatChannel &&
      !hasExpenses;

  /// One sentence for SnackBar / dialog when [canDelete] is false.
  String? get reasonIfBlocked {
    if (canDelete) {
      return null;
    }
    final parts = <String>[];
    if (hasTaskAssignment) {
      parts.add("assigned to a task in this home");
    }
    if (hasAuthoredNote) {
      parts.add("listed as the author of a note");
    }
    if (hasAuthoredJournal) {
      parts.add("listed as the author of a journal entry");
    }
    if (isInChatChannel) {
      parts.add("in a care team chat channel");
    }
    if (hasExpenses) {
      parts.add("recorded on an expense in this home");
    }
    if (parts.isEmpty) {
      return "This person is still linked to data in this home.";
    }
    if (parts.length == 1) {
      return "They are still ${parts.first}. Reassign, remove, or leave those first.";
    }
    return "They are still ${parts.join(", ")}. Reassign, remove, or leave those first.";
  }
}
