import 'package:flutter/material.dart';

/// The brand ramp and the two `ColorScheme`s built from it.
///
/// These are written out rather than generated from `colorSchemeSeed`, which is
/// what the app used to do. A seed is a fast way to get a scheme that is merely
/// legal: it derives every neutral from the brand hue, which on a teal seed
/// tints the greys green and drags clinical content — a lab value, a rejection
/// reason — toward the brand instead of leaving it neutral. Surfaces here are a
/// near-neutral slate with a trace of the brand hue, so cards read as paper and
/// the teal only appears where the app is asking for a decision.
abstract final class Brand {
  /// The product colour. Unchanged from the original seed, so nothing already
  /// shipped shifts hue.
  static const Color teal = Color(0xFF0E8388);

  static const Color teal50 = Color(0xFFE6F4F4);
  static const Color teal100 = Color(0xFFC4E5E6);
  static const Color teal200 = Color(0xFF97D2D4);
  static const Color teal300 = Color(0xFF63BCBF);
  static const Color teal400 = Color(0xFF2FA1A6);
  static const Color teal500 = teal;
  static const Color teal600 = Color(0xFF0C7276);
  static const Color teal700 = Color(0xFF0A5D61);
  static const Color teal800 = Color(0xFF08484B);
  static const Color teal900 = Color(0xFF063437);

  /// Secondary. A muted slate-blue that reads as informational next to the
  /// teal without competing with it for "this is the action".
  static const Color slate200 = Color(0xFFC9D6E2);
  static const Color slate400 = Color(0xFF6E8CA8);
  static const Color slate600 = Color(0xFF456684);
  static const Color slate800 = Color(0xFF2A4358);
}

/// Colours that carry meaning rather than brand.
///
/// A status is not "primary" or "error" — an appointment that is *completed* is
/// not an error, and a record still being scanned is not a success. Reusing
/// `colorScheme.primary` for every positive state is how a screen ends up with
/// four different meanings rendered in the same teal.
///
/// Each tone ships a foreground and a container so it can be used as text, as
/// an icon, or as a filled chip without the caller mixing its own alpha.
@immutable
class AppTones extends ThemeExtension<AppTones> {
  const AppTones({
    required this.success,
    required this.onSuccessContainer,
    required this.successContainer,
    required this.warning,
    required this.onWarningContainer,
    required this.warningContainer,
    required this.danger,
    required this.onDangerContainer,
    required this.dangerContainer,
    required this.info,
    required this.onInfoContainer,
    required this.infoContainer,
    required this.neutral,
    required this.neutralContainer,
  });

  /// Confirmed, approved, completed, verified.
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  /// Awaiting something: under review, scanning, hold expiring, expiring soon.
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// Cancelled, rejected, suspended, revoked, infected file.
  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;

  /// Neutral emphasis: a reference code, an in-person badge, a hint.
  final Color info;
  final Color infoContainer;
  final Color onInfoContainer;

  /// Past and inactive — deliberately low-contrast so history recedes behind
  /// what is still actionable.
  final Color neutral;
  final Color neutralContainer;

  static const AppTones light = AppTones(
    success: Color(0xFF186E48),
    successContainer: Color(0xFFDCF2E7),
    onSuccessContainer: Color(0xFF0B3B26),
    warning: Color(0xFF8A5200),
    warningContainer: Color(0xFFFCEFD9),
    onWarningContainer: Color(0xFF4A2C00),
    danger: Color(0xFFB3261E),
    dangerContainer: Color(0xFFFBE3E1),
    onDangerContainer: Color(0xFF5F150F),
    info: Color(0xFF2A5B8C),
    infoContainer: Color(0xFFE2ECF7),
    onInfoContainer: Color(0xFF14304A),
    neutral: Color(0xFF5C6B6C),
    neutralContainer: Color(0xFFEDF1F1),
  );

  /// Not the light values darkened. Saturated foregrounds go muddy on a dark
  /// surface and fail contrast; these are lifted in lightness and pulled back
  /// in chroma so each still clears 4.5:1 on the dark surface.
  static const AppTones dark = AppTones(
    success: Color(0xFF6EDCA6),
    successContainer: Color(0xFF11331F),
    onSuccessContainer: Color(0xFFB6EFD1),
    warning: Color(0xFFF3BE5C),
    warningContainer: Color(0xFF3A2A0A),
    onWarningContainer: Color(0xFFFAE0AE),
    danger: Color(0xFFFF897D),
    dangerContainer: Color(0xFF3F1512),
    onDangerContainer: Color(0xFFFFCFC9),
    info: Color(0xFF9CC4EC),
    infoContainer: Color(0xFF14273A),
    onInfoContainer: Color(0xFFCFE1F5),
    neutral: Color(0xFF9AACAD),
    neutralContainer: Color(0xFF1E2829),
  );

  @override
  AppTones copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? onDangerContainer,
    Color? info,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? neutral,
    Color? neutralContainer,
  }) {
    return AppTones(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      neutral: neutral ?? this.neutral,
      neutralContainer: neutralContainer ?? this.neutralContainer,
    );
  }

  @override
  AppTones lerp(ThemeExtension<AppTones>? other, double t) {
    if (other is! AppTones) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTones(
      success: mix(success, other.success),
      successContainer: mix(successContainer, other.successContainer),
      onSuccessContainer: mix(onSuccessContainer, other.onSuccessContainer),
      warning: mix(warning, other.warning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarningContainer: mix(onWarningContainer, other.onWarningContainer),
      danger: mix(danger, other.danger),
      dangerContainer: mix(dangerContainer, other.dangerContainer),
      onDangerContainer: mix(onDangerContainer, other.onDangerContainer),
      info: mix(info, other.info),
      infoContainer: mix(infoContainer, other.infoContainer),
      onInfoContainer: mix(onInfoContainer, other.onInfoContainer),
      neutral: mix(neutral, other.neutral),
      neutralContainer: mix(neutralContainer, other.neutralContainer),
    );
  }
}

/// Reads the tones off the theme.
///
/// `Theme.of(context).extension<AppTones>()!` at every call site is enough
/// friction that people reach for `colorScheme.primary` instead, which is the
/// exact problem the extension exists to solve. The fallback is not defensive
/// padding — a widget booted in a bare `MaterialApp` (several golden tests do
/// this) has no extension registered, and a null crash there would be a test
/// failure about theming rather than about the widget.
extension AppTonesX on BuildContext {
  AppTones get tones {
    final theme = Theme.of(this);
    return theme.extension<AppTones>() ??
        (theme.brightness == Brightness.dark ? AppTones.dark : AppTones.light);
  }
}

/// The light scheme.
const ColorScheme lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Brand.teal600,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Brand.teal50,
  onPrimaryContainer: Brand.teal900,
  secondary: Brand.slate600,
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE7EEF5),
  onSecondaryContainer: Brand.slate800,
  tertiary: Color(0xFF8A5200),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFCEFD9),
  onTertiaryContainer: Color(0xFF4A2C00),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFBE3E1),
  onErrorContainer: Color(0xFF5F150F),
  // Cards sit on `surface`; the scaffold uses `surfaceContainerLow` so a card
  // is lighter than the page behind it rather than the same white-on-white
  // that made every list read as one undivided block.
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF111C1D),
  onSurfaceVariant: Color(0xFF4C5D5E),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF6FAFA),
  surfaceContainer: Color(0xFFF0F5F5),
  surfaceContainerHigh: Color(0xFFE9F0F0),
  surfaceContainerHighest: Color(0xFFE2EAEA),
  surfaceTint: Brand.teal600,
  inverseSurface: Color(0xFF1E2B2C),
  onInverseSurface: Color(0xFFEFF4F4),
  inversePrimary: Brand.teal300,
  outline: Color(0xFF77898A),
  outlineVariant: Color(0xFFD5DFDF),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// The dark scheme.
///
/// Surfaces are a very dark slate rather than pure black: OLED black makes the
/// white-on-black text of a records list vibrate, and every elevation step
/// above it has to be invented from nothing.
const ColorScheme darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Brand.teal300,
  onPrimary: Brand.teal900,
  primaryContainer: Brand.teal800,
  onPrimaryContainer: Brand.teal100,
  secondary: Color(0xFFA8C3DA),
  onSecondary: Color(0xFF16293A),
  secondaryContainer: Color(0xFF2A4358),
  onSecondaryContainer: Brand.slate200,
  tertiary: Color(0xFFF3BE5C),
  onTertiary: Color(0xFF3A2A0A),
  tertiaryContainer: Color(0xFF5C4211),
  onTertiaryContainer: Color(0xFFFAE0AE),
  error: Color(0xFFFF897D),
  onError: Color(0xFF450F0A),
  errorContainer: Color(0xFF741A14),
  onErrorContainer: Color(0xFFFFDAD5),
  surface: Color(0xFF141B1C),
  onSurface: Color(0xFFE3EAEA),
  onSurfaceVariant: Color(0xFFB2C2C3),
  surfaceContainerLowest: Color(0xFF0A0F10),
  surfaceContainerLow: Color(0xFF10181A),
  surfaceContainer: Color(0xFF182122),
  surfaceContainerHigh: Color(0xFF1F2A2B),
  surfaceContainerHighest: Color(0xFF283435),
  surfaceTint: Brand.teal300,
  inverseSurface: Color(0xFFE3EAEA),
  onInverseSurface: Color(0xFF1E2B2C),
  inversePrimary: Brand.teal700,
  outline: Color(0xFF7C8E8F),
  outlineVariant: Color(0xFF3A4647),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);
