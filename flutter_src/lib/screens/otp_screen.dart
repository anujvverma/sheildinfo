import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'dashboard_screen.dart';
import 'welcome_screen.dart';
import 'sync_contacts_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final ConfirmationResult? confirmationResult;
  final String? verificationId;
  const OtpScreen({super.key, required this.phoneNumber,
      this.confirmationResult, this.verificationId});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _ctrl = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  int _resendSeconds = 30;
  bool _resendEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) => _nodes[0].requestFocus());
  }

  void _startTimer() {
    setState(() { _resendEnabled = false; _resendSeconds = 30; });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendSeconds--);
      if (_resendSeconds <= 0) { setState(() => _resendEnabled = true); return false; }
      return true;
    });
  }

  String get _otp => _ctrl.map((c) => c.text).join();

  void _onChanged(int i, String v) {
    if (v.length > 1) {
      final digits = v.replaceAll(RegExp(r'\D'), '');
      for (int j = 0; j < digits.length && (i + j) < 6; j++) {
        _ctrl[i + j].text = digits[j];
      }
      _nodes[(i + digits.length).clamp(0, 5)].requestFocus();
    } else {
      if (v.isNotEmpty && i < 5) _nodes[i + 1].requestFocus();
      if (v.isEmpty && i > 0) _nodes[i - 1].requestFocus();
    }
    setState(() {});
    if (_otp.length == 6) _verify();
  }

  Future<void> _verify() async {
    if (_otp.length != 6) return;
    setState(() { _loading = true; _error = null; });

    try {
      UserCredential credential;
      if (widget.confirmationResult != null) {
        credential = await widget.confirmationResult!.confirm(_otp);
      } else {
        final authCredential = PhoneAuthProvider.credential(
            verificationId: widget.verificationId!, smsCode: _otp);
        credential = await FirebaseAuth.instance.signInWithCredential(authCredential);
      }

      final user = credential.user;
      if (user == null) throw Exception('Auth failed');

      // Get JWT token from backend
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('realNumber', widget.phoneNumber);
      await prefs.setString('firebaseUid', user.uid);

      final authData = await ApiService.getAuthToken(widget.phoneNumber, user.uid);
      String maskedNum = (authData?['user'] as Map<String, dynamic>?)?['maskedNumber'] ?? '';

      // Retry if masked number empty
      if (maskedNum.isEmpty) {
        await Future.delayed(const Duration(seconds: 1));
        final retryData = await ApiService.getUser(widget.phoneNumber);
        maskedNum = retryData?['maskedNumber'] ?? '';
      }
      await prefs.setString('maskedNumber', maskedNum);
      debugPrint('JWT token obtained, masked: $maskedNum');

      // Register FCM token for push notifications
      try {
        await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
        final fcmToken = await FirebaseMessaging.instance.getToken(
          vapidKey: const String.fromEnvironment('FCM_VAPID_KEY', defaultValue: ''),
        );
        if (fcmToken != null && fcmToken.isNotEmpty) {
          await ApiService.saveFcmToken(widget.phoneNumber, fcmToken);
          debugPrint('✅ FCM token registered');
        }
      } catch (e) {
        debugPrint('FCM token registration skipped: $e');
      }

      // First time? → show contact sync. Returning? → go to dashboard
      final isFirstSync = !(prefs.getBool('contacts_synced') ?? false);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => WelcomeScreen(
          realNumber: widget.phoneNumber,
          maskedNumber: maskedNum,
          isFirstTime: isFirstSync,
        )),
        (_) => false,
      );

    } on FirebaseAuthException catch (e) {
      setState(() {
        _loading = false;
        _error = e.code == 'invalid-verification-code'
            ? 'Wrong OTP. Please check and try again.'
            : 'Verification failed: ${e.message}';
      });
      for (var c in _ctrl) c.clear();
      _nodes[0].requestFocus();
    } catch (e) {
      setState(() { _loading = false; _error = 'Something went wrong. Try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text('Enter OTP', style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
              const SizedBox(height: 8),
              Text('6-digit code sent to\n${widget.phoneNumber}',
                  style: const TextStyle(fontSize: 15, color: Colors.grey)),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => SizedBox(
                  width: 46, height: 56,
                  child: TextFormField(
                    controller: _ctrl[i],
                    focusNode: _nodes[i],
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF3B4FD8), width: 2)),
                      filled: true,
                      fillColor: _ctrl[i].text.isNotEmpty ? const Color(0xFFF0F4FF) : Colors.white,
                    ),
                    onChanged: (v) => _onChanged(i, v),
                  ),
                )),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13))),
                  ]),
                ),
              ],
              const SizedBox(height: 28),
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _otp.length == 6 ? _verify : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                      ),
                      child: const Text('Verify & Continue', style: TextStyle(fontSize: 17)),
                    ),
              const SizedBox(height: 20),
              Center(
                child: _resendEnabled
                    ? TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Resend OTP', style: TextStyle(
                            color: Color(0xFF3B4FD8), fontWeight: FontWeight.w600)),
                      )
                    : Text('Resend in ${_resendSeconds}s',
                        style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
