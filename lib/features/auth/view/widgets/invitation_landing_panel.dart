import "package:flutter/material.dart";

import "../../../../core/constants/app_constants.dart";
import "../../../../core/invite/invitation_landing_preview.dart";
import "../../../../core/theme/app_colors.dart";

/// Explains CareShare and the specific invitation before the user signs in or registers.
class InvitationLandingPanel extends StatelessWidget {
  const InvitationLandingPanel({
    super.key,
    required this.preview,

    /// When false, omits the long "Create account vs sign in" paragraph (e.g. on
    /// [InviteExistingUserScreen] where the user already has an account).
    this.showAccountCreationHints = true,
  });

  final InvitationLandingPreview preview;
  final bool showAccountCreationHints;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.tealPrimary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.waving_hand_outlined,
                  color: AppColors.tealPrimary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "You're invited",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.tealPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "${preview.inviterLabel} invited you to join ${preview.careGroupLabel} on ${AppConstants.appName}.",
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.35,
                color: AppColors.grey900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "${AppConstants.appName} helps families and carers coordinate visits, tasks, health updates, and shared updates in one place — so everyone stays aligned on the same care plan.",
              style: theme.textTheme.bodySmall?.copyWith(
                height: 1.35,
                color: AppColors.grey500,
              ),
            ),
            if (showAccountCreationHints) ...[
              const SizedBox(height: 12),
              Text(
                "Haven't used CareShare with this email before? Tap Create account and choose a password, or Continue with Google. Already have an account? Sign in below or Continue with Google — use this same invited email.",
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.35,
                  color: AppColors.grey900,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Use the same email this invitation was sent to.",
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.grey500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
