import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class HttpUtils {
  /// Fetches a resource with manual redirect handling.
  /// 
  /// This method manually follows 3xx redirects (up to [maxRedirects]).
  /// If a redirect points to a different host, it automatically strips
  /// the 'Authorization' header to prevent 403 Forbidden errors (common with WebDAV -> OSS/S3).
  static Future<Response<T>> fetchWithManualRedirect<T>(
    Dio dio,
    Uri uri, {
    Options? options,
    CancelToken? cancelToken,
    int maxRedirects = 5,
  }) async {
    var currentOptions = options ?? Options();
    // Force disable auto redirects for this request
    currentOptions = currentOptions.copyWith(
      followRedirects: false,
      validateStatus: (status) => true,
    );

    var currentUri = uri;
    if (currentOptions.headers != null) {
      currentOptions = currentOptions.copyWith(
        headers: Map<String, dynamic>.from(currentOptions.headers!),
      );
    } else {
      currentOptions = currentOptions.copyWith(headers: {});
    }

    for (var i = 0; i < maxRedirects; i++) {
      if (kDebugMode) {
        debugPrint('HttpUtils: Fetching $currentUri (Attempt ${i + 1})');
      }

      try {
        final response = await dio.requestUri<T>(
          currentUri,
          options: currentOptions,
          cancelToken: cancelToken,
        );

        if (response.statusCode != null &&
            (response.statusCode! >= 300 && response.statusCode! < 400)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location != null && location.isNotEmpty) {
            final newUri = currentUri.resolve(location);
            
            // If host changed, drop Authorization header
            if (newUri.host != currentUri.host) {
              if (kDebugMode) {
                debugPrint('HttpUtils: Redirecting to different host (${newUri.host}), dropping auth headers');
              }
              currentOptions.headers?.remove(HttpHeaders.authorizationHeader);
              currentOptions.headers?.remove('Authorization');
            }
            
            currentUri = newUri;
            continue;
          }
        }
        
        return response;
      } catch (e) {
        if (i == maxRedirects - 1) rethrow;
        rethrow; 
      }
    }
    
    throw Exception('Too many redirects ($maxRedirects)');
  }
}
