import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthcare_mobile/core/network/refresh_coordinator.dart';

void main() {
  group('RefreshCoordinator', () {
    test('ten concurrent callers trigger exactly one refresh', () async {
      var refreshCount = 0;
      final gate = Completer<void>();
      final coordinator = RefreshCoordinator();

      Future<void> refresh() async {
        refreshCount++;
        await gate.future;
      }

      // Fire ten callers before the first refresh completes — this is the
      // scenario that revokes a session family if refresh is not single-flight.
      final callers = List.generate(10, (_) => coordinator.run(refresh));

      expect(refreshCount, 1);
      expect(coordinator.isRefreshing, isTrue);

      gate.complete();
      await Future.wait(callers);

      expect(refreshCount, 1);
      expect(coordinator.isRefreshing, isFalse);
    });

    test('a refresh after the previous one settles runs again', () async {
      var refreshCount = 0;
      final coordinator = RefreshCoordinator();

      Future<void> refresh() async {
        refreshCount++;
      }

      await coordinator.run(refresh);
      await coordinator.run(refresh);

      expect(refreshCount, 2);
    });

    test('failure propagates to every awaiting caller and clears the slot',
        () async {
      var refreshCount = 0;
      final gate = Completer<void>();
      final coordinator = RefreshCoordinator();

      Future<void> failing() async {
        refreshCount++;
        await gate.future;
        throw StateError('refresh rejected');
      }

      final a = coordinator.run(failing);
      final b = coordinator.run(failing);

      expect(refreshCount, 1);

      gate.completeError(StateError('refresh rejected'));

      await expectLater(a, throwsStateError);
      await expectLater(b, throwsStateError);

      // The slot must be released, otherwise every later request is stuck
      // awaiting a future that already failed.
      expect(coordinator.isRefreshing, isFalse);

      await coordinator.run(() async => refreshCount++);
      expect(refreshCount, 2);
    });
  });
}
