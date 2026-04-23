import 'package:flutter/foundation.dart';

/// Debug-only logging (no output in release builds).
void rsuDebugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
