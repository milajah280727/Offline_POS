import 'package:flutter/material.dart';
import 'package:kastra/login.dart';
import 'package:kastra/services.dart';
import 'package:kastra/theme.dart';
import 'package:kastra/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DB.init();
  runApp(const Kastra());
}

class Kastra extends StatelessWidget {
  const Kastra({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Kastra',
        theme: appTheme,
        home: const Splash(), // ganti dari const Splash()
      );
}

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await Future.delayed(const Duration(milliseconds: 800));
    Widget home = const LoginPage();
    final uid = DB.session;
    if (uid != null) {
      final u = await DB.getUser(uid);
      if (u != null && (u['is_active'] ?? true)) {
        home = dashboardFor(u['role'].toString().toLowerCase(), uid);
      } else {
        await DB.clearSession();
      }
    }
    if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => home));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/icons/image.png', width: 88),
            const SizedBox(height: 12),
            const Text('KASTRA',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 5, color: C.primary)),
            const SizedBox(height: 24),
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: C.primary)),
          ]),
        ),
      );
}