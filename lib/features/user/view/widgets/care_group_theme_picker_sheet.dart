import "package:flutter/material.dart";

import "../../../../core/theme/care_group_header_theme.dart";

/// Returns a selected ARGB [int], the string `"reset"` to clear the custom theme,
/// or `null` if the sheet was dismissed without a choice.
Future<Object?> showCareGroupThemePicker(
  BuildContext context, {
  int? currentArgb,
}) {
  return showModalBottomSheet<Object?>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Theme colour",
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                "This colour sets the look of home for this care group — header, background, and accents. "
                "Only principal carers can change it.",
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1,
                  ),
                  itemCount: kCareGroupThemeColorPresets.length,
                  itemBuilder: (c, i) {
                    final argb = kCareGroupThemeColorPresets[i];
                    final selected = currentArgb == argb;
                    return Material(
                      color: Color(argb),
                      borderRadius: BorderRadius.circular(12),
                      elevation: selected ? 3 : 0,
                      child: InkWell(
                        onTap: () => Navigator.of(ctx).pop(argb),
                        borderRadius: BorderRadius.circular(12),
                        child: Center(
                          child: selected
                              ? Icon(
                                  Icons.check,
                                  color: Color(argb).computeLuminance() > 0.5
                                      ? Colors.black87
                                      : Colors.white,
                                )
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop("reset"),
                child: const Text("Use default brown"),
              ),
            ],
          ),
        ),
      );
    },
  );
}
