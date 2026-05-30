import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://sheildinfo-production.up.railway.app';

  // ─── AUTH HEADERS ─────────────────────────────────────
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ─── AUTH ──────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getAuthToken(String realNumber, String firebaseUid) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/api/auth/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'realNumber': realNumber, 'firebaseUid': firebaseUid}));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        // Save token to prefs
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('authToken', data['token']);
        return data;
      }
      return null;
    } catch (e) { return null; }
  }

  // ─── USER ──────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getUser(String realNumber) async {
    try {
      final headers = await _headers();
      final res = await http.get(
        Uri.parse('$baseUrl/api/user?realNumber=${Uri.encodeComponent(realNumber)}'),
        headers: headers,
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      return null;
    } catch (e) { return null; }
  }

  // ─── PHONEBOOK ─────────────────────────────────────────
  static Future<List<dynamic>> getPhonebook(String realNumber) async {
    try {
      final headers = await _headers();
      final res = await http.get(
        Uri.parse('$baseUrl/api/phonebook?realNumber=${Uri.encodeComponent(realNumber)}'),
        headers: headers,
      );
      if (res.statusCode == 200) return jsonDecode(res.body)['contacts'] ?? [];
      return [];
    } catch (e) { return []; }
  }

  static Future<bool> addToPhonebook(String realNumber, String contactNumber, String contactName) async {
    try {
      final headers = await _headers();
      final res = await http.post(Uri.parse('$baseUrl/api/phonebook/add'),
        headers: headers,
        body: jsonEncode({'realNumber': realNumber, 'contactNumber': contactNumber, 'contactName': contactName}));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<bool> removeFromPhonebook(String realNumber, String contactNumber) async {
    try {
      final headers = await _headers();
      final res = await http.delete(Uri.parse('$baseUrl/api/phonebook/remove'),
        headers: headers,
        body: jsonEncode({'realNumber': realNumber, 'contactNumber': contactNumber}));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<bool> bulkSyncPhonebook(String realNumber, List<Map<String, String>> contacts) async {
    try {
      final headers = await _headers();
      final res = await http.post(Uri.parse('$baseUrl/api/phonebook/bulk'),
        headers: headers,
        body: jsonEncode({'realNumber': realNumber, 'contacts': contacts}));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  // ─── LOGS ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> getLogs(String realNumber) async {
    try {
      final headers = await _headers();
      final res = await http.get(
        Uri.parse('$baseUrl/api/logs?realNumber=${Uri.encodeComponent(realNumber)}'),
        headers: headers,
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {'calls': [], 'messages': []};
    } catch (e) { return {'calls': [], 'messages': []}; }
  }

  // ─── WHITELIST ─────────────────────────────────────────
  static Future<bool> addTempWhitelist(String realNumber, String callerNumber, String label, int hours) async {
    try {
      final headers = await _headers();
      final res = await http.post(Uri.parse('$baseUrl/api/whitelist/temp'),
        headers: headers,
        body: jsonEncode({'realNumber': realNumber, 'callerNumber': callerNumber, 'label': label, 'hoursValid': hours}));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  // ─── PAYMENTS ──────────────────────────────────────────
  static Future<Map<String, dynamic>?> createPaymentOrder(String realNumber, String plan) async {
    try {
      final headers = await _headers();
      final res = await http.post(Uri.parse('$baseUrl/api/payment/create-order'),
        headers: headers,
        body: jsonEncode({'realNumber': realNumber, 'plan': plan}));
      if (res.statusCode == 200) return jsonDecode(res.body);
      return null;
    } catch (e) { return null; }
  }

  static Future<bool> verifyPayment(String realNumber, String plan,
      String orderId, String paymentId, String signature) async {
    try {
      final headers = await _headers();
      final res = await http.post(Uri.parse('$baseUrl/api/payment/verify'),
        headers: headers,
        body: jsonEncode({
          'realNumber': realNumber, 'plan': plan,
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        }));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  // ─── FCM ───────────────────────────────────────────────
  static Future<bool> saveFcmToken(String realNumber, String fcmToken) async {
    try {
      final headers = await _headers();
      final res = await http.post(Uri.parse('$baseUrl/api/fcm-token'),
        headers: headers,
        body: jsonEncode({'realNumber': realNumber, 'fcmToken': fcmToken}));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  // ─── DELIVERY MODE ─────────────────────────────────────
  static Future<Map<String, dynamic>> getDeliveryMode(String realNumber) async {
    try {
      final headers = await _headers();
      final res = await http.get(
        Uri.parse('$baseUrl/api/delivery-mode?realNumber=${Uri.encodeComponent(realNumber)}'),
        headers: headers,
      );
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {'active': false, 'openUntil': null};
    } catch (e) { return {'active': false, 'openUntil': null}; }
  }

  static Future<bool> enableDeliveryMode(String realNumber, int hours) async {
    try {
      final headers = await _headers();
      final res = await http.post(Uri.parse('$baseUrl/api/delivery-mode'),
        headers: headers,
        body: jsonEncode({'realNumber': realNumber, 'hours': hours}));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  static Future<bool> disableDeliveryMode(String realNumber) async {
    try {
      final headers = await _headers();
      final res = await http.post(Uri.parse('$baseUrl/api/delivery-mode/off'),
        headers: headers,
        body: jsonEncode({'realNumber': realNumber}));
      return res.statusCode == 200;
    } catch (e) { return false; }
  }

  // ─── SMS INBOX (SIM Box forwarded messages) ────────────
  static Future<List<Map<String, dynamic>>> getSmsLog() async {
    try {
      final headers = await _headers();
      final res = await http.get(
        Uri.parse('$baseUrl/api/sms-log'),
        headers: headers,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data['smsLog'] ?? []);
      }
      return [];
    } catch (e) { return []; }
  }
}
