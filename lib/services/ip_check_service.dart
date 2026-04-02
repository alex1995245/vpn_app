import 'package:http/http.dart' as http;

class IpCheckService {
  static const List<String> _apis = [
    'https://api.ipify.org',
    'https://icanhazip.com',
    'https://ifconfig.me/ip',
    'https://checkip.amazonaws.com',
  ];

  Future<String?> getExternalIp() async {
    for (final api in _apis) {
      try {
        final response = await http
            .get(Uri.parse(api))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final ip = response.body.trim();
          if (_isValidIp(ip)) return ip;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  bool _isValidIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }
}
