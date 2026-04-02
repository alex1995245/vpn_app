import 'dart:async';

import 'package:flutter/services.dart';

import '../models/proxy_config.dart';
import 'vpn_engine.dart';

class VpnEngineAndroid implements VpnEngine {
  static const MethodChannel _channel = MethodChannel('com.vpnapp/vpn');

  final _statusController = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = VpnStatus.disconnected;

  VpnEngineAndroid() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onStatusChanged':
        final String statusStr = call.arguments as String;
        _setStatus(_parseStatus(statusStr));
        break;
    }
  }

  VpnStatus _parseStatus(String s) {
    switch (s) {
      case 'connected':
        return VpnStatus.connected;
      case 'connecting':
        return VpnStatus.connecting;
      case 'disconnecting':
        return VpnStatus.disconnecting;
      case 'error':
        return VpnStatus.error;
      default:
        return VpnStatus.disconnected;
    }
  }

  void _setStatus(VpnStatus s) {
    _status = s;
    _statusController.add(s);
  }

  @override
  VpnStatus get status => _status;

  @override
  Stream<VpnStatus> get statusStream => _statusController.stream;

  @override
  Future<bool> connect(ProxyConfig config) async {
    _setStatus(VpnStatus.connecting);
    try {
      final result = await _channel.invokeMethod<bool>('connect', {
        'proxyUrl': config.socks5Url,
        'ip': config.ip,
        'port': config.port,
        'username': config.username,
        'password': config.password,
      });
      if (result == true) {
        _setStatus(VpnStatus.connected);
        return true;
      } else {
        _setStatus(VpnStatus.error);
        return false;
      }
    } catch (e) {
      _setStatus(VpnStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _setStatus(VpnStatus.disconnecting);
    try {
      await _channel.invokeMethod('disconnect');
    } catch (_) {
      // Best effort
    }
    _setStatus(VpnStatus.disconnected);
  }

  @override
  void dispose() {
    _statusController.close();
  }
}
