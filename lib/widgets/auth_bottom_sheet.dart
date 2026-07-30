import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Arka Plan Çizgi Animasyon Motoru (bymcloud projesinden kopyalandı)
class BackgroundLinesPainter extends CustomPainter {
  final Animation<double>? animation;

  BackgroundLinesPainter({this.animation}) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF1EAAF6).withValues(alpha: 0.08)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final circlePaint = Paint()
      ..color = const Color(0xFF1EAAF6).withValues(alpha: 0.055)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const double step = 35.0;
    final double shift = (animation?.value ?? 0.0) * step;

    for (double i = -size.height - (step * 2); i < size.width + (step * 2); i += step) {
      final double currentX = i + shift;
      canvas.drawLine(
        Offset(currentX, 0),
        Offset(currentX + size.height, size.height),
        linePaint,
      );
    }

    final double pulse = (animation?.value ?? 0.0) * 12.0;

    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 100 + pulse, circlePaint);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 180 + pulse, circlePaint);
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.1), 260 + pulse, circlePaint);

    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), 140 - pulse, circlePaint);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.85), 220 - pulse, circlePaint);
  }

  @override
  bool shouldRepaint(covariant BackgroundLinesPainter oldDelegate) => true;
}

class AuthBottomSheet extends StatefulWidget {
  final int initialTabIndex;
  const AuthBottomSheet({super.key, this.initialTabIndex = 0});

  @override
  State<AuthBottomSheet> createState() => _AuthBottomSheetState();
}

enum ForgotPasswordStep { email, code, reset }

class _AuthBottomSheetState extends State<AuthBottomSheet> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _animController;
  late bool _showForgotPasswordView;

  static const Color primaryThemeColor = Color(0xFF1EAAF6);

  // Login controllers
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  bool _loginRememberMe = false;
  bool _isLoading = false;
  bool _obscureLoginPassword = true;

  // Register controllers
  final _regNameController = TextEditingController();
  final _regEmailController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regPasswordConfirmController = TextEditingController();
  bool _obscureRegPassword = true;
  bool _obscureRegPasswordConfirm = true;

  // Forgot password controllers & state
  ForgotPasswordStep _forgotPasswordStep = ForgotPasswordStep.email;
  final _forgotEmailController = TextEditingController();
  final _forgotCodeController = TextEditingController();
  final _forgotNewPasswordController = TextEditingController();
  final _forgotNewPasswordConfirmController = TextEditingController();
  bool _obscureForgotNewPassword = true;
  bool _obscureForgotNewPasswordConfirm = true;

  @override
  void initState() {
    super.initState();
    _showForgotPasswordView = (widget.initialTabIndex == 2);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    int tabIndex = widget.initialTabIndex == 1 ? 1 : 0;
    _tabController = TabController(
      length: 2, 
      vsync: this, 
      initialIndex: tabIndex,
    );
    
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('saved_email');
    final savedPassword = prefs.getString('saved_password');
    if (savedEmail != null && savedEmail.isNotEmpty && savedPassword != null && savedPassword.isNotEmpty) {
      if (mounted) {
        setState(() {
          _loginEmailController.text = savedEmail;
          _loginPasswordController.text = savedPassword;
          _loginRememberMe = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _tabController.dispose();
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _regNameController.dispose();
    _regEmailController.dispose();
    _regPasswordController.dispose();
    _regPasswordConfirmController.dispose();
    _forgotEmailController.dispose();
    _forgotCodeController.dispose();
    _forgotNewPasswordController.dispose();
    _forgotNewPasswordConfirmController.dispose();
    super.dispose();
  }

  void _showToast(String message, {bool isSuccess = false}) {
    if (!mounted) return;
    
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 50.0,
        left: 20.0,
        right: 20.0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            decoration: BoxDecoration(
              color: isSuccess ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(8.0),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10.0,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        overlayEntry.remove();
      }
    });
  }

  void _toggleForgotPasswordView(bool show) {
    setState(() {
      _showForgotPasswordView = show;
    });
  }

  Future<void> _handleLogin() async {
    if (_loginEmailController.text.isEmpty || _loginPasswordController.text.isEmpty) {
      _showToast('Lütfen tüm alanları doldurun.');
      return;
    }

    setState(() => _isLoading = true);
    
    final result = await AuthService().login(
      _loginEmailController.text, 
      _loginPasswordController.text,
      rememberMe: _loginRememberMe
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (result == true || (result != null && result is String)) {
        final prefs = await SharedPreferences.getInstance();
        if (_loginRememberMe) {
          await prefs.setString('saved_email', _loginEmailController.text);
          await prefs.setString('saved_password', _loginPasswordController.text);
        } else {
          await prefs.remove('saved_email');
          await prefs.remove('saved_password');
        }
        if (mounted) {
          Navigator.of(context).pop(result);
        }
      } else {
        _showToast('Giriş başarısız. Lütfen bilgilerinizi kontrol edin.');
      }
    }
  }

  Future<void> _handleRegister() async {
    if (_regNameController.text.isEmpty || 
        _regEmailController.text.isEmpty || 
        _regPasswordController.text.isEmpty || 
        _regPasswordConfirmController.text.isEmpty) {
      _showToast('Lütfen tüm alanları doldurun.');
      return;
    }

    if (_regPasswordController.text != _regPasswordConfirmController.text) {
      _showToast('Şifreler eşleşmiyor.');
      return;
    }

    setState(() => _isLoading = true);

    final result = await AuthService().register({
      'name': _regNameController.text,
      'email': _regEmailController.text,
      'password': _regPasswordController.text,
      'password_confirmation': _regPasswordConfirmController.text,
    });

    if (mounted) {
      setState(() => _isLoading = false);
      if (result == true || (result != null && result is String)) {
        Navigator.of(context).pop(result);
      } else {
        _showToast('Kayıt başarısız oldu. Bilgileri kontrol edip tekrar deneyin.');
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_forgotEmailController.text.isEmpty) {
      _showToast('Lütfen e-posta adresinizi giriniz.');
      return;
    }

    setState(() => _isLoading = true);

    final success = await AuthService().forgotPassword(_forgotEmailController.text);

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _showToast('Doğrulama kodu e-posta adresinize gönderildi.', isSuccess: true);
        setState(() => _forgotPasswordStep = ForgotPasswordStep.code);
      } else {
        _showToast('Şifre sıfırlama isteği başarısız oldu. E-posta adresinizi kontrol edin.');
      }
    }
  }

  Future<void> _handleVerifyCode() async {
    if (_forgotCodeController.text.length < 6) {
      _showToast('Lütfen 6 haneli doğrulama kodunu giriniz.');
      return;
    }

    setState(() => _isLoading = true);

    final success = await AuthService().verifyForgotPasswordCode(
      _forgotEmailController.text, 
      _forgotCodeController.text
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _showToast('Kod doğrulandı. Yeni şifrenizi belirleyin.', isSuccess: true);
        setState(() => _forgotPasswordStep = ForgotPasswordStep.reset);
      } else {
        _showToast('Doğrulama başarısız. Girdiğiniz kod hatalı veya süresi dolmuş olabilir.');
      }
    }
  }

  Future<void> _handleResetPassword() async {
    if (_forgotNewPasswordController.text.isEmpty || _forgotNewPasswordConfirmController.text.isEmpty) {
      _showToast('Lütfen tüm şifre alanlarını doldurunuz.');
      return;
    }

    if (_forgotNewPasswordController.text != _forgotNewPasswordConfirmController.text) {
      _showToast('Şifreler eşleşmiyor.');
      return;
    }

    setState(() => _isLoading = true);

    final success = await AuthService().resetPassword(
      _forgotNewPasswordController.text,
      _forgotNewPasswordConfirmController.text,
    );

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _showToast('Şifreniz başarıyla değiştirildi. Şimdi giriş yapabilirsiniz.', isSuccess: true);
        
        // Reset state & go back to login tab
        _forgotEmailController.clear();
        _forgotCodeController.clear();
        _forgotNewPasswordController.clear();
        _forgotNewPasswordConfirmController.clear();
        setState(() => _forgotPasswordStep = ForgotPasswordStep.email);
        _toggleForgotPasswordView(false);
      } else {
        _showToast('Şifre değiştirme işlemi başarısız oldu.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 24, spreadRadius: 6),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Arka Plan Gradyan Yapılandırması
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEDF2F7), Color(0xFFF8FAFC), Color(0xFFFFFFFF)],
                ),
              ),
            ),
          ),

          // Arka Plan Çizgi Animasyon Yapılandırması (bymcloud projesinden)
          Positioned.fill(
            child: CustomPaint(
              painter: BackgroundLinesPainter(animation: _animController),
            ),
          ),

          // İçerik
          Padding(
            padding: const EdgeInsets.only(
              left: 24, 
              right: 24, 
              top: 16, 
              bottom: 24
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Animasyonlu Görünüm Geçişi (Giriş/Kayıt vs. Şifremi Unuttum)
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 350),
                  crossFadeState: _showForgotPasswordView 
                      ? CrossFadeState.showSecond 
                      : CrossFadeState.showFirst,
                  firstChild: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          labelColor: primaryThemeColor,
                          unselectedLabelColor: Colors.grey.shade600,
                          indicatorColor: primaryThemeColor,
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          tabs: const [
                            Tab(text: 'Giriş Yap'),
                            Tab(text: 'Kayıt Ol'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.48, 
                        child: TabBarView(
                          controller: _tabController,
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _buildLoginTab(),
                            _buildRegisterTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  secondChild: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.55,
                    child: _buildForgotPasswordTab(),
                  ),
                ),

                const SizedBox(height: 12),
                // Sayfaları takip eden versiyon bilgisi
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'v1.0.0 | web v26.7.1',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCustomTextField(
            hintText: 'E-Posta',
            controller: _loginEmailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
          ),
          const SizedBox(height: 16),
          _buildCustomTextField(
            hintText: 'Şifre',
            controller: _loginPasswordController,
            obscureText: _obscureLoginPassword,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(_obscureLoginPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
              onPressed: () => setState(() => _obscureLoginPassword = !_obscureLoginPassword),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: _loginRememberMe,
                activeColor: primaryThemeColor,
                onChanged: (val) => setState(() => _loginRememberMe = val ?? false),
              ),
              const Text('Beni hatırla', style: TextStyle(fontSize: 14)),
              const Spacer(),
              TextButton(
                onPressed: () => _toggleForgotPasswordView(true),
                child: const Text('Şifremi Unuttum', style: TextStyle(color: primaryThemeColor, fontWeight: FontWeight.w600)),
              )
            ],
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryThemeColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading 
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Giriş Yap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCustomTextField(
            hintText: 'Ad Soyad',
            controller: _regNameController,
            prefixIcon: Icons.person_outline,
          ),
          const SizedBox(height: 16),
          _buildCustomTextField(
            hintText: 'E-Posta',
            controller: _regEmailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
          ),
          const SizedBox(height: 16),
          _buildCustomTextField(
            hintText: 'Şifre',
            controller: _regPasswordController,
            obscureText: _obscureRegPassword,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(_obscureRegPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
              onPressed: () => setState(() => _obscureRegPassword = !_obscureRegPassword),
            ),
          ),
          const SizedBox(height: 16),
          _buildCustomTextField(
            hintText: 'Yeni Şifreyi Tekrar Girin',
            controller: _regPasswordConfirmController,
            obscureText: _obscureRegPasswordConfirm,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(_obscureRegPasswordConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
              onPressed: () => setState(() => _obscureRegPasswordConfirm = !_obscureRegPasswordConfirm),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryThemeColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isLoading ? null : _handleRegister,
            child: _isLoading 
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Kayıt Ol', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotPasswordTab() {
    switch (_forgotPasswordStep) {
      case ForgotPasswordStep.email:
        return _buildForgotPasswordEmailStep();
      case ForgotPasswordStep.code:
        return _buildForgotPasswordCodeStep();
      case ForgotPasswordStep.reset:
        return _buildForgotPasswordResetStep();
    }
  }

  Widget _buildForgotPasswordEmailStep() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_reset_rounded, size: 48, color: primaryThemeColor),
          const SizedBox(height: 10),
          const Text(
            'Şifremi Unuttum',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Text(
            'Şifrenizi sıfırlamak için lütfen e-posta adresinizi giriniz.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          _buildCustomTextField(
            hintText: 'E-Posta',
            controller: _forgotEmailController,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: Icons.email_outlined,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryThemeColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isLoading ? null : _handleForgotPassword,
            icon: _isLoading 
                ? const SizedBox.shrink()
                : const Icon(Icons.send_rounded, size: 18),
            label: _isLoading 
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Gönder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              _toggleForgotPasswordView(false);
              setState(() => _forgotPasswordStep = ForgotPasswordStep.email);
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 16, color: primaryThemeColor),
            label: const Text(
              'Giriş Sayfasına Geri Dön',
              style: TextStyle(color: primaryThemeColor, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotPasswordCodeStep() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.verified_user_outlined, size: 48, color: primaryThemeColor),
          const SizedBox(height: 10),
          const Text(
            'Doğrulama Kodu',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Text(
            'E-posta adresinize gönderilen 6 haneli doğrulama kodunu girin.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          _buildCustomTextField(
            label: '',
            hintText: '000000',
            controller: _forgotCodeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 16.0, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryThemeColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isLoading ? null : _handleVerifyCode,
            icon: _isLoading 
                ? const SizedBox.shrink()
                : const Icon(Icons.check_circle_outline, size: 18),
            label: _isLoading 
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Doğrula', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              setState(() => _forgotPasswordStep = ForgotPasswordStep.email);
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 16, color: primaryThemeColor),
            label: const Text(
              'Geri Dön',
              style: TextStyle(color: primaryThemeColor, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotPasswordResetStep() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.lock_outline, size: 48, color: primaryThemeColor),
          const SizedBox(height: 10),
          const Text(
            'Şifre Değiştir',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 6),
          Text(
            'Lütfen yeni şifrenizi belirleyin.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          _buildCustomTextField(
            hintText: 'Yeni Şifre',
            controller: _forgotNewPasswordController,
            obscureText: _obscureForgotNewPassword,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(_obscureForgotNewPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
              onPressed: () => setState(() => _obscureForgotNewPassword = !_obscureForgotNewPassword),
            ),
          ),
          const SizedBox(height: 16),
          _buildCustomTextField(
            hintText: 'Yeni Şifreyi Tekrar Girin',
            controller: _forgotNewPasswordConfirmController,
            obscureText: _obscureForgotNewPasswordConfirm,
            prefixIcon: Icons.lock_outline,
            suffixIcon: IconButton(
              icon: Icon(_obscureForgotNewPasswordConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey),
              onPressed: () => setState(() => _obscureForgotNewPasswordConfirm = !_obscureForgotNewPasswordConfirm),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryThemeColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _isLoading ? null : _handleResetPassword,
            icon: _isLoading 
                ? const SizedBox.shrink()
                : const Icon(Icons.save_outlined, size: 18),
            label: _isLoading 
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Kaydet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomTextField({
    String? label,
    String? hintText,
    required TextEditingController controller,
    IconData? prefixIcon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    int? maxLength,
    TextAlign textAlign = TextAlign.start,
    TextStyle? style,
    String counterText = "",
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null && label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLength: maxLength,
          textAlign: textAlign,
          style: style,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 15),
            counterText: counterText,
            prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: primaryThemeColor) : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), 
              borderSide: BorderSide(color: Colors.grey.shade200)
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16), 
              borderSide: const BorderSide(color: primaryThemeColor, width: 2)
            ),
          ),
        ),
      ],
    );
  }
}
