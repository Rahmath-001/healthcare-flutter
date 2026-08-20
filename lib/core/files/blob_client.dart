import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error/failure.dart';

/// Transfers file bytes to and from object storage.
///
/// Deliberately **not** the `ApiClient`. Signed URLs point at Cloud Storage, not
/// at the MiDoctor API, and sending them through the authenticated client would
/// attach a `Bearer` token to a request bound for a third-party host — which
/// leaks the session to Google's access logs and would be rejected anyway,
/// because the signature covers the headers.
///
/// So this has no base URL, no `AuthInterceptor`, and no knowledge of sessions.
/// The URL it is handed already carries its own short-lived authority.
class BlobClient {
  BlobClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Uploads bytes to a signed URL.
  ///
  /// The `Content-Type` must match what the signature was minted for, or the
  /// storage service rejects it — which is a feature: the upload cannot claim
  /// to be something other than what the API authorised.
  Future<void> put({
    required String url,
    required Uint8List bytes,
    required String contentType,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    try {
      await _dio.put<void>(
        url,
        data: Stream.fromIterable([bytes]),
        cancelToken: cancelToken,
        onSendProgress: onProgress,
        options: Options(
          headers: {
            'Content-Type': contentType,
            Headers.contentLengthHeader: bytes.length,
          },
          // The response body is storage-service XML, never problem+json, so
          // it is not worth parsing — only the status matters.
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw _failureFor(e, 'upload');
    }
  }

  Future<Uint8List> get({required String url, CancelToken? cancelToken}) async {
    try {
      final response = await _dio.get<List<int>>(
        url,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      throw _failureFor(e, 'download');
    }
  }

  Failure _failureFor(DioException e, String what) {
    if (e.type == DioExceptionType.cancel) {
      return Failure(
        kind: FailureKind.unknown,
        message: 'File $what cancelled.',
        code: 'CANCELLED',
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return Failure(
        kind: FailureKind.network,
        message:
            'The $what did not finish. Check your connection and try again.',
        code: 'BLOB_NETWORK',
      );
    }
    // A 403 here almost always means the signed URL expired — a slow upload on
    // a poor connection outliving its fifteen minutes. Worth saying plainly,
    // because "forbidden" would send the user looking for a permissions problem
    // they do not have.
    final status = e.response?.statusCode ?? 0;
    if (status == 403 || status == 401) {
      return Failure(
        kind: FailureKind.validation,
        message: 'That took too long. Please try the $what again.',
        code: 'BLOB_URL_EXPIRED',
      );
    }
    return Failure(
      kind: FailureKind.server,
      message: 'The $what failed. Please try again.',
      code: 'BLOB_FAILED',
    );
  }
}

final blobClientProvider = Provider<BlobClient>((ref) => BlobClient());
