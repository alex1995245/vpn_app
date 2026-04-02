import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/proxy_config.dart';
import 'vpn_engine.dart';

class VpnEngineWindows implements VpnEngine {
  static const String _tunName = 'VpnAppTun';
  static const String _tunIp = '10.0.0.2';
  static const String _tunGateway = '10.0.0.1';
  static const String _tunMask = '255.255.255.0';
  static const String _dns = '1.1.1.1';

  final _statusController = StreamController<VpnStatus>.broadcast();
  VpnStatus _status = VpnStatus.disconnected;
  Process? _tun2socksProcess;
  String? _originalGateway;
  String? _proxyIp;

  @override
  VpnStatus get status => _status;

  @override
  Stream<VpnStatus> get statusStream => _statusController.stream;

  void _setStatus(VpnStatus s) {
    _status = s;
    _statusController.add(s);
  }

  Future<String> _extractBinary(String assetName, String tempDir) async {
    final data = await rootBundle.load('assets/bin/windows/$assetName');
    final bytes = data.buffer.asUint8List();
    final outPath = p.join(tempDir, assetName);
    final file = File(outPath);
    await file.writeAsBytes(bytes);
    return outPath;
  }

  Future<String?> _getOriginalGateway() async {
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "(Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).NextHop",
        ],
      );
      final gw = result.stdout.toString().trim();
      if (gw.isNotEmpty && gw != '') return gw;
    } catch (_) {}
    return null;
  }

  Future<void> _runNetsh(List<String> args) async {
    await Process.run('netsh', args, runInShell: true);
  }

  Future<void> _runRoute(List<String> args) async {
    await Process.run('route', args, runInShell: true);
  }

  Future<void> _configureRoutes(String proxyIp, String originalGw) async {
    // Route proxy IP through original gateway so tun2socks can reach the proxy
    await _runRoute(['add', proxyIp, 'mask', '255.255.255.255', originalGw, 'metric', '5']);

    // Route all traffic through TUN (split into two /1 to cover all IPv4)
    await _runRoute(['add', '0.0.0.0', 'mask', '128.0.0.0', _tunGateway, 'metric', '6']);
    await _runRoute(['add', '128.0.0.0', 'mask', '128.0.0.0', _tunGateway, 'metric', '6']);
  }

  Future<void> _cleanupRoutes(String proxyIp, String originalGw) async {
    await _runRoute(['delete', proxyIp, 'mask', '255.255.255.255', originalGw]);
    await _runRoute(['delete', '0.0.0.0', 'mask', '128.0.0.0', _tunGateway]);
    await _runRoute(['delete', '128.0.0.0', 'mask', '128.0.0.0', _tunGateway]);
  }

  @override
  Future<bool> connect(ProxyConfig config) async {
    if (_status != VpnStatus.disconnected && _status != VpnStatus.error) {
      return false;
    }

    _setStatus(VpnStatus.connecting);
    _proxyIp = config.ip;

    try {
      final tempDir = Directory.systemTemp.createTempSync('vpn_app_').path;

      // Extract binaries from assets
      String tun2socksPath;
      try {
        tun2socksPath = await _extractBinary('tun2socks.exe', tempDir);
        await _extractBinary('wintun.dll', tempDir);
      } catch (e) {
        _setStatus(VpnStatus.error);
        throw Exception(
          'tun2socks.exe or wintun.dll not found in assets/bin/windows/. '
          'Please download them and place in the assets folder.\n'
          'tun2socks: https://github.com/xjasonlyu/tun2socks/releases\n'
          'wintun.dll: https://www.wintun.net/\nError: $e',
        );
      }

      // Start tun2socks process
      _tun2socksProcess = await Process.start(
        tun2socksPath,
        ['-device', 'tun://$_tunName', '-proxy', config.socks5Url],
        workingDirectory: tempDir,
        runInShell: false,
      );

      // Monitor process exit
      _tun2socksProcess!.exitCode.then((code) {
        if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
          _setStatus(VpnStatus.error);
        }
      });

      // Wait for TUN interface to come up
      await Future.delayed(const Duration(seconds: 3));

      if (_tun2socksProcess == null) {
        _setStatus(VpnStatus.error);
        return false;
      }

      // Configure TUN interface IP
      await _runNetsh([
        'interface', 'ip', 'set', 'address',
        'name=$_tunName', 'source=static',
        'addr=$_tunIp', 'mask=$_tunMask', 'gateway=$_tunGateway',
      ]);

      // Set DNS on TUN interface
      await _runNetsh([
        'interface', 'ip', 'set', 'dns',
        'name=$_tunName', 'source=static', 'addr=$_dns',
      ]);

      // Get original gateway before changing routes
      _originalGateway = await _getOriginalGateway();
      if (_originalGateway == null || _originalGateway!.isEmpty) {
        _tun2socksProcess?.kill();
        _tun2socksProcess = null;
        _setStatus(VpnStatus.error);
        throw Exception('Could not determine original default gateway.');
      }

      // Configure routing
      await _configureRoutes(config.ip, _originalGateway!);

      _setStatus(VpnStatus.connected);
      return true;
    } catch (e) {
      if (_status != VpnStatus.error) _setStatus(VpnStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_status == VpnStatus.disconnected) return;
    _setStatus(VpnStatus.disconnecting);

    try {
      _tun2socksProcess?.kill();
      _tun2socksProcess = null;

      if (_proxyIp != null && _originalGateway != null) {
        await _cleanupRoutes(_proxyIp!, _originalGateway!);
      }

      // Remove TUN interface IP config
      await _runNetsh([
        'interface', 'ip', 'set', 'address',
        'name=$_tunName', 'source=dhcp',
      ]);
    } catch (_) {
      // Best effort cleanup
    }

    _originalGateway = null;
    _proxyIp = null;
    _setStatus(VpnStatus.disconnected);
  }

  @override
  void dispose() {
    _tun2socksProcess?.kill();
    _statusController.close();
  }
}
