import 'package:web/web.dart' as web;

bool webFrameIsInIFrame() {
  try {
    return web.window.self != web.window.top;
  } catch (_) {
    return true;
  }
}

void webFrameClearTopLevelQueryPreserveHash() {
  try {
    final loc = web.window.location;
    final origin = loc.origin;
    final path = loc.pathname;
    final hash = loc.hash;
    final newUrl = '$origin$path$hash';
    web.window.history.replaceState(null, '', newUrl);
  } catch (_) {}
}

void webFrameReplaceHistoryState(String url) {
  try {
    web.window.history.replaceState(null, '', url);
  } catch (_) {}
}
