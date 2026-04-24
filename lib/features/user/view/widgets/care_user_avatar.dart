import "package:firebase_auth/firebase_auth.dart" show User;
import "package:flutter/material.dart";

import "../../../../core/avatars/avatar_choices.dart";
import "../../../../core/theme/app_colors.dart";
import "../../models/user_profile.dart";

/// Account photo, preset avatar, or initials — for toolbars, menus, and settings.
class CareUserAvatar extends StatelessWidget {
  const CareUserAvatar({
    super.key,
    required this.radius,
    this.user,
    this.profile,
  });

  final double radius;
  final User? user;
  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final fromProfile = p?.photoUrl?.trim() ?? "";
    final fromUser = user?.photoURL?.trim() ?? "";
    final networkUrl = fromProfile.isNotEmpty ? fromProfile : fromUser;
    if (networkUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.tealLight,
        backgroundImage: NetworkImage(networkUrl),
        onBackgroundImageError: (_, __) {},
        child: null,
      );
    }
    final idx = p?.avatarIndex;
    if (idx != null && idx >= 1) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.tealLight,
        child: ClipOval(
          child: buildSetupAvatarImage(
            idx,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    final name =
        (p?.displayName ?? user?.displayName ?? user?.email ?? "?").trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.tealPrimary,
      foregroundColor: Colors.white,
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _initials(String name) {
    if (name.isEmpty) {
      return "?";
    }
    final parts =
        name.split(RegExp(r"\s+")).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) {
      return name.isNotEmpty ? name[0].toUpperCase() : "?";
    }
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2
          ? "${s[0]}${s[1]}".toUpperCase()
          : s[0].toUpperCase();
    }
    return "${parts.first[0]}${parts[1][0]}".toUpperCase();
  }
}
