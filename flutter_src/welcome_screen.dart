import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'sync_contacts_screen.dart';
import 'dashboard_screen.dart';

class WelcomeScreen extends StatefulWidget {
  final String realNumber;
  final String maskedNumber;
  final bool isFirstTime;
  const WelcomeScreen({super.key, required this.realNumber,
      required this.maskedNumber, required this.isFirstTime});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _scaleAnim = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.maskedNumber));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _continue() {
    if (widget.isFirstTime) {
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => SyncContactsScreen(
              realNumber: widget.realNumber, isFirstTime: true)));
    } else {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const DashboardScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B5E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Shield icon animated
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B4FD8),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: const Icon(Icons.shield, size: 58, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 28),

                Text(
                  widget.isFirstTime ? 'Welcome to ShieldInfo!' : 'Welcome back!',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text('Your privacy shield is active.\nShare this number — keep your real one private.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.white60, height: 1.5)),

                const SizedBox(height: 40),

                // Masked number card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2E7A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3B4FD8), width: 1.5),
                  ),
                  child: Column(children: [
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.shield, color: Color(0xFF00C4E8), size: 16),
                      SizedBox(width: 6),
                      Text('YOUR SHIELDINFO NUMBER', style: TextStyle(
                          color: Color(0xFF00C4E8), fontSize: 11,
                          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ]),
                    const SizedBox(height: 14),
                    Text(
                      widget.maskedNumber.isEmpty ? 'Not assigned yet' : widget.maskedNumber,
                      style: const TextStyle(color: Colors.white, fontSize: 28,
                          fontWeight: FontWeight.bold, letterSpacing: 1.5),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _copy,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: _copied ? Colors.green.withOpacity(0.2) : const Color(0xFF3B4FD8).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: _copied ? Colors.green : const Color(0xFF3B4FD8),
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_copied ? Icons.check : Icons.copy,
                              color: _copied ? Colors.green : Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          Text(_copied ? 'Copied!' : 'Copy Number',
                              style: TextStyle(
                                  color: _copied ? Colors.green : Colors.white70,
                                  fontSize: 13, fontWeight: FontWeight.w500)),
                        ]),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 20),

                // Tip
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Row(children: [
                    Icon(Icons.lightbulb_outline, color: Color(0xFF00C4E8), size: 18),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                        'Share this number on OLX, Swiggy, with strangers — your real number stays hidden.',
                        style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.4))),
                  ]),
                ),

                const Spacer(),

                ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C4E8),
                    foregroundColor: const Color(0xFF0D1B5E),
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    widget.isFirstTime ? 'Set Up My Shield  →' : 'Go to Dashboard  →',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
