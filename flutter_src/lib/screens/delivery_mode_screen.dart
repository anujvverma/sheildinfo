import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';

class DeliveryModeScreen extends StatefulWidget {
  const DeliveryModeScreen({super.key});
  @override
  State<DeliveryModeScreen> createState() => _DeliveryModeScreenState();
}

class _DeliveryModeScreenState extends State<DeliveryModeScreen> {
  String? realNumber;
  bool _active = false;
  DateTime? _openUntil;
  bool _loading = true;
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    realNumber = prefs.getString('realNumber');
    if (realNumber != null) {
      final status = await ApiService.getDeliveryMode(realNumber!);
      setState(() {
        _active = status['active'] ?? false;
        _openUntil = status['openUntil'] != null
            ? DateTime.parse(status['openUntil']).toLocal()
            : null;
        _loading = false;
      });
      if (_active) _startCountdown();
    } else {
      setState(() => _loading = false);
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_openUntil == null) return;
      final remaining = _openUntil!.difference(DateTime.now());
      if (remaining.isNegative) {
        setState(() { _active = false; _remaining = Duration.zero; });
        _timer?.cancel();
      } else {
        setState(() => _remaining = remaining);
      }
    });
    if (_openUntil != null) {
      setState(() => _remaining = _openUntil!.difference(DateTime.now()));
    }
  }

  Future<void> _enable(int hours) async {
    if (realNumber == null) return;
    setState(() => _loading = true);
    final success = await ApiService.enableDeliveryMode(realNumber!, hours);
    if (success) {
      final openUntil = DateTime.now().add(Duration(hours: hours));
      setState(() {
        _active = true;
        _openUntil = openUntil;
        _loading = false;
      });
      _startCountdown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Delivery Mode ON for $hours hour${hours > 1 ? 's' : ''}'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ));
      }
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _disable() async {
    if (realNumber == null) return;
    setState(() => _loading = true);
    final success = await ApiService.disableDeliveryMode(realNumber!);
    if (success) {
      _timer?.cancel();
      setState(() { _active = false; _openUntil = null; _loading = false; _remaining = Duration.zero; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Shield restored'), backgroundColor: Color(0xFF3B4FD8)),
        );
      }
    } else {
      setState(() => _loading = false);
    }
  }

  String _formatRemaining() {
    final h = _remaining.inHours;
    final m = _remaining.inMinutes % 60;
    final s = _remaining.inSeconds % 60;
    if (h > 0) return '${h}h ${m}m remaining';
    if (m > 0) return '${m}m ${s}s remaining';
    return '${s}s remaining';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('Delivery Mode'),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status banner
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _active
                            ? [const Color(0xFFE65100), const Color(0xFFFF9800)]
                            : [const Color(0xFF0D1B5E), const Color(0xFF3B4FD8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(
                        color: (_active ? Colors.orange : const Color(0xFF3B4FD8)).withOpacity(0.3),
                        blurRadius: 20, offset: const Offset(0, 8),
                      )],
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(_active ? Icons.delivery_dining : Icons.shield,
                            color: Colors.white, size: 28),
                        const SizedBox(width: 10),
                        Text(_active ? 'DELIVERY MODE ACTIVE' : 'SHIELD ACTIVE',
                            style: const TextStyle(color: Colors.white70, fontSize: 12,
                                fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      ]),
                      const SizedBox(height: 12),
                      Text(
                        _active ? 'All callers allowed through' : 'Only your contacts can call',
                        style: const TextStyle(color: Colors.white, fontSize: 22,
                            fontWeight: FontWeight.bold),
                      ),
                      if (_active && _remaining.inSeconds > 0) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(_formatRemaining(),
                              style: const TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ],
                      if (_active) ...[
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _disable,
                            icon: const Icon(Icons.shield, color: Colors.white),
                            label: const Text('Restore Shield Now',
                                style: TextStyle(color: Colors.white, fontSize: 14)),
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white),
                                padding: const EdgeInsets.symmetric(vertical: 12)),
                          ),
                        ),
                      ],
                    ]),
                  ),

                  const SizedBox(height: 24),

                  if (!_active) ...[
                    const Text('Enable Delivery Mode',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E))),
                    const SizedBox(height: 4),
                    const Text('Allow ALL callers for a limited time — perfect when you\'re expecting a delivery or cab.',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                    const SizedBox(height: 20),

                    // Duration options
                    ...[ 
                      [1, '1 Hour', 'Quick delivery, short errand', Icons.delivery_dining],
                      [2, '2 Hours', 'Cab, repair person, meeting', Icons.local_taxi],
                      [4, '4 Hours', 'All-day deliveries, events', Icons.schedule],
                    ].map((opt) => GestureDetector(
                      onTap: () => _enable(opt[0] as int),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(
                              color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(opt[3] as IconData, color: Colors.orange, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(opt[1] as String, style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(opt[2] as String, style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)),
                            ],
                          )),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text('Enable',
                                style: TextStyle(color: Colors.white,
                                    fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ]),
                      ),
                    )),
                  ],

                  const SizedBox(height: 16),

                  // How it works
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('How Delivery Mode Works',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 12),
                      ...[
                        [Icons.touch_app, 'Tap to enable for 1, 2 or 4 hours'],
                        [Icons.phone_forwarded, 'ALL incoming calls connect during this time'],
                        [Icons.timer_off, 'Shield automatically re-activates when timer ends'],
                        [Icons.notifications, 'You\'ll get notified when shield is restored'],
                      ].map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(children: [
                          Icon(item[0] as IconData,
                              color: Colors.orange, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(item[1] as String,
                              style: const TextStyle(fontSize: 13, color: Color(0xFF334155)))),
                        ]),
                      )),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }
}
