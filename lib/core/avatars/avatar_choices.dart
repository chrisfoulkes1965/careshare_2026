import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../theme/app_colors.dart";

/// Fallback when [AssetManifest] is unavailable — must match real files (this project uses .jpg).
const int kSetupAvatarFileCount = 48;
const String kSetupAvatarFileExtension = "jpg";

/// Fallback paths when manifest discovery finds nothing (e.g. hot-reload before full restart).
final List<String> kSetupAvatarAssetPaths = List<String>.unmodifiable([
  for (var i = 1; i <= kSetupAvatarFileCount; i++)
    "assets/images/avatars/avatar$i.$kSetupAvatarFileExtension",
]);

/// Discovered image paths under [assets/images/avatars/], sorted. Filled by [initAvatarAssetPaths].
List<String> _resolvedAvatarPaths = List<String>.from(kSetupAvatarAssetPaths);

/// Call once at startup (e.g. from [main]) after [WidgetsFlutterBinding.ensureInitialized].
/// Lists assets via [AssetManifest] (replaces removed `AssetManifest.json`) so any images
/// you add under [assets/images/avatars/] are picked up, including .jpg, .png, or .webp.
Future<void> initAvatarAssetPaths([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  final discovered = await _discoverAvatarPathsFromManifest(b);
  if (discovered.isNotEmpty) {
    _resolvedAvatarPaths = discovered;
  }
}

Future<List<String>> _discoverAvatarPathsFromManifest(AssetBundle bundle) async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    const prefix = "assets/images/avatars/";
    final out = <String>[];
    for (final key in manifest.listAssets()) {
      if (!key.startsWith(prefix)) {
        continue;
      }
      if (key.split("/").last.startsWith(".")) {
        // skip e.g. .gitkeep
        continue;
      }
      final lower = key.toLowerCase();
      if (lower.endsWith(".png") ||
          lower.endsWith(".jpg") ||
          lower.endsWith(".jpeg") ||
          lower.endsWith(".webp") ||
          lower.endsWith(".gif")) {
        out.add(key);
      }
    }
    out.sort(_compareAvatarPaths);
    return out;
  } catch (_) {
    return [];
  }
}

int _compareAvatarPaths(String a, String b) {
  final na = _firstIntInFileName(a);
  final nb = _firstIntInFileName(b);
  if (na != null && nb != null && na != nb) {
    return na.compareTo(nb);
  }
  return a.toLowerCase().compareTo(b.toLowerCase());
}

int? _firstIntInFileName(String assetPath) {
  final name = assetPath.split("/").last;
  final m = RegExp(r"(\d+)").firstMatch(name);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

int get kSetupAvatarCount => _resolvedAvatarPaths.length;

String? setupAvatarAssetPath(int oneBasedIndex) {
  if (oneBasedIndex < 1 || oneBasedIndex > _resolvedAvatarPaths.length) {
    return null;
  }
  return _resolvedAvatarPaths[oneBasedIndex - 1];
}

/// Optional tint behind the image in the picker.
Color setupAvatarBackground(int oneBasedIndex) {
  if (oneBasedIndex < 1) {
    return AppColors.tealLight;
  }
  final t = (oneBasedIndex * 47 % 100) / 100.0;
  return Color.lerp(AppColors.tealLight, Colors.white, 0.35 + t * 0.4)!;
}

/// Picker / summary: shows asset image, or a pet icon if the file is missing.
Widget buildSetupAvatarImage(
  int oneBasedIndex, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.cover,
  BorderRadius? borderRadius,
}) {
  final path = setupAvatarAssetPath(oneBasedIndex);
  final size = height ?? width ?? 32.0;
  final icon = Icon(Icons.pets, size: size * 0.6);
  final child = path == null
      ? icon
      : Image.asset(
          path,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => icon,
        );
  if (borderRadius == null) {
    return child;
  }
  return ClipRRect(
    borderRadius: borderRadius,
    child: child,
  );
}
