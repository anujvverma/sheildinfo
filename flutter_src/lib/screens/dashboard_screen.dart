import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'logs_screen.dart';
import 'phonebook_screen.dart';
import 'whitelist_screen.dart';
import 'plans_screen.dart';
import 'delivery_mode_screen.dart';
import 'upgrade_screen.dart';
import 'login_screen.dart';
import 'sms_inbox_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? realNumber;
  String? maskedNumber;
  Map<String, dynamic>? userInfo;
  int blockedCount = 0;
  int allowedCount = 0;
  bool _loading = true;
  bool _planExpired = false;
  bool _isTrial = false;
  Map<String, dynamic>? _features;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    realNumber = prefs.getString('realNumber');
    maskedNumber = prefs.getString('maskedNumber');

    if (realNumber != null) {
      // Register FCM token for push notifications
      _registerFcmToken();
      final user = await ApiService.getUser(realNumber!);
      // Update masked number from API in case it changed
      if (user != null && user['maskedNumber'] != null) {
        maskedNumber = user['maskedNumber'];
        await prefs.setString('maskedNumber', maskedNumber!);
      }
      _planExpired = user?['expired'] ?? false;
      _isTrial = (user?['plan'] ?? 'trial') == 'trial';
      _features = user?['features'] as Map<String, dynamic>?;
      final logs = await ApiService.getLogs(realNumber!);
      final calls = logs['calls'] as List? ?? [];
      setState(() {
        userInfo = user;
        blockedCount = calls.where((c) => c['action'] == 'blocked').length;
        allowedCount = calls.where((c) => c['action'] == 'allowed').length;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }


  Widget _buildPlanBanner() {
    final isExpired = _planExpired;
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const UpgradeScreen())).then((_) => _loadData()),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isExpired ? Colors.red.shade50 : Colors.orange.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isExpired ? Colors.red.shade200 : Colors.orange.shade200),
        ),
        child: Row(children: [
          Icon(isExpired ? Icons.warning_amber : Icons.info_outline,
              color: isExpired ? Colors.red : Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isExpired ? 'Plan Expired' : 'Free Trial Active',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                    color: isExpired ? Colors.red : Colors.orange)),
            Text(isExpired
                ? 'Upgrade now to keep your shield active'
                : 'Upgrade to unlock Delivery Mode, SMS forwarding & more',
                style: TextStyle(fontSize: 11,
                    color: isExpired ? Colors.red.shade700 : Colors.orange.shade700)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isExpired ? Colors.red : Colors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Upgrade', style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ]),
      ),
    );
  }

  Future<void> _registerFcmToken() async {
    // FCM push notifications work on mobile (iOS/Android)
    // On web, notifications are handled differently
    debugPrint('FCM: skipped on web platform');
  }

  void _copyMaskedNumber() {
    if (maskedNumber != null && maskedNumber!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: maskedNumber!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masked number copied! Share this number — not your real one.'),
          backgroundColor: Color(0xFF3B4FD8),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clears authToken, realNumber, maskedNumber, etc.
    if (!mounted) return;
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('ShieldInfo', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── MASKED NUMBER CARD ──────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D1B5E), Color(0xFF3B4FD8)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(
                            color: const Color(0xFF3B4FD8).withOpacity(0.3),
                            blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Row(children: [
                          Icon(Icons.shield, color: Colors.white70, size: 16),
                          SizedBox(width: 6),
                          Text('YOUR SHIELDINFO NUMBER',
                              style: TextStyle(color: Colors.white70, fontSize: 11,
                                  letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: Text(
                              maskedNumber?.isNotEmpty == true ? maskedNumber! : 'Setting up your number...',
                              style: const TextStyle(color: Colors.white, fontSize: 24,
                                  fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                          ),
                          GestureDetector(
                            onTap: _copyMaskedNumber,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.copy, color: Colors.white, size: 14),
                                SizedBox(width: 6),
                                Text('Copy', style: TextStyle(color: Colors.white,
                                    fontSize: 12, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        const Text('Share this number — your real number stays private',
                            style: TextStyle(color: Colors.white60, fontSize: 11)),
                        const SizedBox(height: 14),
                        Row(children: [
                          GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => const UpgradeScreen())).then((_) => _loadData()),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(
                                  '${(userInfo?["plan"] ?? "trial").toString().toUpperCase()} PLAN',
                                  style: const TextStyle(color: Colors.white, fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 10),
                              ]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (userInfo?['active'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                                SizedBox(width: 4),
                                Text('ACTIVE', style: TextStyle(color: Colors.greenAccent,
                                    fontSize: 11, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                        ]),
                      ]),
                    ),

                    const SizedBox(height: 16),

                    // ── PLAN BANNER ──────────────────────────────────────
                    if (_planExpired || _isTrial) _buildPlanBanner(),
                    if (_planExpired || _isTrial) const SizedBox(height: 12),

                    // ── STATS ───────────────────────────────────────────
                    Row(children: [
                      Expanded(child: _StatCard(
                          icon: Icons.block, iconColor: Colors.red,
                          label: 'Blocked', value: blockedCount.toString(),
                          bgColor: const Color(0xFFFFEEEE))),
                      const SizedBox(width: 12),
                      Expanded(child: _StatCard(
                          icon: Icons.check_circle, iconColor: Colors.green,
                          label: 'Allowed', value: allowedCount.toString(),
                          bgColor: const Color(0xFFEEFFEE))),
                    ]),

                    const SizedBox(height: 20),

                    // ── QUICK ACTIONS ───────────────────────────────────
                    const Text('Quick Actions',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (ctx, constraints) {
                      final cols = constraints.maxWidth > 600 ? 4 : 2;
                      final cardW = (constraints.maxWidth - (cols-1)*12) / cols;
                      return Wrap(
                        spacing: 12, runSpacing: 12,
                        children: [
                          SizedBox(width: cardW, height: 110, child: _ActionCard(icon: Icons.contacts, label: 'Phonebook',
                              subtitle: 'Manage contacts', color: const Color(0xFF3B4FD8),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => PhonebookScreen(realNumber: realNumber!))))),
                          SizedBox(width: cardW, height: 110, child: _ActionCard(icon: Icons.history, label: 'Call Logs',
                              subtitle: 'View history', color: const Color(0xFF6B35D8),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => LogsScreen(realNumber: realNumber!))))),
                          SizedBox(width: cardW, height: 110, child: _ActionCard(icon: Icons.timer, label: 'Temp Access',
                              subtitle: 'Allow for hours', color: const Color(0xFF0099CC),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => WhitelistScreen(realNumber: realNumber!))))),
                          SizedBox(width: cardW, height: 110, child: _ActionCard(icon: Icons.sms_outlined, label: 'SMS Inbox',
                              subtitle: 'Forwarded messages', color: const Color(0xFF0EA5E9),
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => const SmsInboxScreen())))),
                          SizedBox(width: cardW, height: 110, child: _ActionCard(icon: Icons.delivery_dining, label: 'Delivery Mode',
                              subtitle: 'Pro+ feature', color: Colors.orange,
                              onTap: () {
                                final canUse = _features?['deliveryMode'] ?? false;
                                if (!canUse) {
                                  Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => const UpgradeScreen(featureName: 'Delivery Mode')));
                                } else {
                                  Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => const DeliveryModeScreen())).then((_) => _loadData());
                                }
                              })),
                        ],
                      );
                    }),

                    const SizedBox(height: 16),

                    // ── SHARE BOX ───────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Share your ShieldInfo number',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        const Text('Use this on OLX, Swiggy, with strangers — never your real number.',
                            style: TextStyle(color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF0F4FF),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(children: [
                            Expanded(child: Text(
                              maskedNumber?.isNotEmpty == true ? maskedNumber! : 'Contact support to get your number',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                                  color: Color(0xFF3B4FD8), letterSpacing: 1),
                            )),
                            IconButton(
                              icon: const Icon(Icons.copy, color: Color(0xFF3B4FD8)),
                              onPressed: _copyMaskedNumber,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor, bgColor;
  final String label, value;
  const _StatCard({required this.icon, required this.iconColor,
      required this.label, required this.value, required this.bgColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(icon, color: iconColor, size: 28),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: iconColor)),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({required this.icon, required this.label,
      required this.subtitle, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 24),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ]),
        ]),
      ),
    );
  }
}
