import 'package:shared_preferences/shared_preferences.dart';

import '../data/product_lookup.dart';

class Settings {
  static const _kGs1Key = 'gs1_india_api_key';
  static const _kGs1Url = 'gs1_india_api_url';

  static Future<LookupConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_kGs1Key);
    final url = prefs.getString(_kGs1Url);
    return LookupConfig(
      gs1IndiaKey: (key != null && key.isNotEmpty) ? key : null,
      gs1IndiaUrlTemplate: (url != null && url.isNotEmpty)
          ? url
          : const LookupConfig().gs1IndiaUrlTemplate,
    );
  }

  static Future<void> save({String? gs1Key, String? gs1Url}) async {
    final prefs = await SharedPreferences.getInstance();
    if (gs1Key != null) await prefs.setString(_kGs1Key, gs1Key);
    if (gs1Url != null) await prefs.setString(_kGs1Url, gs1Url);
  }
}
