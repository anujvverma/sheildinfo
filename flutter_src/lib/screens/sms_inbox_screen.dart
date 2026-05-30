import 'package:flutter/material.dart';
import '../api_service.dart';

/// SMS Inbox — shows all messages forwarded from the Jio SIM box.
/// Each entry shows: sender, message body, time.
/// OTPs from Blinkit/Ola/etc. appear here instantly after the SIM box forwards them.
class SmsInboxScreen extends StatefulWidget {
  const SmsInboxScreen({super.key});
  @override
  State<SmsInboxScreen> createState() => _SmsInboxScreenState();
}

class _SmsInboxScreenState extends State<SmsInboxScreen> {
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final msgs = await ApiService.getSmsLog();
    setState(() {
      _messages = msgs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('SMS Inbox', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => _SmsCard(msg: _messages[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(Icons.sms_outlined, size: 40, color: Color(0xFF3B4FD8)),
          ),
          const SizedBox(height: 20),
          const Text('No messages yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'When someone sends an SMS to your ShieldInfo number, it will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey, height: 1.5),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF86EFAC)),
            ),
            child: const Row(children: [
              Icon(Icons.lightbulb_outline, color: Color(0xFF16A34A), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Register on Blinkit, Ola etc. with your ShieldInfo number — OTPs will show up here.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF166534), height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SmsCard extends StatelessWidget {
  final Map<String, dynamic> msg;
  const _SmsCard({required this.msg});

  /// Detect if this looks like an OTP message
  bool get _isOtp {
    final body = (msg['message'] ?? '').toString().toLowerCase();
    return body.contains('otp') ||
        body.contains('code') ||
        body.contains('verify') ||
        body.contains('verification') ||
        RegExp(r'\b\d{4,8}\b').hasMatch(body);
  }

  String get _timeAgo {
    final raw = msg['sent_at'] ?? msg['created_at'] ?? '';
    if (raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) { return ''; }
  }

  /// Extract the OTP digits from the message body
  String? get _otpCode {
    final body = msg['message'] ?? '';
    final match = RegExp(r'\b(\d{4,8})\b').firstMatch(body);
    return match?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    final isOtp = _isOtp;
    final from = msg['from_number'] ?? 'Unknown';
    final body = msg['message'] ?? '';
    final otp = _otpCode;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isOtp
            ? Border.all(color: const Color(0xFF3B4FD8).withOpacity(0.3), width: 1.5)
            : Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: isOtp
                    ? const Color(0xFFEEF2FF)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isOtp ? Icons.lock_open_outlined : Icons.sms_outlined,
                size: 20,
                color: isOtp ? const Color(0xFF3B4FD8) : Colors.grey,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(from,
                    style: const TextStyle(fontWeight: FontWeight.bold,
                        fontSize: 14, color: Color(0xFF1A1A2E))),
                Text(_timeAgo,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
            if (isOtp)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B4FD8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('OTP', style: TextStyle(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
          ]),

          const SizedBox(height: 12),

          // Message body
          Text(body,
              style: const TextStyle(fontSize: 14, color: Color(0xFF374151), height: 1.4)),

          // OTP highlight box
          if (isOtp && otp != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(children: [
                const Text('YOUR OTP', style: TextStyle(
                    fontSize: 10, color: Color(0xFF6B7280), letterSpacing: 1.5)),
                const SizedBox(height: 4),
                Text(otp,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold,
                        color: Color(0xFF3B4FD8), letterSpacing: 8)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
