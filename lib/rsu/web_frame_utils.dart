import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class WebFrameUtils {
  static bool get isInIFrame {
    if (!kIsWeb) return false;
    try {
      return web.window.self != web.window.top;
    } catch (_) {
      return true;
    }
  }

  /// Clears the *top-level* query string while keeping the hash route intact.
  ///
  /// This is important for OAuth on Dreamflow web deployments because providers can redirect to:
  /// `/?code=...&state=...#/login`.
  /// If we leave `?code=...` in the URL, a refresh can re-trigger routing logic.
  static void clearTopLevelQueryPreserveHash() {
    if (!kIsWeb) return;
    try {
      final loc = web.window.location;
      final origin = loc.origin;
      final path = loc.pathname;
      final hash = loc.hash; // includes leading '#', may be empty
      final newUrl = '$origin$path$hash';
      web.window.history.replaceState(null, '', newUrl);
    } catch (_) {
      // Ignore; URL cleanup is a best-effort improvement.
    }
  }
}
