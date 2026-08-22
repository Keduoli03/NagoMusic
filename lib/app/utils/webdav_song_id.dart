/// Extracts the path (+ query, if any) portion of a WebDAV href/uri,
/// independent of scheme/host/port. Falls back to the raw input if it isn't
/// a parseable URL.
///
/// Two addresses that serve the same directory tree (e.g. a LAN address and
/// a remote-access tunnel for the same home server) produce the same path
/// for the same file, so this is what makes song identity endpoint-agnostic.
String webdavPathOf(String hrefOrUri) {
  final trimmed = hrefOrUri.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.path.isEmpty) return trimmed;
  final query = uri.hasQuery ? '?${uri.query}' : '';
  return '${uri.path}$query';
}

/// Builds a WebDAV song id that only depends on the source and the file's
/// path on the server, not on which endpoint (host) was used to reach it.
/// This keeps ids — and everything keyed by them (favorites, play stats,
/// playlists) — stable when a source has multiple addresses that serve the
/// same directory tree.
String buildWebdavSongId({required String sourceId, required String hrefOrUri}) {
  return '$sourceId::${webdavPathOf(hrefOrUri)}';
}
