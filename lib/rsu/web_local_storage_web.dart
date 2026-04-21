import 'package:web/web.dart' as web;

/// Web implementation backed by `window.localStorage`.
class WebLocalStorage {
  const WebLocalStorage();

  static const instance = WebLocalStorage();

  web.Storage? get _storage => web.window.localStorage;

  String? getItem(String key) => _storage?.getItem(key);

  void setItem(String key, String value) => _storage?.setItem(key, value);

  void removeItem(String key) => _storage?.removeItem(key);
}
