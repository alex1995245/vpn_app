import 'package:flutter_test/flutter_test.dart';

import 'package:vpn_app/models/proxy_config.dart';

void main() {
  group('ProxyConfig', () {
    test('socks5Url without credentials', () {
      final config = ProxyConfig(ip: '1.2.3.4', port: 1080);
      expect(config.socks5Url, 'socks5://1.2.3.4:1080');
    });

    test('socks5Url with credentials', () {
      final config = ProxyConfig(
        ip: '1.2.3.4',
        port: 1080,
        username: 'user',
        password: 'pass',
      );
      expect(config.socks5Url, 'socks5://user:pass@1.2.3.4:1080');
    });

    test('address getter', () {
      final config = ProxyConfig(ip: '10.0.0.1', port: 8080);
      expect(config.address, '10.0.0.1:8080');
    });

    test('toJson and fromJson roundtrip', () {
      final config = ProxyConfig(
        ip: '192.168.1.1',
        port: 3128,
        username: 'admin',
        password: 'secret',
      );
      final json = config.toJson();
      final restored = ProxyConfig.fromJson(json);
      expect(restored.ip, config.ip);
      expect(restored.port, config.port);
      expect(restored.username, config.username);
      expect(restored.password, config.password);
    });

    test('toJson with null credentials', () {
      final config = ProxyConfig(ip: '1.2.3.4', port: 1080);
      final json = config.toJson();
      expect(json['username'], isNull);
      expect(json['password'], isNull);
    });
  });
}
