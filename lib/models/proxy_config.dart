class ProxyConfig {
  final String ip;
  final int port;
  final String? username;
  final String? password;

  ProxyConfig({
    required this.ip,
    required this.port,
    this.username,
    this.password,
  });

  String get address => '$ip:$port';

  String get socks5Url {
    if (username != null && username!.isNotEmpty) {
      return 'socks5://$username:${password ?? ''}@$ip:$port';
    }
    return 'socks5://$ip:$port';
  }

  Map<String, dynamic> toJson() => {
        'ip': ip,
        'port': port,
        'username': username,
        'password': password,
      };

  factory ProxyConfig.fromJson(Map<String, dynamic> json) => ProxyConfig(
        ip: json['ip'] as String,
        port: json['port'] as int,
        username: json['username'] as String?,
        password: json['password'] as String?,
      );
}
