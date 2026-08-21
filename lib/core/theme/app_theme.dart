import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';
import 'app_tokens.dart';

/// The patient/provider app's visual language.
///
/// Everything a screen needs to look right is configured here, once. The
/// alternative — each screen choosing its own radius, padding and elevation —
/// is what the app was doing, and it is why a `Card` on Records did not match a
/// `Card` on Appointments even though both used the default.
///
/// Not shared with the operator console: see `lib/admin/theme/admin_theme.dart`
/// for why an operator should never be in doubt about which app they are in.
abstract final class AppTheme {
  static ThemeData get light => _build(lightScheme, AppTones.light);
  static ThemeData get dark => _build(darkScheme, AppTones.dark);

  /// Status-bar / navigation-bar styling for each brightness.
  ///
  /// Applied through the `AppBarTheme` rather than a global
  /// `SystemChrome.setSystemUIOverlayStyle` call, so it survives a theme change
  /// at runtime instead of being whatever the last screen happened to set.
  static SystemUiOverlayStyle _overlay(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark
          ? darkScheme.surfaceContainerLow
          : lightScheme.surfaceContainerLow,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );
  }

  static ThemeData _build(ColorScheme scheme, AppTones tones) {
    final text = _textTheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      extensions: <ThemeExtension<dynamic>>[tones],
      textTheme: text,

      // The page is one step below a card, so cards lift off it without a
      // shadow. On a pure-white scaffold every card border has to be drawn.
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      canvasColor: scheme.surface,

      // The M3 ink ripple. The default splash on Android is the M2 one, which
      // reads as a different app to anything else on the device.
      splashFactory: InkSparkle.splashFactory,

      // Standard, not compact: this app is used one-handed, sometimes by
      // someone unwell, and shaving 8px off every tap target to fit more rows
      // is the wrong trade for a booking flow.
      visualDensity: VisualDensity.standard,

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // Android 14+ back gesture: the outgoing page follows the finger.
          // Falls back to the zoom transition on older versions by itself.
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLow,
        foregroundColor: scheme.onSurface,
        // Transparent tint, because the app bar already sits on the scaffold
        // colour; the default tint makes it drift teal as content scrolls
        // under it, which reads as a rendering bug rather than elevation.
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: _overlay(scheme.brightness),
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),

      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: Elevations.card,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.mdAll,
          // A hairline instead of a shadow. In dark mode a shadow against a
          // near-black surface conveys nothing at all, so the card edge has to
          // be a line or the card has no edge.
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),

      // 52 tall everywhere. The old `PrimaryButton` hard-coded that height
      // while every other button in the app was 40, so the same action looked
      // like two different weights depending on the screen.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          shape: const RoundedRectangleBorder(borderRadius: Radii.pillAll),
          textStyle: text.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
          shape: const RoundedRectangleBorder(borderRadius: Radii.pillAll),
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          // 44 rather than the M3 default of 40: 44 is the smaller of the two
          // platform minimum touch targets, and several of these sit in a
          // stack where a mis-tap costs the user a whole screen.
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
          shape: const RoundedRectangleBorder(borderRadius: Radii.pillAll),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const RoundedRectangleBorder(borderRadius: Radii.pillAll),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 3,
        hoverElevation: 3,
        highlightElevation: 1,
        extendedTextStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onPrimary,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),

      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md + 2,
        ),
        border: const OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        hintStyle: text.bodyMedium?.copyWith(color: scheme.outline),
        // The default floating label overlaps a filled field's top border at
        // large text scales; keeping it above the field avoids that entirely.
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
        side: BorderSide.none,
        shape: const RoundedRectangleBorder(borderRadius: Radii.pillAll),
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm,
        ),
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        secondaryLabelStyle:
            text.labelLarge?.copyWith(color: scheme.onPrimaryContainer),
        showCheckmark: false,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        elevation: 3,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape:
            const RoundedRectangleBorder(borderRadius: Radii.pillAll),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color:
                selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
          );
        }),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            text.titleSmall?.copyWith(fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          borderSide: BorderSide(color: scheme.primary, width: 3),
        ),
        dividerColor: scheme.outlineVariant,
        overlayColor: WidgetStatePropertyAll(
          scheme.primary.withValues(alpha: 0.06),
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: scheme.surfaceContainerHigh,
          selectedBackgroundColor: scheme.primaryContainer,
          selectedForegroundColor: scheme.onPrimaryContainer,
          foregroundColor: scheme.onSurfaceVariant,
          side: BorderSide.none,
          shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
          textStyle: text.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: Insets.md),
        ),
      ),

      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.xs,
        ),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
        minVerticalPadding: Insets.md,
      ),

      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: scheme.outlineVariant,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: Elevations.sheet,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: Elevations.dialog,
        shape: const RoundedRectangleBorder(borderRadius: Radii.lgAll),
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        insetPadding: const EdgeInsets.all(Insets.lg),
        shape: const RoundedRectangleBorder(borderRadius: Radii.smAll),
        elevation: Elevations.sheet,
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: Radii.smAll,
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: Colors.transparent,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.onPrimary : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? scheme.primary : null),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
        elevation: Elevations.sheet,
      ),
    );
  }

  /// The type scale.
  ///
  /// Material's default tracking is tuned for short marketing strings; at
  /// `bodySmall` it spaces out exactly the dense metadata this app is full of
  /// — "Lab report · 12 Aug 2026 · Apollo" — until it wraps a line early. The
  /// tracking below is tightened and `bodySmall` is 13 rather than 12, because
  /// it carries real content here (scan status, dosage, expiry) and not just
  /// captions, and a chunk of this audience is reading it without glasses.
  static TextTheme _textTheme(ColorScheme scheme) {
    final onSurface = scheme.onSurface;
    final variant = scheme.onSurfaceVariant;

    return TextTheme(
      displaySmall: TextStyle(
        fontSize: 34,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: onSurface,
      ),
      headlineLarge: TextStyle(
        fontSize: 30,
        height: 1.22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: onSurface,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: onSurface,
      ),
      headlineSmall: TextStyle(
        fontSize: 22,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: onSurface,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: onSurface,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        height: 1.4,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.05,
        color: onSurface,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: onSurface,
      ),
      bodyMedium: TextStyle(
        fontSize: 14.5,
        height: 1.45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: onSurface,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        color: variant,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: onSurface,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: variant,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: variant,
      ),
    );
  }
}
