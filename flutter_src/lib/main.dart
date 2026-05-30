import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ShieldInfoApp());
}

class ShieldInfoApp extends StatelessWidget {
  const ShieldInfoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShieldInfo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3B4FD8), brightness: Brightness.light),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF3B4FD8),
            foregroundColor: Colors.white,
            elevation: 0),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B4FD8),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3B4FD8), width: 2),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(seconds: 2));
    final prefs = await SharedPreferences.getInstance();
    final realNumber = prefs.getString('realNumber');
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) =>
            realNumber != null ? const DashboardScreen() : const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF3B4FD8),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24)),
              child: const Icon(Icons.shield, size: 60, color: Color(0xFF3B4FD8)),
            ),
            const SizedBox(height: 24),
            const Text('ShieldInfo',
                style: TextStyle(color: Colors.white, fontSize: 36,
                    fontWeight: FontWeight.bold, letterSpacing: 1)),
            const SizedBox(height: 8),
            const Text('Your privacy, protected',
                style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
