import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/data/session_repository.dart';
import 'config/app_config.dart';
import 'network/api_client.dart';
import 'network/auth_interceptor.dart';
import 'network/refresh_coordinator.dart';
import 'session/session.dart';
import 'session/session_controller.dart';
import 'storage/secure_token_store.dart';

/// Composition root.
///
/// Everything the app depends on is declared here so tests can swap any piece
/// via `ProviderScope(overrides: [...])` without touching widget code.

/// Overridden in main() once SharedPreferences has been loaded.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('Override sharedPreferencesProvider in main()'),
);

/// Overridden in main() from package metadata.
final appVersionProvider = Provider<String>((ref) => '0.0.0');

final appConfigProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

final secureTokenStoreProvider = Provider<SecureTokenStore>(
  (ref) => SecureTokenStore(),
);

/// Stable per-install id used for the device list and per-device revocation.
///
/// Generated locally rather than read from hardware: device identifiers are
/// regulated personal data under the DPDP Act, and a random per-install value
/// serves the security purpose without collecting anything about the handset.
final deviceIdProvider = FutureProvider<String>((ref) async {
  final store = ref.watch(secureTokenStoreProvider);
  final existing = await store.readDeviceId();
  if (existing != null) return existing;

  final random = Random.secure();
  final id = List<int>.generate(16, (_) => random.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  await store.writeDeviceId(id);
  return id;
});

final refreshCoordinatorProvider = Provider<RefreshCoordinator>(
  (ref) => RefreshCoordinator(),
);

/// Bare Dio used only to replay a request after a refresh. It deliberately has
/// no [AuthInterceptor], so a replay can never recurse into another refresh.
final retryDioProvider = Provider<Dio>(
  (ref) => buildDio(ref.watch(appConfigProvider)),
);

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  return buildDio(
    config,
    interceptors: [
      AuthInterceptor(
        accessTokenProvider: () =>
            ref.read(sessionControllerProvider.notifier).accessToken,
        refresh: () =>
            ref.read(sessionControllerProvider.notifier).refreshAccessToken(),
        coordinator: ref.watch(refreshCoordinatorProvider),
        retryClient: ref.watch(retryDioProvider),
        onAuthenticationLost: () {
          ref.read(sessionControllerProvider.notifier).signOutLocally();
        },
      ),
    ],
  );
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(dio: ref.watch(dioProvider)),
);

/// Swaps to [ApiSessionRepository] once the backend is deployed.
///
/// Until then the fixture keeps the whole client architecture — router, shells,
/// interceptors, repositories — buildable and testable end to end.
final useFixturesProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('USE_FIXTURES', defaultValue: true),
);

final sessionRepositoryProvider = Provider<SessionRepository>((ref) {
  if (ref.watch(useFixturesProvider)) return FixtureSessionRepository();
  return ApiSessionRepository(ref.watch(apiClientProvider));
});

final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, Session?>(SessionController.new);

/// Convenience view of the current session, or null while loading or signed out.
final currentSessionProvider = Provider<Session?>(
  (ref) => ref.watch(sessionControllerProvider).value,
);
