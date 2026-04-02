import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/proxy_config.dart';
import 'vpn_engine.dart';

class VpnEngineWindows implements VpnEngine {
  static const String _tunName = 'VpnAppTun';
  static const String _tunIp = '10.0.0.2';
  static const String _tunGateway = '10.0.0.1';
  static const String _tunMask = '255.255.255.0';

  /// Time to wait after launching tun2socks before the Wintun adapter is
  /// registered in Windows and ready to accept `netsh` configuration.
  static const Duration _tunAdapterStartupDelay = Duration(seconds: 5);

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

  /// Try to extract [assetName] from rootBundle into [tempDir].
  /// Returns the path on success, null on failure.
  Future<String?> _tryExtractBinary(String assetName, String tempDir) async {
    try {
      final data = await rootBundle.load('assets/bin/windows/$assetName');
      final bytes = data.buffer.asUint8List();
      final outPath = p.join(tempDir, assetName);
      await File(outPath).writeAsBytes(bytes);
      debugPrint('[VPN] Extracted $assetName to $outPath');
      return outPath;
    } catch (e) {
      debugPrint('[VPN] Failed to extract $assetName from rootBundle: $e');
      return null;
    }
  }

  /// Locate tun2socks.exe, trying multiple strategies:
  /// 1. Extract from rootBundle as tun2socks.exe
  /// 2. Extract from rootBundle as tun2socks-windows-amd64.exe
  /// 3. Alongside the running executable
  /// 4. In the flutter_assets subfolder next to the running executable
  Future<String?> _findTun2socks(String tempDir) async {
    // 1 & 2: rootBundle (works in both debug and release)
    for (final name in ['tun2socks.exe', 'tun2socks-windows-amd64.exe']) {
      final path = await _tryExtractBinary(name, tempDir);
      if (path != null) return path;
    }

    // 3 & 4: filesystem fallbacks (useful during development)
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(exeDir, 'tun2socks.exe'),
      p.join(exeDir, 'tun2socks-windows-amd64.exe'),
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'bin', 'windows', 'tun2socks.exe'),
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'bin', 'windows', 'tun2socks-windows-amd64.exe'),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        debugPrint('[VPN] Found tun2socks at $candidate');
        return candidate;
      }
    }

    return null;
  }

  /// Locate wintun.dll using the same strategies, copying it to tempDir
  /// so it sits alongside tun2socks.exe.
  Future<void> _ensureWintun(String tempDir) async {
    // Try rootBundle first
    if (await _tryExtractBinary('wintun.dll', tempDir) != null) return;

    // Filesystem fallbacks
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(exeDir, 'wintun.dll'),
      p.join(exeDir, 'data', 'flutter_assets', 'assets', 'bin', 'windows', 'wintun.dll'),
    ];

    for (final candidate in candidates) {
      final src = File(candidate);
      if (src.existsSync()) {
        final dest = p.join(tempDir, 'wintun.dll');
        await src.copy(dest);
        debugPrint('[VPN] Copied wintun.dll from $candidate to $dest');
        return;
      }
    }

    debugPrint('[VPN] wintun.dll not found – tun2socks may fail to load Wintun driver');
  }

  Future<String?> _getOriginalGateway() async {
    const cmd =
        "(Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).NextHop";
    debugPrint('[VPN] Getting original gateway: powershell -Command "$cmd"');
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command', cmd],
        runInShell: true,
      );
      final gw = result.stdout.toString().trim();
      debugPrint('[VPN] Original gateway: "$gw"');
      if (gw.isNotEmpty) return gw;
    } catch (e) {
      debugPrint('[VPN] Failed to get gateway: $e');
    }
    return null;
  }

  Future<ProcessResult> _runRoute(List<String> args) async {
    debugPrint('[VPN] route ${args.join(' ')}');
    final result = await Process.run('route', args, runInShell: true);
    debugPrint('[VPN] route exit=${result.exitCode} stdout=${result.stdout} stderr=${result.stderr}');
    return result;
  }

  Future<void> _configureRoutes(String proxyIp, String originalGw) async {
    // 1. Route proxy IP through the original gateway so tun2socks can reach it
    await _runRoute(['add', proxyIp, 'mask', '255.255.255.255', originalGw, 'metric', '5']);

    // 2. Route upper half of address space through TUN
    await _runRoute(['add', '128.0.0.0', 'mask', '128.0.0.0', _tunGateway, 'metric', '6']);

    // 3. Route lower half through TUN – may fail on some systems, ignore error
    await _runRoute(['add', '0.0.0.0', 'mask', '128.0.0.0', _tunGateway, 'metric', '6']);
  }

  Future<void> _cleanupRoutes(String proxyIp) async {
    await _runRoute(['delete', '0.0.0.0', 'mask', '128.0.0.0']);
    await _runRoute(['delete', '128.0.0.0', 'mask', '128.0.0.0']);
    await _runRoute(['delete', proxyIp]);
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
      debugPrint('[VPN] Temp dir: $tempDir');

      // Locate / extract tun2socks
      final tun2socksPath = await _findTun2socks(tempDir);
      if (tun2socksPath == null) {
        _setStatus(VpnStatus.error);
        throw Exception(
          'tun2socks.exe not found. Place tun2socks.exe (or tun2socks-windows-amd64.exe) '
          'in assets/bin/windows/.\n'
          'Download: https://github.com/xjasonlyu/tun2socks/releases',
        );
      }

      // Ensure wintun.dll is present alongside tun2socks
      await _ensureWintun(p.dirname(tun2socksPath));

      // Get original gateway BEFORE starting tun2socks (route table still clean)
      _originalGateway = await _getOriginalGateway();
      if (_originalGateway == null || _originalGateway!.isEmpty) {
        _setStatus(VpnStatus.error);
        throw Exception('Could not determine original default gateway.');
      }

      // Start tun2socks
      final tun2socksArgs = ['-device', 'tun://$_tunName', '-proxy', config.socks5Url];
      debugPrint('[VPN] Starting tun2socks: $tun2socksPath ${tun2socksArgs.join(' ')}');
      _tun2socksProcess = await Process.start(
        tun2socksPath,
        tun2socksArgs,
        workingDirectory: p.dirname(tun2socksPath),
        runInShell: false,
      );

      // Log tun2socks output for diagnostics
      _tun2socksProcess!.stdout.listen((data) => debugPrint('[tun2socks] ${String.fromCharCodes(data)}'));
      _tun2socksProcess!.stderr.listen((data) => debugPrint('[tun2socks] ${String.fromCharCodes(data)}'));

      // Monitor process exit
      _tun2socksProcess!.exitCode.then((code) {
        debugPrint('[VPN] tun2socks exited with code $code');
        if (_status == VpnStatus.connected || _status == VpnStatus.connecting) {
          _setStatus(VpnStatus.error);
        }
      });

      // Wait for the TUN adapter to appear (tun2socks registers the Wintun adapter)
      debugPrint('[VPN] Waiting ${_tunAdapterStartupDelay.inSeconds}s for TUN adapter to come up…');
      await Future.delayed(_tunAdapterStartupDelay);

      // Configure TUN interface IP using the correct netsh syntax
      debugPrint('[VPN] Configuring TUN IP: netsh interface ipv4 set address name="$_tunName" static $_tunIp $_tunMask $_tunGateway');
      final netshResult = await Process.run(
        'netsh',
        ['interface', 'ipv4', 'set', 'address', 'name=$_tunName', 'static', _tunIp, _tunMask, _tunGateway],
        runInShell: true,
      );
      debugPrint('[VPN] netsh ip exit=${netshResult.exitCode} stdout=${netshResult.stdout} stderr=${netshResult.stderr}');

      // Set DNS via PowerShell; ignore errors (Wintun can reject netsh DNS commands)
      debugPrint('[VPN] Setting DNS via PowerShell');
      final dnsResult = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "Set-DnsClientServerAddress -InterfaceAlias '$_tunName' -ServerAddresses '1.1.1.1','8.8.8.8'",
        ],
        runInShell: true,
      );
      debugPrint('[VPN] DNS exit=${dnsResult.exitCode} stdout=${dnsResult.stdout} stderr=${dnsResult.stderr}');

      // Configure routing
      await _configureRoutes(config.ip, _originalGateway!);

      _setStatus(VpnStatus.connected);
      return true;
    } catch (e) {
      debugPrint('[VPN] connect error: $e');
      if (_status != VpnStatus.error) _setStatus(VpnStatus.error);
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    if (_status == VpnStatus.disconnected) return;
    _setStatus(VpnStatus.disconnecting);

    try {
      // Kill tun2socks via taskkill (more reliable than Process.kill on Windows)
      debugPrint('[VPN] Killing tun2socks via taskkill');
      final killResult = await Process.run(
        'taskkill', ['/F', '/IM', 'tun2socks.exe'],
        runInShell: true,
      );
      debugPrint('[VPN] taskkill exit=${killResult.exitCode} stdout=${killResult.stdout}');
      // Also call kill() as a fallback in case taskkill did not match the process
      _tun2socksProcess?.kill();
      _tun2socksProcess = null;

      // Clean up routes
      if (_proxyIp != null) {
        await _cleanupRoutes(_proxyIp!);
      }
    } catch (e) {
      debugPrint('[VPN] disconnect error (best-effort): $e');
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
