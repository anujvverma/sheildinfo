import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  String _selected = 'pro';
  bool _loading = false;
  String? _realNumber;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _realNumber = prefs.getString('realNumber'));
  }

  Future<void> _subscribe() async {
    if (_realNumber == null) return;
    setState(() => _loading = true);

    final order = await ApiService.createPaymentOrder(_realNumber!, _selected);
    setState(() => _loading = false);

    if (order == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create order. Try again.'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Show payment confirmation (Razorpay SDK integration goes here)
    if (mounted) _showPaymentSheet(order);
  }

  void _showPaymentSheet(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Icon(Icons.payment, color: Color(0xFF3B4FD8), size: 40),
            const SizedBox(height: 12),
            Text('${order['planLabel']} Plan',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Rs.${(order['amount'] / 100).toStringAsFixed(0)}/month',
                style: const TextStyle(fontSize: 18, color: Color(0xFF3B4FD8),
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                _orderRow('Order ID', order['orderId'].toString().substring(0, 16) + '...'),
                const Divider(height: 16),
                _orderRow('Amount', 'Rs.${(order['amount'] / 100).toStringAsFixed(0)}'),
                const Divider(height: 16),
                _orderRow('Currency', 'INR'),
              ]),
            ),
            const SizedBox(height: 20),
            const Text('Razorpay payment integration active.\nUse the Razorpay Flutter SDK for in-app checkout.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Pay with Razorpay'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('Upgrade Plan'),
        leading: IconButton(icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose your plan', style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
            const SizedBox(height: 4),
            const Text('Cancel anytime. No hidden charges.',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 20),

            ...[
              { 'id':'basic',  'name':'Basic',  'price':'99',  'color':const Color(0xFF3B4FD8),
                'features':['1 masked number','Full call blocking','30-day logs','SMS forwarding'] },
              { 'id':'pro',    'name':'Pro',    'price':'199', 'color':const Color(0xFF7C3AED),
                'features':['2 masked numbers','90-day logs','Temp whitelist','Priority support','Analytics'] },
              { 'id':'family', 'name':'Family', 'price':'399', 'color':const Color(0xFF0D1B5E),
                'features':['5 masked numbers','Family dashboard','Full history','All Pro features'] },
            ].map((plan) {
              final isSelected = _selected == plan['id'];
              final color = plan['color'] as Color;
              final features = plan['features'] as List;
              return GestureDetector(
                onTap: () => setState(() => _selected = plan['id'] as String),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: isSelected ? color : const Color(0xFFE2E8F0),
                        width: isSelected ? 2 : 1),
                    boxShadow: isSelected ? [BoxShadow(
                        color: color.withOpacity(0.15), blurRadius: 12)] : [],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: color.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(plan['name'] as String, style: TextStyle(
                            color: color, fontWeight: FontWeight.bold, fontSize: 13))),
                      const Spacer(),
                      RichText(text: TextSpan(children: [
                        TextSpan(text: 'Rs.${plan['price']}',
                            style: TextStyle(color: color, fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Roboto')),
                        const TextSpan(text: '/mo',
                            style: TextStyle(color: Colors.grey, fontSize: 13,
                                fontFamily: 'Roboto')),
                      ])),
                      const SizedBox(width: 8),
                      Container(width: 22, height: 22,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? color : Colors.transparent,
                            border: Border.all(
                                color: isSelected ? color : Colors.grey.shade300, width: 2)),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 14) : null),
                    ]),
                    const SizedBox(height: 12),
                    ...features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Icon(Icons.check_circle, color: color, size: 16),
                        const SizedBox(width: 8),
                        Text(f as String, style: const TextStyle(fontSize: 13,
                            color: Color(0xFF334155))),
                      ]),
                    )),
                  ]),
                ),
              );
            }),

            const SizedBox(height: 8),
            _loading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _subscribe,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: Text('Subscribe to ${_selected[0].toUpperCase()}${_selected.substring(1)}',
                        style: const TextStyle(fontSize: 16)),
                  ),
            const SizedBox(height: 12),
            const Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock, size: 14, color: Colors.grey),
              SizedBox(width: 4),
              Text('Secured by Razorpay', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
          ],
        ),
      ),
    );
  }
}
