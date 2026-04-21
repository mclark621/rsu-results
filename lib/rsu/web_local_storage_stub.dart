/// Non-web stub for localStorage access.
class WebLocalStorage {
  const WebLocalStorage();

  static const instance = WebLocalStorage();

  String? getItem(String key) => null;

  void setItem(String key, String value) {}

  void removeItem(String key) {}
}
