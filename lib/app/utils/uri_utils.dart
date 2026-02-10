
import 'package:path/path.dart' as p;

class UriUtils {
  UriUtils._();

  /// Repairs a URL string that might have broken percent escapes.
  /// Handles cases where '%' is followed by non-hex characters or incomplete sequences.
  /// Also normalizes spaces encoded as '%20' if they were double-encoded.
  static String repairUrlForBrokenPercentEscapes(String input) {
    final s = input.trim();
    if (s.isEmpty) return s;
    final sb = StringBuffer();

    bool isWs(int cu) =>
        cu == 0x20 || cu == 0x09 || cu == 0x0A || cu == 0x0D;
    bool isHex(int cu) =>
        (cu >= 0x30 && cu <= 0x39) ||
        (cu >= 0x41 && cu <= 0x46) ||
        (cu >= 0x61 && cu <= 0x66);

    var i = 0;
    while (i < s.length) {
      final cu = s.codeUnitAt(i);
      if (cu == 0x25) {
        sb.writeCharCode(cu);
        i += 1;
        var got = 0;
        while (i < s.length && got < 2) {
          final next = s.codeUnitAt(i);
          if (isWs(next)) {
            i += 1;
            continue;
          }
          if (!isHex(next)) break;
          sb.writeCharCode(next);
          got += 1;
          i += 1;
        }
        continue;
      }
      if (cu == 0x0A || cu == 0x0D || cu == 0x09) {
        i += 1;
        continue;
      }
      if (cu == 0x20) {
        sb.write('%20');
        i += 1;
        continue;
      }
      sb.writeCharCode(cu);
      i += 1;
    }
    return sb.toString();
  }

  /// Iteratively decodes a string until it no longer changes or up to [maxDepth] times.
  /// Useful for handling double/triple encoded URIs.
  static String decodeRecursive(String input, {int maxDepth = 4}) {
    var current = input;
    for (var i = 0; i < maxDepth; i++) {
      try {
        final next = Uri.decodeFull(current);
        if (next == current) break;
        current = next;
      } catch (_) {
        break;
      }
    }
    return current;
  }

  /// Parses a URI string safely, handling broken escapes and recursive decoding of path segments.
  static Uri? parseSafeUri(String uriStr) {
    final raw = repairUrlForBrokenPercentEscapes(uriStr);
    if (raw.isEmpty) return null;
    
    // Try parsing the raw string, or encoded if raw fails
    final parsed = Uri.tryParse(raw) ?? Uri.tryParse(Uri.encodeFull(raw));
    if (parsed == null) return null;

    // For HTTP/S, try to clean up the path segments
    if (parsed.isScheme('http') || parsed.isScheme('https')) {
      final segments = parsed.pathSegments.map((seg) {
        if (seg.isEmpty) return seg;
        return decodeComponentRecursive(seg);
      }).toList();
      return parsed.replace(pathSegments: segments);
    }
    
    return parsed;
  }

  /// Recursively decodes a URI component (like a path segment).
  static String decodeComponentRecursive(String input, {int maxDepth = 4}) {
    var current = input;
    for (var i = 0; i < maxDepth; i++) {
      try {
        final next = Uri.decodeComponent(current);
        if (next == current) break;
        current = next;
      } catch (_) {
        break;
      }
    }
    return current;
  }

  /// Extracts a safe, human-readable file name from a URI or file path.
  static String extractFileName(String uriStr) {
    try {
      // Decode fully first to handle encoded paths
      final decoded = decodeRecursive(uriStr);
      final name = p.basenameWithoutExtension(decoded);
      if (name.isNotEmpty && name != '/') return name;
    } catch (_) {}
    return p.basenameWithoutExtension(uriStr);
  }
}
