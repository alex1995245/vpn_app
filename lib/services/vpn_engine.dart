import '../models/proxy_config.dart';

enum VpnStatus { disconnected, connecting, connected, disconnecting, error }

abstract class VpnEngine {
  VpnStatus get status;
  Stream<VpnStatus> get statusStream;
  Future<bool> connect(ProxyConfig config);
  Future<void> disconnect();
  void dispose();
}
