import 'dart:core';

void main() {
  String? current = "XSRF-TOKEN=old_token";
  String incoming = "XSRF-TOKEN=new_token; expires=Wed, 29 Jul 2026 11:24:51 GMT; Max-Age=7200; path=/; secure; samesite=none, bym_b2c_session=new_session_val; expires=Wed, 29 Jul 2026 11:24:51 GMT; Max-Age=7200; path=/; secure; httponly; samesite=none, remember_web_59ba36addc2b2f9401580f014c7f58ea4e30989d=eyJpdiI6IkhjS...; expires=Wed, 29-Jul-2026 10:48:58 GMT; Max-Age=31536000; path=/; secure; httponly; samesite=lax";

  Map<String, String> cookiesMap = {};

  void parseAndAdd(String? str, bool isSetCookieHeader) {
    if (str == null || str.isEmpty) return;
    if (isSetCookieHeader) {
      final safeIncoming = str.replaceAll(
          RegExp(r'(?<!Mon|Tue|Wed|Thu|Fri|Sat|Sun),\s*', caseSensitive: false),
          '|||');
      final chunks = safeIncoming.split('|||');

      for (var chunk in chunks) {
        final parts = chunk.split(';');
        if (parts.isNotEmpty) {
          final firstPart = parts.first.trim();
          final eqIdx = firstPart.indexOf('=');
          if (eqIdx != -1) {
            final key = firstPart.substring(0, eqIdx).trim();
            final val = firstPart.substring(eqIdx + 1).trim();
            final lowerKey = key.toLowerCase();
            if (key.isNotEmpty &&
                !['expires', 'path', 'domain', 'max-age', 'secure', 'httponly', 'samesite']
                    .contains(lowerKey)) {
              cookiesMap[key] = val;
            }
          }
        }
      }
    }
  }

  parseAndAdd(current, false);
  parseAndAdd(incoming, true);

  final merged = cookiesMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
  print("Merged: $merged");
}
