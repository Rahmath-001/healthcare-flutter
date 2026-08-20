import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    test('does not fire before the delay elapses', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(delay: const Duration(milliseconds: 500));
        d.run(() => calls++);

        async.elapse(const Duration(milliseconds: 499));
        expect(calls, 0);

        async.elapse(const Duration(milliseconds: 1));
        expect(calls, 1);
      });
    });

    test('collapses rapid calls into a single trailing invocation', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(delay: const Duration(milliseconds: 500));

        // Simulates search-as-you-type: each keystroke restarts the timer.
        for (var i = 0; i < 5; i++) {
          d.run(() => calls++);
          async.elapse(const Duration(milliseconds: 100));
        }
        expect(calls, 0, reason: 'timer restarted on every call');

        async.elapse(const Duration(milliseconds: 500));
        expect(calls, 1);
      });
    });

    test('dispose cancels a pending invocation', () {
      fakeAsync((async) {
        var calls = 0;
        final d = Debouncer(delay: const Duration(milliseconds: 500));
        d.run(() => calls++);

        d.dispose();
        async.elapse(const Duration(seconds: 2));

        // A fire after dispose would call setState on an unmounted widget.
        expect(calls, 0);
      });
    });
  });
}
