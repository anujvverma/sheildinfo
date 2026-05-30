import 'package:flutter/material.dart';
import '../api_service.dart';

class WhitelistScreen extends StatefulWidget {
  final String realNumber;
  const WhitelistScreen({super.key, required this.realNumber});

  @override
  State<WhitelistScreen> createState() => _WhitelistScreenState();
}

class _WhitelistScreenState extends State<WhitelistScreen> {
  void _addTempAccess() {
    final numberCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    int selectedHours = 2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Allow Temporary Access',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Let someone call through for a limited time',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: numberCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Their Mobile Number',
                  hintText: '+919XXXXXXXXX',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  hintText: 'e.g. Zomato rider, Plumber',
                  prefixIcon: Icon(Icons.label),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Allow for how long?',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [1, 2, 4, 8].map((h) => GestureDetector(
                  onTap: () => setModal(() => selectedHours = h),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selectedHours == h
                          ? const Color(0xFF3B4FD8)
                          : const Color(0xFFF0F4FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$h hr',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: selectedHours == h ? Colors.white : const Color(0xFF3B4FD8),
                        )),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () async {
                  final number = numberCtrl.text.trim();
                  final label = labelCtrl.text.trim();
                  if (number.isEmpty) return;
                  Navigator.pop(context);
                  final success = await ApiService.addTempWhitelist(
                      widget.realNumber, number, label, selectedHours);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(success
                        ? '$number can call for $selectedHours hour(s)'
                        : 'Failed to add. Try again.'),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ));
                },
                child: const Text('Allow Access'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Temporary Access')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0099CC), Color(0xFF00BBEE)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.timer, color: Colors.white, size: 32),
                  SizedBox(height: 12),
                  Text('Temporary Whitelist',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Allow someone to call you for a few hours — perfect for delivery riders, repair people, or anyone you\'re expecting.',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Text('Common Use Cases', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            ...[
              ['🛵', 'Delivery Rider', 'Zomato, Swiggy, Amazon'],
              ['🔧', 'Repair Person', 'Plumber, electrician'],
              ['🚗', 'Cab Driver', 'Ola, Uber pickup'],
              ['📦', 'Courier', 'Delivery confirmation'],
            ].map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
              ),
              child: Row(
                children: [
                  Text(item[0], style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item[1], style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(item[2], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            )),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _addTempAccess,
              icon: const Icon(Icons.add),
              label: const Text('Add Temporary Access', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
