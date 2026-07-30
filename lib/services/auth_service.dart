import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = 'https://shop.akmazbarkod.com';
  
  static String get customUserAgent {
    if (!kIsWeb && Platform.isIOS) {
      return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1';
    }
    return 'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.6613.127 Mobile Safari/537.36';
  }

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  String? _sessionCookie;
  bool _isLoggedIn = false;

  String? get sessionCookie => _sessionCookie;
  bool get isLoggedIn => _isLoggedIn;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _sessionCookie = prefs.getString('auth_cookie');
    
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      await validateSession();
    } else {
      await _setLoggedInState(false);
    }
  }

  Future<bool> validateSession() async {
    if (_sessionCookie == null || _sessionCookie!.isEmpty) {
      await _setLoggedInState(false);
      return false;
    }

    try {
      final request = http.Request('GET', Uri.parse('$baseUrl/giris-yap'));
      request.headers['Cookie'] = _sessionCookie!;
      request.headers['User-Agent'] = customUserAgent;
      request.followRedirects = false;

      final responseStream = await http.Client().send(request);
      final response = await http.Response.fromStream(responseStream);

      // Visiting /giris-yap as an authenticated user redirects away (302/301)
      if (response.statusCode == 302 || response.statusCode == 301 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location == null || (!location.endsWith('/giris-yap') && !location.endsWith('/giris'))) {
          await syncCookiesToWebView(_sessionCookie);
          await _setLoggedInState(true);
          return true;
        }
      }
    } catch (e) {
      debugPrint("Session validation error: $e");
    }

    // Session is expired or invalid
    await logout();
    return false;
  }

  Future<void> _setLoggedInState(bool loggedIn) async {
    _isLoggedIn = loggedIn;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_logged_in', loggedIn);
  }

  Future<void> _saveCookie(String? cookieStr) async {
    final prefs = await SharedPreferences.getInstance();
    if (cookieStr != null && cookieStr.isNotEmpty) {
      await prefs.setString('auth_cookie', cookieStr);
    } else {
      await prefs.remove('auth_cookie');
    }
  }

  String _mergeCookies(String? current, String? incoming) {
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
      } else {
        final parts = str.split(';');
        for (var p in parts) {
          final trimmed = p.trim();
          final eqIdx = trimmed.indexOf('=');
          if (eqIdx != -1) {
            final key = trimmed.substring(0, eqIdx).trim();
            final val = trimmed.substring(eqIdx + 1).trim();
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

    parseAndAdd(current, false);
    parseAndAdd(incoming, true);

    final merged = cookiesMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    debugPrint("MergeCookies Result: $merged");
    _saveCookie(merged);
    return merged;
  }

  Future<Map<String, String>?> _getCsrfTokenAndCookie(String path) async {
    try {
      final headers = <String, String>{
        'User-Agent': customUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
      };
      if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
        headers['Cookie'] = _sessionCookie!;
      }

      final response = await http.get(Uri.parse('$baseUrl$path'), headers: headers);

      if (response.statusCode == 200) {
        final html = response.body;
        
        String? token;
        final tokenMatch1 = RegExp(r'name="_token"\s+value="([^"]+)"').firstMatch(html);
        final tokenMatch2 = RegExp(r'value="([^"]+)"\s+name="_token"').firstMatch(html);
        final tokenMatch3 = RegExp(r'meta\s+name="csrf-token"\s+content="([^"]+)"').firstMatch(html);

        if (tokenMatch1 != null && tokenMatch1.groupCount >= 1) {
          token = tokenMatch1.group(1);
        } else if (tokenMatch2 != null && tokenMatch2.groupCount >= 1) {
          token = tokenMatch2.group(1);
        } else if (tokenMatch3 != null && tokenMatch3.groupCount >= 1) {
          token = tokenMatch3.group(1);
        }

        final cookies = response.headers['set-cookie'];
        if (cookies != null) {
          _sessionCookie = _mergeCookies(_sessionCookie, cookies);
        }

        if (token != null) {
          return {
            'token': token,
            'cookie': _sessionCookie ?? '',
          };
        }
      }
    } catch (e) {
      debugPrint("Error fetching CSRF token: $e");
    }
    return null;
  }

  Future<dynamic> login(String email, String password, {bool rememberMe = true}) async {
    try {
      final initData = await _getCsrfTokenAndCookie('/giris-yap');
      if (initData == null) {
        debugPrint("Login failed: Could not retrieve CSRF token.");
        return false;
      }

      final token = initData['token']!;
      final requestCookies = initData['cookie']!;

      final request = http.Request('POST', Uri.parse('$baseUrl/giris-yap'));
      request.headers.addAll({
        'Cookie': requestCookies,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': baseUrl,
        'Referer': '$baseUrl/giris-yap',
        'User-Agent': customUserAgent,
        'Accept': 'application/json',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        'X-Requested-With': 'XMLHttpRequest',
      });

      request.bodyFields = {
        '_token': token,
        'phone_ext': '',
        'website_url': '',
        'email': email.trim(),
        'password': password,
        if (rememberMe) 'remember': 'on',
      };
      request.followRedirects = false;

      final responseStream = await http.Client().send(request);
      final response = await http.Response.fromStream(responseStream);

      final newCookies = response.headers['set-cookie'];
      if (newCookies != null) {
        _sessionCookie = _mergeCookies(_sessionCookie, newCookies);
      }

      try {
        final bodyJson = jsonDecode(response.body);
        if (bodyJson != null && bodyJson is Map && bodyJson['webview_login_token'] != null) {
          final token = bodyJson['webview_login_token'].toString();
          await _setLoggedInState(true);
          return token;
        }
      } catch (e) {
        // Ignore JSON parsing errors
      }

      final location = response.headers['location'];
      debugPrint("Login POST Response Status: ${response.statusCode}, Location: $location");

      // 1. Direct redirect check on POST response
      if (response.statusCode == 302 || response.statusCode == 301 || response.statusCode == 303) {
        if (location != null && !location.endsWith('/giris-yap') && !location.endsWith('/giris')) {
          await syncCookiesToWebView(_sessionCookie);
          await _setLoggedInState(true);
          return true;
        }
      }

      // 2. Double-check auth status by GET /giris-yap with session cookie (maciter pattern)
      final checkRequest = http.Request('GET', Uri.parse('$baseUrl/giris-yap'));
      checkRequest.headers['Cookie'] = _sessionCookie ?? '';
      checkRequest.headers['User-Agent'] = customUserAgent;
      checkRequest.followRedirects = false;

      final checkResponseStream = await http.Client().send(checkRequest);
      final checkResponse = await http.Response.fromStream(checkResponseStream);
      final checkCookies = checkResponse.headers['set-cookie'];
      if (checkCookies != null) {
        _sessionCookie = _mergeCookies(_sessionCookie, checkCookies);
      }

      debugPrint("Login GET Check Response Status: ${checkResponse.statusCode}, Location: ${checkResponse.headers['location']}");

      // If visiting /giris-yap as an authenticated user redirects away (302/301), auth was successful!
      if (checkResponse.statusCode == 302 || checkResponse.statusCode == 301 || checkResponse.statusCode == 303) {
        await syncCookiesToWebView(_sessionCookie);
        await _setLoggedInState(true);
        return true;
      }

      // If still returns 200 on /giris-yap, auth failed (invalid credentials)
      await _setLoggedInState(false);
      return false;
    } catch (e) {
      debugPrint("Login error: $e");
      await _setLoggedInState(false);
      return false;
    }
  }

  Future<dynamic> register(Map<String, String> data) async {
    try {
      final initData = await _getCsrfTokenAndCookie('/kayit-ol');
      if (initData == null) return false;

      final token = initData['token']!;
      final requestCookies = initData['cookie']!;

      data['_token'] = token;
      data['phone_ext'] = '';
      data['website_url'] = '';

      final request = http.Request('POST', Uri.parse('$baseUrl/kayit-ol'));
      request.headers.addAll({
        'Cookie': requestCookies,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': baseUrl,
        'Referer': '$baseUrl/kayit-ol',
        'User-Agent': customUserAgent,
        'Accept': 'application/json',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        'X-Requested-With': 'XMLHttpRequest',
      });
      request.bodyFields = data;
      request.followRedirects = false;

      final responseStream = await http.Client().send(request);
      final response = await http.Response.fromStream(responseStream);

      final newCookies = response.headers['set-cookie'];
      if (newCookies != null) {
        _sessionCookie = _mergeCookies(_sessionCookie, newCookies);
      }

      try {
        final bodyJson = jsonDecode(response.body);
        if (bodyJson != null && bodyJson is Map && bodyJson['webview_login_token'] != null) {
          final token = bodyJson['webview_login_token'].toString();
          await _setLoggedInState(true);
          return token;
        }
      } catch (e) {
        // Ignore JSON parsing errors
      }

      if (response.statusCode == 302 || response.statusCode == 301 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location != null && !location.endsWith('/kayit-ol')) {
          await syncCookiesToWebView(_sessionCookie);
          await _setLoggedInState(true);
          return true; 
        }
      }
      return false;
    } catch (e) {
      debugPrint("Register error: $e");
      return false;
    }
  }

  Future<bool> forgotPassword(String email) async {
    try {
      final initData = await _getCsrfTokenAndCookie('/sifremiunuttum');
      if (initData == null) return false;

      final token = initData['token']!;
      final requestCookies = initData['cookie']!;

      final request = http.Request('POST', Uri.parse('$baseUrl/sifreyenile'));
      request.headers.addAll({
        'Cookie': requestCookies,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': baseUrl,
        'Referer': '$baseUrl/sifremiunuttum',
        'User-Agent': customUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
      });
      request.bodyFields = {
        '_token': token,
        'email': email.trim(),
      };
      request.followRedirects = false;

      final responseStream = await http.Client().send(request);
      final response = await http.Response.fromStream(responseStream);

      final newCookies = response.headers['set-cookie'];
      if (newCookies != null) {
        _sessionCookie = _mergeCookies(_sessionCookie, newCookies);
      }

      if (response.statusCode == 302 || response.statusCode == 301 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location != null && !location.endsWith('/sifremiunuttum')) {
          return true;
        }
      } else if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Forgot password error: $e");
      return false;
    }
  }

  Future<bool> verifyForgotPasswordCode(String email, String code) async {
    try {
      final initData = await _getCsrfTokenAndCookie('/sifredogrula');
      if (initData == null) return false;

      final token = initData['token']!;
      final requestCookies = initData['cookie']!;

      final request = http.Request('POST', Uri.parse('$baseUrl/sifredogrula'));
      request.headers.addAll({
        'Cookie': requestCookies,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': baseUrl,
        'Referer': '$baseUrl/sifredogrula',
        'User-Agent': customUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
      });
      request.bodyFields = {
        '_token': token,
        'email': email.trim(),
        'code': code.trim(),
      };
      request.followRedirects = false;

      final responseStream = await http.Client().send(request);
      final response = await http.Response.fromStream(responseStream);

      final newCookies = response.headers['set-cookie'];
      if (newCookies != null) {
        _sessionCookie = _mergeCookies(_sessionCookie, newCookies);
      }

      // Check for redirect to /sifredegistir or success
      if (response.statusCode == 302 || response.statusCode == 301 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location != null && !location.endsWith('/sifredogrula')) {
          return true;
        }
      } else if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Verify code error: $e");
      return false;
    }
  }

  Future<bool> resetPassword(String password, String passwordConfirmation) async {
    try {
      final initData = await _getCsrfTokenAndCookie('/sifredegistir');
      if (initData == null) return false;

      final token = initData['token']!;
      final requestCookies = initData['cookie']!;

      final request = http.Request('POST', Uri.parse('$baseUrl/sifremidegistir'));
      request.headers.addAll({
        'Cookie': requestCookies,
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': baseUrl,
        'Referer': '$baseUrl/sifredegistir',
        'User-Agent': customUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
      });
      request.bodyFields = {
        '_token': token,
        'password': password,
        'password_confirmation': passwordConfirmation,
      };
      request.followRedirects = false;

      final responseStream = await http.Client().send(request);
      final response = await http.Response.fromStream(responseStream);

      final newCookies = response.headers['set-cookie'];
      if (newCookies != null) {
        _sessionCookie = _mergeCookies(_sessionCookie, newCookies);
      }

      if (response.statusCode == 302 || response.statusCode == 301 || response.statusCode == 303) {
        final location = response.headers['location'];
        if (location != null && !location.endsWith('/sifredegistir')) {
          return true;
        }
      } else if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Reset password error: $e");
      return false;
    }
  }

  Future<void> logout() async {
    _sessionCookie = null;
    await _saveCookie(null);
    await _setLoggedInState(false);
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
  }

  Future<void> syncCookiesToWebView([String? customCookie]) async {
    final cookieHeader = customCookie ?? _sessionCookie;
    if (cookieHeader == null || cookieHeader.isEmpty) return;

    final cookieManager = WebViewCookieManager();
    
    final cookies = cookieHeader.split(';');
    for (var c in cookies) {
      var parts = c.trim().split('=');
      if (parts.length >= 2) {
        var name = parts[0].trim();
        var value = parts.sublist(1).join('=').trim();
        if (['expires', 'path', 'domain', 'httponly', 'secure', 'samesite'].contains(name.toLowerCase())) {
          continue;
        }
        try {
          await cookieManager.setCookie(
            WebViewCookie(
              name: name,
              value: value,
              domain: "shop.akmazbarkod.com",
              path: "/",
            ),
          );
          // Webview'in alt domainler için de çerezi alabilmesi için
          // domainin başına nokta koyarak bir kopya daha kaydediyoruz
          // Bu, bazı auth sistemlerinde gerekiyor olabilir.
          await cookieManager.setCookie(
            WebViewCookie(
              name: name,
              value: value,
              domain: ".shop.akmazbarkod.com",
              path: "/",
            ),
          );
          debugPrint("Successfully set WebView cookie: $name");
        } catch (e) {
          debugPrint("Failed to set WebView cookie $name: $e");
        }
      }
    }
  }
}
