import "package:flutter/material.dart";

import "app_colors.dart";

/// HSL hue +180° — complement of the theme background, for the logo mark.
Color complementaryLogoOnTheme(Color background) {
  final hsl = HSLColor.fromColor(background);
  var h = (hsl.hue + 180) % 360.0;
  var c = hsl.withHue(h);
  if (c.saturation < 0.2) {
    c = c.withSaturation(0.4);
  }
  var out = c.toColor();
  final dL = (out.computeLuminance() - background.computeLuminance()).abs();
  if (dL < 0.18) {
    out = background.computeLuminance() < 0.5
        ? const Color(0xFFF0E8E0)
        : const Color(0xFF2A2118);
  }
  return out;
}

/// Styling for the home header bar derived from a per–care group theme colour, or the default
/// [AppColors.homeHeaderBrown] when [activeThemeArgb] is null.
class CareGroupHeaderStyle {
  const CareGroupHeaderStyle({
    required this.background,
    required this.onBackground,
    required this.onBackgroundMuted,
    required this.hint,
    required this.logoTint,
    required this.subtle,
    this.avatarMaterialColor,
    this.avatarRingColor,
  });

  final Color background;
  final Color onBackground;
  final Color onBackgroundMuted;
  final Color hint;

  /// Complement of the header [background], used to tint a transparent
  /// monochrome PNG (`Image.color` + [BlendMode.srcIn]).
  final Color logoTint;
  final Color subtle;
  final Color? avatarMaterialColor;
  final Color? avatarRingColor;
}

/// Picks high-contrast text and logo tints for light vs dark [background] colors.
CareGroupHeaderStyle resolveCareGroupHeaderStyle({int? activeThemeArgb}) {
  final bg = activeThemeArgb != null
      ? Color(activeThemeArgb)
      : AppColors.homeHeaderBrown;
  final dark = _isDarkishBackground(bg);
  final logo = complementaryLogoOnTheme(bg);
  if (dark) {
    return CareGroupHeaderStyle(
      background: bg,
      onBackground: const Color(0xFFF5F0EA),
      onBackgroundMuted: const Color(0xFFF5F0EA).withValues(alpha: 0.7),
      hint: const Color(0xFFC4B0A0),
      logoTint: logo,
      subtle: const Color(0xA6F5F0EA),
      avatarMaterialColor: const Color(0xFF6B4D35),
      avatarRingColor: const Color(0xFF8C6E55),
    );
  }
  return CareGroupHeaderStyle(
    background: bg,
    onBackground: const Color(0xFF2A2118),
    onBackgroundMuted: const Color(0xD02A2118),
    hint: const Color(0xFF6B5D4D),
    logoTint: logo,
    subtle: const Color(0xA62A2118),
    avatarMaterialColor: const Color(0xFFEDE6DD),
    avatarRingColor: const Color(0xFF4A3D2E),
  );
}

bool _isDarkishBackground(Color c) {
  return c.computeLuminance() < 0.5;
}

/// Preset theme colors (ARGB) for the care group settings picker.
const List<int> kCareGroupThemeColorPresets = <int>[
  0xFF3B2A1A, // default brown
  0xFF2196F3, // material blue
  0xFF1A7F7A, // teal
  0xFF5C6BC0, // indigo
  0xFF6D4C41, // brown
  0xFF00897B, // teal dark
  0xFF3949AB, // indigo deep
  0xFF7B1FA2, // purple
  0xFF00695C, // green dark
  0xFFBF360C, // deep orange
  0xFF4E342E, // brown deep
  0xFF0D47A1, // blue deep
  0xFF5D4037, // brown
  0xFF1B5E20, // green
  0xFF4A148C, // deep purple
  0xFFAD1457, // pink
];

/// Merged surface + content colours for the home screen (below the header), derived
/// from the same [activeThemeArgb] as the header, or the warm defaults when null.
@immutable
class CareGroupHomePageStyle {
  const CareGroupHomePageStyle({
    required this.scaffoldBackground,
    required this.textPrimary,
    required this.textMuted,
    required this.textTertiary,
    required this.timeMuted,
    required this.todayNeedsAccent,
    required this.todayStripBackground,
    required this.todayStripBorder,
    required this.addCta,
    required this.onAddCta,
    required this.feedBorder,
    required this.cardBorder,
    required this.cardBorderUnassigned,
    required this.chipTagBackground,
    required this.chipTagForeground,
    required this.dividerSubtle,
    required this.cardShadow,
    required this.wizardBannerBackground,
    required this.outlineAccent,
    required this.switchCareGroupText,
    required this.toolBarChips,
    required this.refreshIndicator,
  });

  final Color scaffoldBackground;
  final Color textPrimary;
  final Color textMuted;
  final Color textTertiary;
  final Color timeMuted;
  final Color todayNeedsAccent;
  final Color todayStripBackground;
  final Color todayStripBorder;
  final Color addCta;
  final Color onAddCta;
  final Color feedBorder;
  final Color cardBorder;
  final Color cardBorderUnassigned;
  final Color chipTagBackground;
  final Color chipTagForeground;
  final Color dividerSubtle;
  final Color cardShadow;
  final Color wizardBannerBackground;
  final Color outlineAccent;
  final Color switchCareGroupText;
  final List<({Color background, Color iconColor})> toolBarChips;
  final Color refreshIndicator;

  static const CareGroupHomePageStyle fallback = CareGroupHomePageStyle(
    scaffoldBackground: AppColors.homeWarmBackground,
    textPrimary: AppColors.homeTextPrimary,
    textMuted: AppColors.homeTextMuted,
    textTertiary: Color(0xFF8C7A6A),
    timeMuted: Color(0xFFB0A090),
    todayNeedsAccent: Color(0xFF7A5C3A),
    todayStripBackground: AppColors.homeTodayStripBg,
    todayStripBorder: AppColors.homeTodayStripBorder,
    addCta: AppColors.homeAddCta,
    onAddCta: Color(0xFFF5F0EA),
    feedBorder: AppColors.homeFeedBorder,
    cardBorder: Color(0x1A3B2A1A),
    cardBorderUnassigned: Color(0x263B2A1A),
    chipTagBackground: Color(0xFFE6F1FB),
    chipTagForeground: Color(0xFF185FA5),
    dividerSubtle: Color(0x143B2A1A),
    cardShadow: Color(0x0D3B2A1A),
    wizardBannerBackground: AppColors.tealLight,
    outlineAccent: AppColors.tealPrimary,
    switchCareGroupText: Color(0xFF8C6E55),
    toolBarChips: _kDefaultToolBarChips,
    refreshIndicator: AppColors.tealPrimary,
  );
}

const List<({Color background, Color iconColor})> _kDefaultToolBarChips =
    <({Color background, Color iconColor})>[
  (background: Color(0xFFFEF3E9), iconColor: Color(0xFF8C6E55)),
  (background: Color(0xFFE6F0FA), iconColor: Color(0xFF185FA5)),
  (background: Color(0xFFE8F5E5), iconColor: Color(0xFF3B6D11)),
  (background: Color(0xFFEEEDFE), iconColor: Color(0xFF534AB7)),
  (background: Color(0xFFF0EBE3), iconColor: Color(0xFF6B4D35)),
  (background: Color(0xFFDEEDF8), iconColor: Color(0xFF185FA5)),
  (background: Color(0xFFF5F0EA), iconColor: Color(0xFF8C4A1E)),
  (background: Color(0xFFE6F0FA), iconColor: Color(0xFF1A7F7A)),
  (background: Color(0xFFFDECEA), iconColor: Color(0xFFA32D2D)),
  (background: Color(0xFFEEEDFE), iconColor: Color(0xFF534AB7)),
  (background: Color(0xFFE8F4ED), iconColor: Color(0xFF2E7D5A)),
  (background: Color(0xFFEDE7F6), iconColor: Color(0xFF5C4A9A)),
];

Color _a(Color base, int a) => base.withValues(alpha: a / 255.0);

List<({Color background, Color iconColor})> _toolBarChipsForSeed(Color seed) {
  return List<({Color background, Color iconColor})>.generate(12, (i) {
    final h0 = HSLColor.fromColor(seed);
    final h = (h0.hue + i * (360.0 / 12.0)) % 360.0;
    var bg = h0
        .withHue(h)
        .withSaturation((h0.saturation * 0.4 + 0.28).clamp(0.2, 0.55))
        .withLightness(0.94)
        .toColor();
    var ic = h0
        .withHue(h)
        .withSaturation((h0.saturation * 0.65 + 0.35).clamp(0.4, 0.75))
        .withLightness(0.40)
        .toColor();
    if ((bg.computeLuminance() - ic.computeLuminance()).abs() < 0.2) {
      ic = h0.withHue(h).withSaturation(0.6).withLightness(0.32).toColor();
    }
    return (background: bg, iconColor: ic);
  });
}

/// Page chrome (scaffold, cards, CTA) matching [activeThemeArgb], or
/// [CareGroupHomePageStyle.fallback] when the care group uses the default header.
CareGroupHomePageStyle resolveCareGroupHomePageStyle({int? activeThemeArgb}) {
  if (activeThemeArgb == null) {
    return CareGroupHomePageStyle.fallback;
  }
  final seed = Color(activeThemeArgb);
  final hsl = HSLColor.fromColor(seed);
  final textPrimary = hsl
      .withSaturation((hsl.saturation * 0.35 + 0.12).clamp(0.12, 0.32))
      .withLightness(0.16)
      .toColor();
  final textMuted = hsl
      .withSaturation((hsl.saturation * 0.2 + 0.05).clamp(0.05, 0.2))
      .withLightness(0.45)
      .toColor();
  final textTertiary = hsl.withSaturation(0.12).withLightness(0.5).toColor();
  final timeMuted = hsl.withSaturation(0.1).withLightness(0.66).toColor();
  final todayNeedsAccent = hsl
      .withSaturation((hsl.saturation * 0.45 + 0.2).clamp(0.2, 0.55))
      .withLightness(0.38)
      .toColor();
  final scaffold = hsl
      .withSaturation((hsl.saturation * 0.12 + 0.04).clamp(0.04, 0.2))
      .withLightness(0.96)
      .toColor();
  final strip = hsl
      .withSaturation((hsl.saturation * 0.4 + 0.15).clamp(0.15, 0.5))
      .withLightness(0.94)
      .toColor();
  final stripBorder = hsl
      .withSaturation((hsl.saturation * 0.45 + 0.2).clamp(0.2, 0.55))
      .withLightness(0.78)
      .toColor();
  final cta = hsl
      .withSaturation((hsl.saturation * 0.9 + 0.1).clamp(0.25, 0.75))
      .withLightness((hsl.lightness * 0.5).clamp(0.2, 0.42))
      .toColor();
  final onCta = cta.computeLuminance() < 0.5
      ? const Color(0xFFF5F0EA)
      : const Color(0xFF1A1816);
  final chipTagBg = Color.lerp(const Color(0xFFFFFFFF), seed, 0.12)!;
  var chipTagFg = hsl
      .withSaturation((hsl.saturation * 0.7 + 0.2).clamp(0.35, 0.8))
      .withLightness(0.35)
      .toColor();
  if ((chipTagBg.computeLuminance() - chipTagFg.computeLuminance()).abs() <
      0.25) {
    chipTagFg = hsl.withLightness(0.28).withSaturation(0.65).toColor();
  }
  return CareGroupHomePageStyle(
    scaffoldBackground: scaffold,
    textPrimary: textPrimary,
    textMuted: textMuted,
    textTertiary: textTertiary,
    timeMuted: timeMuted,
    todayNeedsAccent: todayNeedsAccent,
    todayStripBackground: strip,
    todayStripBorder: stripBorder,
    addCta: cta,
    onAddCta: onCta,
    feedBorder: _a(seed, 0x1A),
    cardBorder: _a(seed, 0x1A),
    cardBorderUnassigned: _a(seed, 0x26),
    chipTagBackground: chipTagBg,
    chipTagForeground: chipTagFg,
    dividerSubtle: _a(seed, 0x14),
    cardShadow: _a(seed, 0x0D),
    wizardBannerBackground: Color.lerp(const Color(0xFFFFFFFF), seed, 0.14)!,
    outlineAccent: seed,
    switchCareGroupText: hsl
        .withSaturation((hsl.saturation * 0.35 + 0.15).clamp(0.2, 0.45))
        .withLightness(0.45)
        .toColor(),
    toolBarChips: _toolBarChipsForSeed(seed),
    refreshIndicator: seed,
  );
}

/// Material [ThemeData] overlay for feature screens (AppBar, FAB, primary controls) so
/// they use the same colours as the care group home header. Use [AppTheme.light] as [base].
ThemeData buildCareGroupAppTheme(ThemeData base, {int? activeThemeArgb}) {
  final h = resolveCareGroupHeaderStyle(activeThemeArgb: activeThemeArgb);
  final seed = h.background;
  final onBar = h.onBackground;
  final fromSeed = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  );
  final primaryContainer = Color.lerp(
    const Color(0xFFFFFFFF),
    seed,
    0.2,
  )!;

  final scheme = fromSeed.copyWith(
    primary: seed,
    onPrimary: onBar,
    primaryContainer: primaryContainer,
    onPrimaryContainer: seed,
  );

  final titleBase =
      base.appBarTheme.titleTextStyle ?? base.textTheme.titleLarge;
  return base.copyWith(
    colorScheme: scheme,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: h.background,
      foregroundColor: h.onBackground,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(color: h.onBackground),
      actionsIconTheme: IconThemeData(color: h.onBackground),
      titleTextStyle: titleBase != null
          ? titleBase.copyWith(
              color: h.onBackground,
              fontWeight: FontWeight.w600,
            )
          : base.textTheme.titleLarge?.copyWith(
              color: h.onBackground,
              fontWeight: FontWeight.w600,
            ),
    ),
    progressIndicatorTheme: base.progressIndicatorTheme.copyWith(
      color: seed,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryContainer,
      foregroundColor: seed,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: seed,
        foregroundColor: onBar,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: seed,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: seed),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: seed),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: seed, width: 2),
      ),
    ),
  );
}

/// Supplies [resolveCareGroupHomePageStyle] to descendants (home landing content).
@immutable
class CareGroupHomeStyleScope extends InheritedWidget {
  const CareGroupHomeStyleScope({
    super.key,
    required this.style,
    required this.activeThemeArgb,
    required super.child,
  });

  final CareGroupHomePageStyle style;
  final int? activeThemeArgb;

  static CareGroupHomePageStyle of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<CareGroupHomeStyleScope>();
    return scope?.style ?? CareGroupHomePageStyle.fallback;
  }

  @override
  bool updateShouldNotify(covariant CareGroupHomeStyleScope oldWidget) {
    return oldWidget.activeThemeArgb != activeThemeArgb;
  }
}
