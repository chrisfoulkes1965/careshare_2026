import "package:equatable/equatable.dart";

import "alternate_email.dart";
import "alternate_phone.dart";
import "home_sections_visibility.dart";
import "expense_payment_details.dart";
import "postal_address.dart";
import "user_alert_preferences.dart";

final class UserProfile extends Equatable {
  /// Builds a lightweight profile from Firebase Auth-style session fields
  /// (`AuthBloc.state.user` getters) — no `firebase_auth` import required at call sites.
  factory UserProfile.fromAuthSession({
    required String uid,
    required String email,
    String? displayName,
    String? photoUrl,
  }) {
    final dn = displayName?.trim() ?? "";
    return UserProfile(
      uid: uid,
      email: email,
      displayName: dn,
      photoUrl: photoUrl,
    );
  }

  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.fullName,
    this.phone,
    this.address,
    this.alternateEmails = const [],
    this.alternatePhones = const [],
    this.photoUrl,
    this.avatarIndex,
    this.simpleMode = false,
    this.wizardCompleted = false,
    this.wizardSkipped = false,
    this.activeCareGroupId,
    this.wizardDraft,
    this.homeSections,
    this.alertPreferences,
    this.expensePaymentDetails,
  });

  final String uid;
  final String email;

  /// Short display name shown in chat / members lists; this is the display name
  /// that already existed before the profile expansion.
  final String displayName;

  /// Optional legal full name (e.g. "Christopher Foulkes"). Distinct from
  /// [displayName] which may be a nickname.
  final String? fullName;

  /// Primary phone number (the user's main mobile / contact number).
  final String? phone;

  /// Optional postal address.
  final PostalAddress? address;

  /// Additional email addresses owned by the user (verified via Resend link).
  final List<AlternateEmail> alternateEmails;

  /// Additional phone numbers (SMS verification not yet wired — flagged
  /// unverified, possibly tagged non-mobile if the user opted to skip).
  final List<AlternatePhone> alternatePhones;

  final String? photoUrl;
  final int? avatarIndex;
  final bool simpleMode;
  final bool wizardCompleted;
  final bool wizardSkipped;
  final String? activeCareGroupId;
  final Map<String, dynamic>? wizardDraft;

  /// When absent, treat as “show all” sections on the home landing page.
  final HomeSectionsVisibility? homeSections;

  /// Optional overrides for alert delivery (email, in-app, push, SMS).
  final UserAlertPreferences? alertPreferences;

  /// Where payers should send reimbursement (bank details). Required before submitting expenses.
  final ExpensePaymentDetails? expensePaymentDetails;

  bool get needsWizard => !wizardCompleted && !wizardSkipped;

  bool get hasCompleteExpensePaymentDetails =>
      expensePaymentDetails?.isComplete ?? false;

  HomeSectionsVisibility get resolvedHomeSections =>
      homeSections ?? const HomeSectionsVisibility();

  UserAlertPreferences get resolvedAlertPreferences =>
      alertPreferences ?? const UserAlertPreferences();

  UserProfile copyWith({
    String? displayName,
    String? fullName,
    String? phone,
    PostalAddress? address,
    List<AlternateEmail>? alternateEmails,
    List<AlternatePhone>? alternatePhones,
    String? photoUrl,
    int? avatarIndex,
    bool? simpleMode,
    bool? wizardCompleted,
    bool? wizardSkipped,
    String? activeCareGroupId,
    Map<String, dynamic>? wizardDraft,
    HomeSectionsVisibility? homeSections,
    UserAlertPreferences? alertPreferences,
    ExpensePaymentDetails? expensePaymentDetails,
  }) {
    return UserProfile(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      alternateEmails: alternateEmails ?? this.alternateEmails,
      alternatePhones: alternatePhones ?? this.alternatePhones,
      photoUrl: photoUrl ?? this.photoUrl,
      avatarIndex: avatarIndex ?? this.avatarIndex,
      simpleMode: simpleMode ?? this.simpleMode,
      wizardCompleted: wizardCompleted ?? this.wizardCompleted,
      wizardSkipped: wizardSkipped ?? this.wizardSkipped,
      activeCareGroupId: activeCareGroupId ?? this.activeCareGroupId,
      wizardDraft: wizardDraft ?? this.wizardDraft,
      homeSections: homeSections ?? this.homeSections,
      alertPreferences: alertPreferences ?? this.alertPreferences,
      expensePaymentDetails:
          expensePaymentDetails ?? this.expensePaymentDetails,
    );
  }

  @override
  List<Object?> get props => [
        uid,
        email,
        displayName,
        fullName,
        phone,
        address,
        alternateEmails,
        alternatePhones,
        photoUrl,
        avatarIndex,
        simpleMode,
        wizardCompleted,
        wizardSkipped,
        activeCareGroupId,
        wizardDraft,
        homeSections,
        alertPreferences,
        expensePaymentDetails,
      ];
}
