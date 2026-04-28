import "package:flutter/material.dart";

import "../../../../core/theme/app_colors.dart";

/// List row for tool navigation (home, settings-style lists).
class CareActionCard extends StatelessWidget {
  const CareActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.warm = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool warm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: warm ? 0 : 1,
        shadowColor: const Color(0x0D3B2A1A),
        surfaceTintColor: Colors.transparent,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: warm
              ? const BorderSide(color: Color(0x1A3B2A1A))
              : const BorderSide(color: AppColors.grey200),
        ),
        child: ListTile(
          onTap: onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Icon(icon, color: AppColors.tealPrimary),
          title: Text(title),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.chevron_right,
            color: AppColors.homeTextMuted.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
