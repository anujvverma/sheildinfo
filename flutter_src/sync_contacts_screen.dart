import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';
import 'dashboard_screen.dart';
import 'phonebook_screen.dart';

class SyncContactsScreen extends StatefulWidget {
  final String realNumber;
  final bool isFirstTime;
  const SyncContactsScreen({super.key, required this.realNumber, this.isFirstTime = false});
  @override
  State<SyncContactsScreen> createState() => _SyncContactsScreenState();
}

class _SyncContactsScreenState extends State<SyncContactsScreen> {

  void _goToDashboard() {
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: widget.isFirstTime ? null : AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Sync Contacts', style: TextStyle(color: Color(0xFF1A1A2E))),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.isFirstTime) ...[
                const SizedBox(height: 16),
                const Text('One last step!', style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 8),
                const Text('Add your contacts so they can\ncall through your masked number.',
                    style: TextStyle(fontSize: 15, color: Colors.grey)),
                const SizedBox(height: 28),
              ] else const SizedBox(height: 8),

              Center(child: Column(children: [
                Container(width: 110, height: 110,
                    decoration: const BoxDecoration(color: Color(0xFFF0F4FF), shape: BoxShape.circle),
                    child: const Icon(Icons.contacts, color: Color(0xFF3B4FD8), size: 56)),
                const SizedBox(height: 20),
                const Text('Protect your contacts', style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A1A2E))),
                const SizedBox(height: 8),
                const Text('Only contacts in your ShieldInfo phonebook\ncan call through your masked number.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14)),
              ])),

              const SizedBox(height: 28),

              ...[
                [Icons.block, 'Unknown callers blocked', 'Anyone not in your list gets rejected', Colors.red],
                [Icons.check_circle, 'Known contacts connected', 'Your phonebook contacts always get through', Colors.green],
                [Icons.timer, 'Temp access for others', 'Grant time-limited access to delivery riders', Colors.blue],
              ].map((item) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(children: [
                  Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: (item[3] as Color).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(item[0] as IconData, color: item[3] as Color, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item[1] as String, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(item[2] as String, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  ])),
                ]),
              )),

              const SizedBox(height: 28),

              ElevatedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => PhonebookScreen(realNumber: widget.realNumber))),
                icon: const Icon(Icons.person_add),
                label: const Text('Add Contacts', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _goToDashboard,
                  child: Text(widget.isFirstTime ? 'Skip for now' : 'Back to Dashboard',
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
