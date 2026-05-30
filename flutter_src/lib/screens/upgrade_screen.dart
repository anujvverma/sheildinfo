import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';

class UpgradeScreen extends StatefulWidget {
  final String? featureName;
  const UpgradeScreen({super.key, this.featureName});
  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  String _selected = 'pro';
  bool _loading = false;
  String? _realNumber;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) =>
        setState(() => _realNumber = p.getString('realNumber')));
  }

  Future<void> _subscribe() async {
    if (_realNumber == null) return;
    setState(() => _loading = true);
    final order = await ApiService.createPaymentOrder(_realNumber!, _selected);
    setState(() => _loading = false);
    if (!mounted) return;
    if (order != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Order created: Rs.${(order['amount']/100).toStringAsFixed(0)} — Razorpay checkout coming soon'),
        backgroundColor: const Color(0xFF7C3AED),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1B4B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1B4B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Manage Plan'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (widget.featureName != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF7C3AED)),
                ),
                child: Row(children: [
                  const Icon(Icons.lock, color: Color(0xFFA78BFA)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    '${widget.featureName} requires a paid plan. Upgrade to unlock it.',
                    style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 13),
                  )),
                ]),
              ),
              const SizedBox(height: 20),
            ],
            const Text('Choose Your Plan', style: TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Unlock full privacy protection',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 24),
            ...[
              {'id':'basic',  'name':'Basic',  'price':'99',  'color':const Color(0xFF4F46E5),
               'features':['1 shield number','Full call blocking','30-day logs','SMS forwarding']},
              {'id':'pro',    'name':'Pro',    'price':'199', 'color':const Color(0xFF7C3AED),
               'features':['2 shield numbers','Delivery Mode','90-day logs','Priority support']},
              {'id':'family', 'name':'Family', 'price':'399', 'color':const Color(0xFF06B6D4),
               'features':['5 shield numbers','Family dashboard','365-day logs','All Pro features']},
            ].map((plan) {
              final isSelected = _selected == plan['id'];
              final color = plan['color'] as Color;
              return GestureDetector(
                onTap: () => setState(() => _selected = plan['id'] as String),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withOpacity(0.15) : const Color(0xFF2E2B5F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isSelected ? color : Colors.white12,
                        width: isSelected ? 2 : 1),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(plan['name'] as String, style: TextStyle(
                            color: color, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      const Spacer(),
                      Text('Rs.${plan['price']}/mo', style: TextStyle(
                          color: color, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? color : Colors.transparent,
                          border: Border.all(color: isSelected ? color : Colors.white38, width: 2)),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 14) : null),
                    ]),
                    const SizedBox(height: 12),
                    ...(plan['features'] as List).map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Icon(Icons.check_circle, color: color, size: 15),
                        const SizedBox(width: 8),
                        Text(f as String, style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                      ]),
                    )),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 8),
            _loading
                ? const CircularProgressIndicator(color: Color(0xFF7C3AED))
                : ElevatedButton(
                    onPressed: _subscribe,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      'Subscribe to ${_selected[0].toUpperCase()}${_selected.substring(1)} Plan',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
            const SizedBox(height: 12),
            const Text('Secured by Razorpay  |  Cancel anytime',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
