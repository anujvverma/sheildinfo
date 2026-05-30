import 'package:flutter/material.dart';
import '../api_service.dart';

class PhonebookScreen extends StatefulWidget {
  final String realNumber;
  const PhonebookScreen({super.key, required this.realNumber});

  @override
  State<PhonebookScreen> createState() => _PhonebookScreenState();
}

class _PhonebookScreenState extends State<PhonebookScreen> {
  List<dynamic> contacts = [];
  List<dynamic> filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchCtrl.addListener(_onSearch);
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      filtered = q.isEmpty
          ? contacts
          : contacts.where((c) =>
              (c['contact_name'] ?? '').toLowerCase().contains(q) ||
              (c['contact_number'] ?? '').contains(q)).toList();
    });
  }

  Future<void> _loadContacts() async {
    setState(() => _loading = true);
    final list = await ApiService.getPhonebook(widget.realNumber);
    setState(() {
      contacts = list;
      filtered = list;
      _loading = false;
    });
  }

  Future<void> _deleteContact(dynamic contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Contact'),
        content: Text('Remove ${contact['contact_name'] ?? contact['contact_number']} from your phonebook?\n\nThey will no longer be able to call through your masked number.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await ApiService.removeFromPhonebook(widget.realNumber, contact['contact_number']);
    if (success) {
      _loadContacts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${contact['contact_name'] ?? 'Contact'} removed'),
          backgroundColor: Colors.orange,
        ));
      }
    }
  }

  void _addContact() {
    final nameCtrl = TextEditingController();
    final numberCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 24, right: 24, top: 8, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text('Add Contact', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('This contact will be able to call through your masked number', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outline), hintText: 'e.g. Raj Kumar')),
            const SizedBox(height: 12),
            TextField(controller: numberCtrl, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Mobile Number', prefixIcon: Icon(Icons.phone_outlined), hintText: '+919XXXXXXXXX')),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    final number = numberCtrl.text.trim();
                    if (number.isEmpty) return;
                    Navigator.pop(context);
                    final success = await ApiService.addToPhonebook(widget.realNumber, number, name);
                    if (!mounted) return;
                    if (success) {
                      _loadContacts();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${name.isNotEmpty ? name : number} added!'), backgroundColor: Colors.green),
                      );
                    }
                  },
                  child: const Text('Add'),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _avatarColor(String name) {
    final colors = [
      const Color(0xFF3B4FD8), const Color(0xFF6B35D8), const Color(0xFF0099CC),
      const Color(0xFF00AA88), const Color(0xFFCC6600), const Color(0xFFCC0066),
    ];
    if (name.isEmpty) return colors[0];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        title: const Text('Phonebook'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadContacts),
          IconButton(icon: const Icon(Icons.person_add), onPressed: _addContact),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats bar
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFFF0F4FF), borderRadius: BorderRadius.circular(20)),
                        child: Row(children: [
                          const Icon(Icons.check_circle, color: Color(0xFF3B4FD8), size: 16),
                          const SizedBox(width: 4),
                          Text('${contacts.length} contacts allowed', style: const TextStyle(color: Color(0xFF3B4FD8), fontSize: 13, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      const Spacer(),
                      Text('Swipe left to remove', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                    ],
                  ),
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search contacts...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                // Contact list
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.contacts_outlined, size: 72, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(contacts.isEmpty ? 'No contacts yet' : 'No results found',
                                  style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 8),
                              if (contacts.isEmpty)
                                const Text('Tap + to add contacts who can\ncall through your masked number',
                                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            final name = c['contact_name'] ?? '';
                            final number = c['contact_number'] ?? '';
                            final initial = name.isNotEmpty ? name[0].toUpperCase() : '#';
                            return Dismissible(
                              key: Key(number),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(14)),
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.delete, color: Colors.white),
                                    Text('Remove', style: TextStyle(color: Colors.white, fontSize: 11)),
                                  ],
                                ),
                              ),
                              confirmDismiss: (_) async {
                                await _deleteContact(c);
                                return false; // We handle reload ourselves
                              },
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: CircleAvatar(
                                    backgroundColor: _avatarColor(name),
                                    radius: 24,
                                    child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                                  ),
                                  title: Text(name.isNotEmpty ? name : 'Unknown', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                  subtitle: Text(number, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle, color: Colors.green, size: 18),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                        onPressed: () => _deleteContact(c),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContact,
        icon: const Icon(Icons.person_add),
        label: const Text('Add Contact'),
        backgroundColor: const Color(0xFF3B4FD8),
        foregroundColor: Colors.white,
      ),
    );
  }
}
