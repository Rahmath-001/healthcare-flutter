import 'package:flutter/material.dart';

/// The console's visual language.
///
/// Deliberately not the patient app's. An operator holding both open should
/// never be in doubt about which one they are acting in — approving a doctor
/// and browsing as a patient are different kinds of act, and a shared palette
/// invites the mistake.
///
/// Denser than the mobile theme, too: this is a tool used all day on a large
/// screen, where the mobile app's generous touch targets waste the room that
/// makes a review queue readable.
abstract final class AdminTheme {
  /// Slate rather than the product's teal.
  static const _seed = Color(0xFF334155);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant,
      ),
      listTileTheme: const ListTileThemeData(dense: true),
    );
  }
}

/// The widest a reading column gets.
///
/// A review queue stretched across a 27-inch monitor is unreadable; the eye
/// loses its place between the name at one edge and the decision at the other.
const kAdminMaxContentWidth = 1160.0;
