import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/toko.dart';
import 'package:kastra/widgets.dart';

// ignore_for_file: deprecated_member_use, use_build_context_synchronously

// ---------------------------------------------------------------------------
// DESIGN TOKENS (diselaraskan dengan biru Kastra)
// ---------------------------------------------------------------------------
const Color kPrimary = Color(0xFF5F85DA);
const Color kPrimaryDark = Color(0xFF3F63B8);
const Color kSky = Color(0xFF9FBCEF);
const Color kInk = Color(0xFF0F172A);
const Color kSub = Color(0xFF64748B);
const Color kLabel = Color(0xFF334155);
const Color kIconIdle = Color(0xFF94A3B8);
const Color kBorder = Color(0xFFE2E8F0);
const Color kFieldFill = Color(0xFFF8FAFC);
const Color kFieldFocus = Color(0xFFF5F9FF);

// Geometri gelombang — dipakai BERSAMA oleh header login dan painter
// transisi, agar krest overlay di t=0 identik dengan gelombang header.
const double kHeaderH = 290;
const double kMainBase = .78;
const double kBackBase = .68;
const double kMainAmp = kHeaderH * .05; // 14.5
const double kBackAmp = kHeaderH * .04; // 11.6

/// Timeline transisi (milidetik).
class WaveTimeline {
  WaveTimeline._();
  static const int cover = 900;      // gelombang turun menutup layar
  static const int welcomeIn = 350;  // teks selamat datang muncul
  static const int hold = 500;       // teks bertahan
  static const int welcomeOut = 350; // teks menghilang
  static const int reveal = 650;     // air memudar, dashboard terungkap
  static const int total = cover + welcomeIn + hold + welcomeOut + reveal;

  static double get coverEnd => cover * 1.0;
  static double get welcomeInEnd => coverEnd + welcomeIn;
  static double get holdEnd => welcomeInEnd + hold;
  static double get welcomeOutEnd => holdEnd + welcomeOut;
  static double get revealStart => welcomeOutEnd;
}

/// "Jam gelombang" global — header login menulis fase gelombangnya,
/// painter transisi membacanya agar gerakan air tersinkron.
class WavePhase {
  WavePhase._();
  static final ValueNotifier<double> notifier = ValueNotifier(0);
}

// ===========================================================================
// TRANSISI GELOMBANG — cover → welcome-in → hold → welcome-out → reveal.
// ===========================================================================
class WaveRoute<T> extends PageRouteBuilder<T> {
  WaveRoute({required WidgetBuilder builder})
      : super(
          transitionDuration: const Duration(milliseconds: WaveTimeline.total),
          reverseTransitionDuration: const Duration(milliseconds: WaveTimeline.total),
          opaque: false, // halaman login tetap tergambar di bawah
          pageBuilder: (context, animation, secondaryAnimation) => builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              _WaveTransition(animation: animation, child: child),
        );
}

class _WaveTransition extends StatelessWidget {
  const _WaveTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  static const Curve _cubic = Curves.easeInOutCubic;
  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static double _clamp01(double v) => v.clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, WavePhase.notifier]),
      builder: (context, _) {
        final t = animation.value;
        final double elapsed = t * WaveTimeline.total;

        double coverP = 1;
        double welcomeOpacity = 0;
        double welcomeSlide = 0;
        double waterOpacity = 1;
        double settleP = 0;

        if (elapsed < WaveTimeline.coverEnd) {
          coverP = _cubic.transform(elapsed / WaveTimeline.cover);
        } else if (elapsed < WaveTimeline.welcomeInEnd) {
          final p = (elapsed - WaveTimeline.coverEnd) / WaveTimeline.welcomeIn;
          welcomeOpacity = Curves.easeOut.transform(p);
          welcomeSlide = Curves.easeOutCubic.transform(p);
        } else if (elapsed < WaveTimeline.holdEnd) {
          welcomeOpacity = 1;
          welcomeSlide = 1;
        } else if (elapsed < WaveTimeline.welcomeOutEnd) {
          final p = (elapsed - WaveTimeline.holdEnd) / WaveTimeline.welcomeOut;
          welcomeOpacity = Curves.easeIn.transform(1 - p);
          welcomeSlide = 1 - Curves.easeInCubic.transform(p);
        } else {
          final p = _cubic.transform((elapsed - WaveTimeline.revealStart) / WaveTimeline.reveal);
          waterOpacity = 1 - p;
          settleP = p;
        }

        final bool showChild = elapsed >= WaveTimeline.coverEnd;
        final size = MediaQuery.of(context).size;
        final double maxDev = kMainAmp * 1.35 + 20;
        final double mainY = _lerp(kHeaderH * kMainBase, size.height + maxDev, coverP);
        final double backY = mainY - 29;

        return Stack(
          fit: StackFit.expand,
          children: [
            Visibility(visible: showChild, maintainState: true, child: child),

            // --- TEKS SELAMAT DATANG ---
            if (welcomeOpacity > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(0, 26 * (1 - welcomeSlide)),
                      child: Opacity(
                        opacity: welcomeOpacity,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(.16),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Icon(Icons.point_of_sale, color: Colors.white, size: 30),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Selamat Datang',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -.4,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Menyiapkan Kastra…',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withOpacity(.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // --- AIR ---
            if (waterOpacity > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: waterOpacity,
                    child: Transform.translate(
                      offset: Offset(0, 40 * settleP),
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _GrowingWavePainter(
                            mainY: mainY,
                            backY: backY,
                            phase: WavePhase.notifier.value,
                            foamAlpha: _clamp01(coverP * 2.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Dua lapis gelombang dengan rumus yang sama dengan header login.
class _GrowingWavePainter extends CustomPainter {
  _GrowingWavePainter({
    required this.mainY,
    required this.backY,
    required this.phase,
    required this.foamAlpha,
  });

  final double mainY;
  final double backY;
  final double phase;
  final double foamAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _wavePath(size, backY, kBackAmp, 1.45, -phase * .7, 2.4, closeToTop: true),
      Paint()..color = kSky.withOpacity(.45),
    );
    canvas.drawPath(
      _wavePath(size, mainY, kMainAmp, 1.15, phase, 0, closeToTop: true),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFF7EA2E8), kPrimary, kPrimaryDark],
        ).createShader(Offset.zero & size),
    );

    if (foamAlpha > 0) {
      Path crestLine() => _wavePath(size, mainY, kMainAmp, 1.15, phase, 0, closeToTop: false);
      canvas.drawPath(
        crestLine(),
        Paint()
          ..color = Colors.white.withOpacity(.55 * foamAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        crestLine()..shift(const Offset(0, 14)),
        Paint()
          ..color = Colors.white.withOpacity(.12 * foamAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7,
      );
    }
  }

  Path _wavePath(Size size, double yMean, double amp, double freq, double phase, double seed,
      {required bool closeToTop}) {
    final path = Path();
    const steps = 64;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final y = yMean - amp * math.sin(t * freq * 2 * math.pi + phase + seed);
      if (i == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(t * size.width, y);
      }
    }
    if (closeToTop) {
      path
        ..lineTo(size.width, -200)
        ..lineTo(-2, -200)
        ..close();
    }
    return path;
  }

  @override
  bool shouldRepaint(_GrowingWavePainter old) =>
      old.mainY != mainY || old.backY != backY || old.phase != phase || old.foamAlpha != foamAlpha;
}

// ===========================================================================
// HALAMAN LOGIN
// ===========================================================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  late final AnimationController _waveCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();

  // Satu controller untuk SEMUA entrance: konten header + form (stagger).
  late final AnimationController _enterCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..forward();

  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userFocus = FocusNode();
  final _passFocus = FocusNode();

  bool _obscure = true;
  bool _remember = true;
  bool _loading = false;
  String? _userError;
  String? _passError;

  @override
  void initState() {
    super.initState();
    _userFocus.addListener(_refresh);
    _passFocus.addListener(_refresh);
    _waveCtrl.addListener(_broadcastPhase);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }

  void _broadcastPhase() => WavePhase.notifier.value = _waveCtrl.value * 2 * math.pi;
  void _refresh() => setState(() {});

  @override
  void dispose() {
    _waveCtrl.removeListener(_broadcastPhase);
    _waveCtrl.dispose();
    _enterCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _userFocus.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();

    final username = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    setState(() {
      _userError = username.isEmpty ? 'Username masih kosong.' : null;
      _passError = pass.isEmpty ? 'Kata sandi masih kosong.' : null;
    });
    if (_userError != null || _passError != null) return;

    setState(() => _loading = true);
    final user = await DB.login(username, pass);
    if (!mounted) return;

    if (user == null) {
      setState(() => _loading = false);
      _toast('Username atau password salah');
      return;
    }

    final id = user['id_user'] as int;
    final role = user['role'].toString().toLowerCase();

    // "Ingat saya": centang = sesi disimpan (auto-login), tidak = sesi dihapus.
    if (_remember) {
      await DB.saveSession(id);
    } else {
      await DB.clearSession();
    }
    await DB.log(id, '${user['nama_lengkap']} ($role) login pada ${fdate(DateTime.now())}');
    if (!mounted) return;

    HapticFeedback.mediumImpact();
    Navigator.of(context).pushReplacement(
      WaveRoute<void>(builder: (_) => dashboardFor(role, id)),
    );

    // Setelah layar tertutup air penuh: hentikan animasi header (halaman
    // login tak terlihat lagi) & kembalikan ikon status bar ke gelap
    // (dashboard ber-AppBar putih).
    Future.delayed(const Duration(milliseconds: WaveTimeline.cover + 200), () {
      if (!mounted) return;
      _waveCtrl.stop();
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      );
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kInk,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          content: Text(
            message,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _FadeUp(
                          controller: _enterCtrl,
                          interval: const Interval(.32, .60, curve: Curves.easeOutCubic),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _AuthField(
                                label: 'Username',
                                hint: 'Masukkan username',
                                icon: Icons.person_outline_rounded,
                                controller: _userCtrl,
                                focusNode: _userFocus,
                                textInputAction: TextInputAction.next,
                                errorText: _userError,
                                onSubmitted: (_) => _passFocus.requestFocus(),
                                onChanged: (_) {
                                  if (_userError != null) setState(() => _userError = null);
                                },
                              ),
                              const SizedBox(height: 16),
                              _AuthField(
                                label: 'Kata Sandi',
                                hint: 'Masukkan kata sandi',
                                icon: Icons.lock_outline_rounded,
                                controller: _passCtrl,
                                focusNode: _passFocus,
                                obscure: _obscure,
                                onToggleObscure: () => setState(() => _obscure = !_obscure),
                                textInputAction: TextInputAction.done,
                                errorText: _passError,
                                onSubmitted: (_) => _submit(),
                                onChanged: (_) {
                                  if (_passError != null) setState(() => _passError = null);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _FadeUp(
                          controller: _enterCtrl,
                          interval: const Interval(.44, .72, curve: Curves.easeOutCubic),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: Checkbox(
                                      value: _remember,
                                      onChanged: (v) {
                                        HapticFeedback.selectionClick();
                                        setState(() => _remember = v ?? false);
                                      },
                                      activeColor: kPrimary,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      side: const BorderSide(color: kBorder, width: 1.4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text('Ingat saya',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: kLabel)),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () => Navigator.push(context,
                                        MaterialPageRoute(builder: (_) => const ForgotPasswordPage())),
                                    style: TextButton.styleFrom(
                                      foregroundColor: kPrimary,
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('Lupa kata sandi?',
                                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _PrimaryButton(label: 'Masuk', loading: _loading, onTap: _submit),
                              // --- FOOTER: IMPORT & DAFTAR TOKO ---
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: OutlinedButton.icon(
                                  onPressed: () => importTokoFlow(context),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: kPrimary,
                                    side: const BorderSide(color: kPrimary, width: 1.4),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  ),
                                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                                  label: const Text('Import Data Toko',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                const Text('Belum memiliki data toko?',
                                    style: TextStyle(fontSize: 13.5, color: kSub)),
                                GestureDetector(
                                  onTap: () => Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => const RegisterTokoPage())),
                                  child: const Text(' Daftar sekarang',
                                      style: TextStyle(
                                          fontSize: 13.5, fontWeight: FontWeight.w800, color: kPrimary)),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: kHeaderH,
      width: double.infinity,
      child: Stack(
        children: [
          // 1) Gelombang — selalu terlihat, bagian dari "air".
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _waveCtrl,
                builder: (context, _) => CustomPaint(
                  painter: _WaveHeaderPainter(phase: _waveCtrl.value * 2 * math.pi),
                ),
              ),
            ),
          ),

          // 2) Konten header — entrance stagger paling awal (header → form).
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  _FadeUp(
                    controller: _enterCtrl,
                    interval: const Interval(0, .20, curve: Curves.easeOutCubic),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(.18),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.point_of_sale, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _FadeUp(
                    controller: _enterCtrl,
                    interval: const Interval(.05, .25, curve: Curves.easeOutCubic),
                    child: const Text(
                      'KASTRA',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _FadeUp(
                    controller: _enterCtrl,
                    interval: const Interval(.10, .32, curve: Curves.easeOutCubic),
                    child: const Text(
                      'Selamat Datang Kembali',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  _FadeUp(
                    controller: _enterCtrl,
                    interval: const Interval(.15, .38, curve: Curves.easeOutCubic),
                    child: Text(
                      'Masuk untuk melanjutkan perjalananmu',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(.78),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PAINTER HEADER (rumus sama dengan _GrowingWavePainter)
// ---------------------------------------------------------------------------
class _WaveHeaderPainter extends CustomPainter {
  _WaveHeaderPainter({required this.phase});
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    _drawWave(
      canvas,
      size,
      paint: Paint()..color = kSky.withOpacity(.45),
      base: kBackBase,
      amp: kBackAmp,
      freq: 1.45,
      phase: -phase * .7,
      seed: 2.4,
    );
    _drawWave(
      canvas,
      size,
      paint: Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [Color(0xFF7EA2E8), kPrimary, kPrimaryDark],
        ).createShader(Offset.zero & size),
      base: kMainBase,
      amp: kMainAmp,
      freq: 1.15,
      phase: phase,
      seed: 0,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size, {
    required Paint paint,
    required double base,
    required double amp,
    required double freq,
    required double phase,
    required double seed,
  }) {
    final path = Path();
    const steps = 64;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final y = size.height * base - amp * math.sin(t * freq * 2 * math.pi + phase + seed);
      if (i == 0) {
        path.moveTo(0, y);
      } else {
        path.lineTo(t * size.width, y);
      }
    }
    path
      ..lineTo(size.width, 0)
      ..lineTo(0, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveHeaderPainter oldDelegate) => oldDelegate.phase != phase;
}

// ---------------------------------------------------------------------------
// FIELD INPUT
// ---------------------------------------------------------------------------
class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.focusNode,
    this.obscure = false,
    this.onToggleObscure,
    this.errorText,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
  }) : keyboardType = null;

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool focused = focusNode.hasFocus;
    final bool hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: kLabel)),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            // Gaya lama: abu polos tanpa border. Error = merah muda, fokus = sedikit lebih gelap.
            color: hasError
                ? const Color(0xFFFEF2F2)
                : (focused ? const Color(0xFFE9EDF5) : const Color(0xFFF5F5F5)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: focused ? kPrimary : kIconIdle),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  onChanged: onChanged,
                  cursorColor: kPrimary,
                  cursorWidth: 1.8,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: kInk),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isCollapsed: true,
                    hintText: '...',
                    hintStyle: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w400, color: kIconIdle),
                  ),
                ),
              ),
              if (onToggleObscure != null)
                GestureDetector(
                  onTap: onToggleObscure,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 14, 0, 14),
                    child: Icon(
                      obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      size: 20,
                      color: kIconIdle,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 14, color: Color(0xFFDC2626)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    errorText!,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFFDC2626)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TOMBOL UTAMA
// ---------------------------------------------------------------------------
class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({required this.label, this.onTap, this.loading = false});

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;
  bool get _enabled => widget.onTap != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) {
          if (_enabled) setState(() => _pressed = true);
        },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _enabled ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? .98 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _pressed ? kPrimaryDark : kPrimary,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                if (!_pressed)
                  BoxShadow(
                    color: kPrimary.withOpacity(.30),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: widget.loading
                  ? const Row(
                      key: ValueKey('loading'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Memeriksa…',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    )
                  : Text(
                      widget.label,
                      key: const ValueKey('idle'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .2),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ANIMASI FADE + SLIDE (entrance stagger)
// ---------------------------------------------------------------------------
class _FadeUp extends StatelessWidget {
  const _FadeUp({required this.controller, required this.interval, required this.child});

  final Animation<double> controller;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = interval.transform(controller.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}