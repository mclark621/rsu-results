/// Key-value persistence used by [RsuSettingsStore] (SharedPreferences, web storage, or in-memory).
abstract class PrefsStorage {
  String? getString(String key);
  int? getInt(String key);

  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
  Future<void> remove(String key);
}
