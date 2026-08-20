import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/widgets/primary_button.dart';

/// Widget tests for the presentational widgets that have no Firebase
/// dependency. Screens are covered once they sit behind repositories that can
/// be overridden in tests (Phase 1).
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('PrimaryButton', () {
    testWidgets('renders its label and fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        PrimaryButton(label: 'Continue', onPressed: () => taps++),
      ));

      expect(find.text('Continue'), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('shows a spinner and swallows taps while loading',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(wrap(
        PrimaryButton(
          label: 'Continue',
          onPressed: () => taps++,
          loading: true,
        ),
      ));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Continue'), findsNothing);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      // Loading must disable the button, otherwise a double-tap can double-submit
      // an OTP request or, later, a booking.
      expect(taps, 0);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(wrap(
        const PrimaryButton(label: 'Continue', onPressed: null),
      ));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });
}
