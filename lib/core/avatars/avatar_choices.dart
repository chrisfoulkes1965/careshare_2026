import "package:flutter/material.dart";

import "../theme/app_colors.dart";

/// 24 in-app "creature" avatars (emoji). Replaces missing `assets/images/avatars/avatarN.jpg` files.
const List<String> kSetupAvatarEmojis = [
  "🐱",
  "🐶",
  "🦊",
  "🐻",
  "🐼",
  "🐨",
  "🐯",
  "🦁",
  "🐮",
  "🐷",
  "🐸",
  "🐵",
  "🐔",
  "🦆",
  "🦉",
  "🦋",
  "🐢",
  "🦎",
  "🐙",
  "🦀",
  "🐬",
  "🦈",
  "🦓",
  "🦒",
];

String setupAvatarEmoji(int oneBasedIndex) {
  if (oneBasedIndex < 1 || oneBasedIndex > kSetupAvatarEmojis.length) {
    return "🐾";
  }
  return kSetupAvatarEmojis[oneBasedIndex - 1];
}

/// Soft background for each tile so the grid is readable in light and dark.
Color setupAvatarBackground(int oneBasedIndex) {
  if (oneBasedIndex < 1) {
    return AppColors.tealLight;
  }
  // Spread hues without pulling in extra dependencies.
  final t = (oneBasedIndex * 47 % 100) / 100.0;
  return Color.lerp(AppColors.tealLight, Colors.white, 0.35 + t * 0.4)!;
}
