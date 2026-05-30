import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'otp_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  bool _loading = false;
  String? _error;
  RecaptchaVerifier? _recaptchaVerifier;

  @override
  void dispose() {
    _recaptchaVerifier?.clear();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      setState(() => _error = 'Enter a valid 10-digit number');
      return;
    }
    setState(() { _loading = true; _error = null; });

    final fullNumber = '+91$phone';

    try {
      ConfirmationResult? confirmationResult;

      if (kIsWeb) {
        _recaptchaVerifier?.clear();
        _recaptchaVerifier = RecaptchaVerifier(
          auth: FirebaseAuth.instance,
          size: RecaptchaVerifierSize.invisible,
          onSuccess: () => debugPrint('reCAPTCHA success'),
          onError: (e) => debugPrint('reCAPTCHA error: $e'),
          onExpired: () => debugPrint('reCAPTCHA expired'),
        );
        confirmationResult = await FirebaseAuth.instance
            .signInWithPhoneNumber(fullNumber, _recaptchaVerifier!);
      } else {
        // Mobile: no recaptcha needed
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: fullNumber,
          verificationCompleted: (_) {},
          verificationFailed: (e) => throw e,
          codeSent: (verificationId, _) {
            if (mounted) {
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => OtpScreen(
                    phoneNumber: fullNumber,
                    verificationId: verificationId,
                  )));
            }
          },
          codeAutoRetrievalTimeout: (_) {},
        );
        return;
      }

      if (!mounted) return;
      setState(() => _loading = false);
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => OtpScreen(
            phoneNumber: fullNumber,
            confirmationResult: confirmationResult,
          )));

    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} — ${e.message}');
      setState(() {
        _loading = false;
        _error = _friendlyError(e.code);
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() { _loading = false; _error = 'Failed to send OTP. Try again.'; });
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'invalid-phone-number': return 'Invalid phone number. Use 10 digits.';
      case 'too-many-requests': return 'Too many attempts. Please wait and try again.';
      case 'quota-exceeded': return 'SMS quota exceeded. Try again later.';
      default: return 'Failed to send OTP ($code). Try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),
              Center(
                child: Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF3B4FD8), Color(0xFF6B7FE8)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(
                        color: const Color(0xFF3B4FD8).withOpacity(0.3),
                        blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: const Icon(Icons.shield, size: 50, color: Colors.white),
                ),
              ),
              const SizedBox(height: 24),
              const Center(child: Text('ShieldInfo', style: TextStyle(
                  fontSize: 32, fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A2E), letterSpacing: 0.5))),
              const Center(child: Text('Your privacy, protected',
                  style: TextStyle(fontSize: 15, color: Colors.grey))),
              const SizedBox(height: 40),

              ...[
                [Icons.lock_outline, 'Your real number stays private'],
                [Icons.block, 'Unknown callers get blocked'],
                [Icons.check_circle_outline, 'Only your contacts get through'],
              ].map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF0F4FF),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(b[0] as IconData,
                        color: const Color(0xFF3B4FD8), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(b[1] as String,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF334155))),
                ]),
              )),

              const SizedBox(height: 32),
              const Text('Enter your mobile number',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: _error != null ? Colors.red : const Color(0xFFE2E8F0),
                      width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: Color(0xFFE2E8F0)))),
                    child: const Text('+91', style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16,
                        color: Color(0xFF3B4FD8))),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        hintText: '9XXXXXXXXX', counterText: '',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onChanged: (_) => setState(() => _error = null),
                      onSubmitted: (_) => _sendOtp(),
                    ),
                  ),
                ]),
              ),

              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],

              const SizedBox(height: 24),
              // reCAPTCHA container (invisible but required by Firebase web)
              const SizedBox(id: Key('recaptcha-container'), height: 0),

              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _sendOtp,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Send OTP', style: TextStyle(fontSize: 17)),
                    ),
              const SizedBox(height: 20),
              Center(child: Text(
                  'By continuing you agree to our Terms & Privacy Policy',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400))),
            ],
          ),
        ),
      ),
    );
  }
}
