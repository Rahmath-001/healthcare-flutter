import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../error/failure.dart';

/// Crash and error reporting.
///
/// Until this existed a production crash was invisible: every diagnostic
/// `debugPrint` is compiled out of release, and R8 was preserving line numbers
/// for a reporter that did not exist. The only surviving signal was errors the
/// *server* saw — which is precisely the wrong half for a 100ms-based app that
/// has never been tested on a real Indian mobile network.
///
/// The hard constraint is that this is a health app. A crash report that
/// carries a patient's name, a diagnosis or a record title is a PHI disclosure
/// to a third-party processor, so nothing here ever forwards a message the
/// server or the domain layer produced. What gets recorded is the *shape* of a
/// failure — its type, its machine code, and where it happened.
abstract final class CrashReporting {
  /// Installs the global error handlers.
  ///
  /// Both are needed and they catch different things: `FlutterError.onError`
  /// covers errors inside the framework's build/layout/paint phases, while
  /// `PlatformDispatcher.instance.onError` covers everything else that reaches
  /// the root zone — a rejected Future in a controller, most commonly.
  static Future<void> initialise(AppConfig config) async {
    final crashlytics = FirebaseCrashlytics.instance;

    // Collecting from debug builds fills the dashboard with a developer's own
    // hot-reload noise and hides the reports that matter.
    await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
    await crashlytics.setCustomKey('env', config.env.name);

    FlutterError.onError = (details) {
      // Keeps the red screen and the console output in debug.
      FlutterError.presentError(details);
      if (kDebugMode) return;
      crashlytics.recordFlutterFatalError(_scrub(details));
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) return false;
      crashlytics.recordError(_describe(error), stack, fatal: true);
      return true;
    };
  }

  /// Associates reports with a session, never with a person.
  ///
  /// The MiDoctor user id is an opaque identifier that means nothing outside
  /// this system — unlike a name, phone number or email, which would turn every
  /// crash report into a disclosure.
  static Future<void> setUser(String? userId) =>
      FirebaseCrashlytics.instance.setUserIdentifier(userId ?? '');

  /// Records a handled failure that the user was shown.
  ///
  /// Useful for the failures that are technically handled but still mean the
  /// product did not work — a consultation that could not be joined, an upload
  /// that expired. Only the machine code is sent; [Failure.message] is written
  /// for a human and can quote server `detail`.
  static Future<void> recordHandled(Failure failure, {String? context}) {
    if (kDebugMode) return Future<void>.value();
    return FirebaseCrashlytics.instance.recordError(
      'Failure(${failure.kind.name}/${failure.code ?? 'NO_CODE'})',
      StackTrace.current,
      reason: context,
      fatal: false,
    );
  }

  /// Leaves a trail of *where* the user was, never of what they were reading.
  ///
  /// Route names only. A breadcrumb like "opened record: Chest X-Ray" would put
  /// a diagnosis in a crash report.
  static void breadcrumb(String route) {
    if (kDebugMode) return;
    FirebaseCrashlytics.instance.log('nav:$route');
  }

  /// Strips a [Failure]'s human-readable message out of a Flutter error.
  ///
  /// `Failure.message` is shown to the user and may quote the server's `detail`
  /// verbatim, so it is exactly the field most likely to carry something about
  /// a person. The kind and code survive, which is what a report needs.
  static FlutterErrorDetails _scrub(FlutterErrorDetails details) {
    final error = details.exception;
    if (error is! Failure) return details;

    return FlutterErrorDetails(
      exception: _describe(error),
      stack: details.stack,
      library: details.library,
      context: details.context,
    );
  }

  static Object _describe(Object error) {
    if (error is Failure) {
      return 'Failure(${error.kind.name}/${error.code ?? 'NO_CODE'})';
    }
    return error;
  }
}
