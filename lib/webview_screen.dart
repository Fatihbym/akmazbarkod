import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/auth_service.dart';
import 'widgets/auth_bottom_sheet.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController controller;
  double _progress = 0;
  bool _isFirstLoad = true;
  bool _justLoggedOut = false;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setUserAgent(AuthService.customUserAgent)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _progress = 0;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _progress = 1;
            });
            if (_isFirstLoad) {
              FlutterNativeSplash.remove();
              _isFirstLoad = false;
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (_isFirstLoad) {
              FlutterNativeSplash.remove();
              _isFirstLoad = false;
            }
          },
          onNavigationRequest: (NavigationRequest request) async {
            final url = request.url;
            final uri = Uri.parse(url);
            final path = uri.path;

            // 0. Özel Linkleri (WhatsApp, Telefon, Mail vs.) Yakala
            if (!['http', 'https'].contains(uri.scheme)) {
              try {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } else {
                  debugPrint("Could not launch $url");
                }
              } catch (e) {
                debugPrint("Error launching $url: $e");
              }
              return NavigationDecision.prevent;
            }

            // 1. Çıkış Yap Bağlantısını Yakala (kullanici/cikis)
            if (path.contains('/kullanici/cikis') || path.contains('/cikis')) {
              await AuthService().logout();
              _justLoggedOut = true;
              return NavigationDecision.navigate;
            }

            // 2. Şifremi Unuttum Bağlantısını Yakala (sifremiunuttum)
            if (path.contains('/sifremiunuttum')) {
              _showAuthBottomSheet(initialTabIndex: 2);
              return NavigationDecision.prevent;
            }

            // 3. Giriş Yap veya Kayıt Ol Bağlantılarını Yakala (giris-yap / kayit-ol)
            if (path == '/giris-yap' || path == '/kayit-ol' || path.contains('/giris-yap')) {
              if (_justLoggedOut) {
                _justLoggedOut = false;
                controller.loadRequest(Uri.parse('https://shop.akmazbarkod.com/'));
                return NavigationDecision.prevent;
              }
              
              int tabIndex = (url.contains('tab=register') || path.contains('/kayit-ol')) ? 1 : 0;
              _showAuthBottomSheet(initialTabIndex: tabIndex);
              
              // Prevent getting stuck on an empty page if the redirect is blocked
              controller.loadRequest(Uri.parse('https://shop.akmazbarkod.com/'));
              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      );

    controller.loadRequest(
      Uri.parse('https://shop.akmazbarkod.com/'),
    );
  }

  void _showAuthBottomSheet({int initialTabIndex = 0}) async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AuthBottomSheet(initialTabIndex: initialTabIndex),
    );

    if (result != null && result is String) {
      // API üzerinden token geldi, token ile webview login endpointine yönlendir
      await controller.clearCache();
      await Future.delayed(const Duration(milliseconds: 500));
      await controller.loadRequest(
        Uri.parse('https://shop.akmazbarkod.com/api/webview-auth?token=$result'),
      );
    } else if (result == true) {
      // Giriş veya kayıt başarılı oldu (token dönmediyse), anasayfaya yönlendir ve yenile
      await AuthService().syncCookiesToWebView();
      await controller.clearCache();
      await Future.delayed(const Duration(milliseconds: 500));
      await controller.loadRequest(
        Uri.parse('https://shop.akmazbarkod.com/'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (await controller.canGoBack()) {
          controller.goBack();
          return;
        }

        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.orange, size: 28),
                  SizedBox(width: 10),
                  Text('Çıkış Onayı'),
                ],
              ),
              content: const Text('Uygulamadan çıkmak istediğinize emin misiniz?'),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(CupertinoIcons.xmark, color: Colors.red),
                  label: const Text('İptal', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
                TextButton.icon(
                  onPressed: () => SystemNavigator.pop(),
                  icon: const Icon(CupertinoIcons.checkmark_alt, color: Colors.green),
                  label: const Text('Çıkış', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height,
                child: WebViewWidget(controller: controller),
              ),
              if (_progress < 1.0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: Colors.transparent,
                    color: const Color(0xFF1EAAF6),
                    minHeight: 4,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
