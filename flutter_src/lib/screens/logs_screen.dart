import 'package:flutter/material.dart';
import '../api_service.dart';

class LogsScreen extends StatefulWidget {
  final String realNumber;
  const LogsScreen({super.key, required this.realNumber});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> calls = [];
  List<dynamic> messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final logs = await ApiService.getLogs(widget.realNumber);
    setState(() {
      calls = logs['calls'] ?? [];
      messages = logs['messages'] ?? [];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Logs'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _loadLogs)],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Calls (${calls.length})'),
            Tab(text: 'SMS (${messages.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCallsList(),
                _buildSMSList(),
              ],
            ),
    );
  }

  Widget _buildCallsList() {
    if (calls.isEmpty) return _emptyState(Icons.call, 'No call logs yet');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: calls.length,
      itemBuilder: (_, i) {
        final call = calls[i];
        final isBlocked = call['action'] == 'blocked';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isBlocked ? Colors.red.shade50 : Colors.green.shade50,
              child: Icon(
                isBlocked ? Icons.call_end : Icons.call,
                color: isBlocked ? Colors.red : Colors.green,
                size: 20,
              ),
            ),
            title: Text(call['caller_number'] ?? 'Unknown',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(_formatDate(call['called_at']),
                style: const TextStyle(fontSize: 12)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isBlocked ? Colors.red.shade50 : Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isBlocked ? 'BLOCKED' : 'ALLOWED',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isBlocked ? Colors.red : Colors.green,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSMSList() {
    if (messages.isEmpty) return _emptyState(Icons.message, 'No messages yet');
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      itemBuilder: (_, i) {
        final msg = messages[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8)],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade50,
              child: const Icon(Icons.message, color: Colors.blue, size: 20),
            ),
            title: Text(msg['from_number'] ?? 'Unknown',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg['message'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)),
                Text(_formatDate(msg['sent_at']), style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
            isThreeLine: true,
          ),
        );
      },
    );
  }

  Widget _emptyState(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(text, style: const TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }
}
