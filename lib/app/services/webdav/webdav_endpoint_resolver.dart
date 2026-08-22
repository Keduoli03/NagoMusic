import 'package:webdav_client/webdav_client.dart' as webdav;

import 'webdav_source_repository.dart';

/// Resolves which of a WebDAV source's configured addresses (primary +
/// alternates, e.g. a LAN address at home and a remote-access tunnel while
/// away) is currently reachable, and rewrites stored URIs to point at it.
///
/// Song identity (see webdav_song_id.dart) is endpoint-agnostic, so callers
/// combine a song's stored path with whatever this resolver says is live
/// right now instead of trusting the host baked into an old stored URI.
class WebDavEndpointResolver {
  WebDavEndpointResolver._internal();

  static final WebDavEndpointResolver instance =
      WebDavEndpointResolver._internal();

  static const _probeTimeoutMs = 4000;
  static const _cacheTtl = Duration(seconds: 45);

  final Map<String, _CachedEndpoint> _cache = {};
  final Map<String, Future<String?>> _inflight = {};

  /// Drops the cached "known good" endpoint for [sourceId], forcing the next
  /// [resolveActiveEndpoint] call to re-probe every configured address.
  void invalidate(String sourceId) => _cache.remove(sourceId);

  /// Returns the first reachable endpoint for [source] (its own list of
  /// addresses, primary first), preferring the last-known-good one if it's
  /// still within its cache TTL. If none answer, falls back to the primary
  /// endpoint so callers still get a best-effort URL instead of null.
  Future<String?> resolveActiveEndpoint(
    WebDavSource source, {
    bool forceRefresh = false,
  }) async {
    final endpoints = source.allEndpoints;
    if (endpoints.isEmpty) return null;
    if (endpoints.length == 1) return endpoints.first;

    if (!forceRefresh) {
      final cached = _cache[source.id];
      if (cached != null &&
          !cached.isExpired &&
          endpoints.contains(cached.endpoint)) {
        return cached.endpoint;
      }
    }

    final existingInflight = _inflight[source.id];
    if (existingInflight != null) return existingInflight;

    final future = _probeAll(source, endpoints);
    _inflight[source.id] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(source.id);
    }
  }

  Future<String?> _probeAll(
    WebDavSource source,
    List<String> endpoints,
  ) async {
    final headers = WebDavSourceRepository.instance.buildHeaders(source);
    final probePath = source.path.trim().isEmpty ? '/' : source.path.trim();
    for (final endpoint in endpoints) {
      final ok = await _probeOne(endpoint, probePath, headers);
      if (ok) {
        _cache[source.id] = _CachedEndpoint(endpoint, DateTime.now());
        return endpoint;
      }
    }
    return endpoints.first;
  }

  Future<bool> _probeOne(
    String endpoint,
    String path,
    Map<String, String> headers,
  ) async {
    try {
      final client = webdav.newClient(
        endpoint,
        user: '',
        password: '',
        debug: false,
      );
      client.setHeaders(headers);
      client.setConnectTimeout(_probeTimeoutMs);
      client.setSendTimeout(_probeTimeoutMs);
      client.setReceiveTimeout(_probeTimeoutMs);
      var searchPath = path;
      if (!searchPath.startsWith('/')) searchPath = '/$searchPath';
      await client.readDir(searchPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Rewrites [originalUri]'s scheme/host/port to [targetEndpoint]'s,
  /// keeping the path and query untouched. Falls back to the original if
  /// either side fails to parse.
  Uri rewriteHost(String originalUri, String targetEndpoint) {
    final original = Uri.tryParse(originalUri);
    final target = Uri.tryParse(targetEndpoint);
    if (original == null || target == null) {
      return Uri.parse(originalUri);
    }
    return original.replace(
      scheme: target.scheme,
      host: target.host,
      port: target.hasPort ? target.port : null,
    );
  }
}

class _CachedEndpoint {
  final String endpoint;
  final DateTime resolvedAt;

  _CachedEndpoint(this.endpoint, this.resolvedAt);

  bool get isExpired =>
      DateTime.now().difference(resolvedAt) > WebDavEndpointResolver._cacheTtl;
}
