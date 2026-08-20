import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// `context.l10n.someKey`, instead of `AppLocalizations.of(context)!.someKey`.
///
/// Short enough that using it is never the inconvenient option — which matters,
/// because the previous state of this project was an ARB file wired into
/// `MaterialApp` that **no screen read**, while ~270 English literals sat in the
/// widgets. Localisation that is more effort than typing the string does not
/// happen.
///
/// Non-nullable: `nullable-getter: false` in `l10n.yaml` means a missing
/// delegate is a crash at startup rather than a null somewhere in a build
/// method, which is the right way round for something every screen depends on.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
