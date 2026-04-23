import 'package:flutter/foundation.dart';

import 'package:rsu_results/rsu/web_frame_impl_web.dart' if (dart.library.io) 'package:rsu_results/rsu/web_frame_impl_stub.dart' as impl;

class WebFrameUtils {
  static bool get isInIFrame {
    if (!kIsWeb) return false;
    try {
      return impl.webFrameIsInIFrame();
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
    impl.webFrameClearTopLevelQueryPreserveHash();
  }

  /// Replace browser history state (e.g. kiosk mode entry URL). Web only.
  static void replaceHistoryState(String url) {
    if (!kIsWeb) return;
    impl.webFrameReplaceHistoryState(url);
  }
}
