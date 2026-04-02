import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/proxy_config.dart';
import '../services/ip_check_service.dart';
import '../services/vpn_engine.dart';
import '../services/vpn_engine_android.dart';
import '../services/vpn_engine_windows.dart';

class VpnProvider extends ChangeNotifier {
  static const String _configKey = 'proxy_config';

  late final VpnEngine _engine;
  final IpCheckService _ipCheck = IpCheckService();

  ProxyConfig? _config;
  String? _externalIp;
  String? _errorMessage;
  DateTime? _connectedAt;

  VpnProvider() {
    if (Platform.isWindows) {
      _engine = VpnEngineWindows();
    } else {
      _engine = VpnEngineAndroid();
    }

    _engine.statusStream.listen((status) {
      if (status == VpnStatus.connected) {
        _connectedAt = DateTime.now();
        _refreshExternalIp();
      } else if (status == VpnStatus.disconnected ||
          status == VpnStatus.error) {
        _connectedAt = null;
        _externalIp = null;
      }
      notifyListeners();
    });

    _loadConfig();
  }

  ProxyConfig? get config => _config;
  String? get externalIp => _externalIp;
  String? get errorMessage => _errorMessage;
  DateTime? get connectedAt => _connectedAt;
  VpnStatus get status => _engine.status;
  bool get isConnected => _engine.status == VpnStatus.connected;
  bool get isConnecting =>
      _engine.status == VpnStatus.connecting ||
      _engine.status == VpnStatus.disconnecting;

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_configKey);
      if (jsonStr != null) {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        _config = ProxyConfig.fromJson(map);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> saveConfig(ProxyConfig config) async {
    _config = config;
    _errorMessage = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, jsonEncode(config.toJson()));
    } catch (_) {}
    notifyListeners();
  }

  Future<void> connect() async {
    if (_config == null) {
      _errorMessage = 'Please configure proxy settings first.';
      notifyListeners();
      return;
    }
    _errorMessage = null;
    notifyListeners();
    try {
      await _engine.connect(_config!);
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _errorMessage = null;
    notifyListeners();
    try {
      await _engine.disconnect();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _refreshExternalIp() async {
    _externalIp = null;
    notifyListeners();
    _externalIp = await _ipCheck.getExternalIp();
    notifyListeners();
  }

  Future<void> refreshExternalIp() => _refreshExternalIp();

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }
}
