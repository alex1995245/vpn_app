import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/vpn_provider.dart';
import '../services/vpn_engine.dart';
import 'proxy_settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Timer? _uptimeTimer;
  Duration _uptime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final provider = context.read<VpnProvider>();
      if (provider.isConnected && provider.connectedAt != null) {
        setState(() {
          _uptime = DateTime.now().difference(provider.connectedAt!);
        });
      } else {
        setState(() {
          _uptime = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _uptimeTimer?.cancel();
    super.dispose();
  }

  Color _buttonColor(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return const Color(0xFF00E676);
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        return const Color(0xFFFFD600);
      case VpnStatus.error:
      case VpnStatus.disconnected:
        return const Color(0xFFFF1744);
    }
  }

  Color _glowColor(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return const Color(0xFF00E676).withOpacity(0.6);
      case VpnStatus.connecting:
      case VpnStatus.disconnecting:
        return const Color(0xFFFFD600).withOpacity(0.6);
      case VpnStatus.error:
      case VpnStatus.disconnected:
        return const Color(0xFFFF1744).withOpacity(0.5);
    }
  }

  String _statusText(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        return 'CONNECTED';
      case VpnStatus.connecting:
        return 'CONNECTING...';
      case VpnStatus.disconnecting:
        return 'DISCONNECTING...';
      case VpnStatus.error:
        return 'ERROR';
      case VpnStatus.disconnected:
        return 'DISCONNECTED';
    }
  }

  String _formatUptime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpn, _) {
        final status = vpn.status;
        final isAnimating =
            status == VpnStatus.connecting || status == VpnStatus.disconnecting;

        if (isAnimating) {
          _pulseController.repeat(reverse: true);
        } else {
          _pulseController.stop();
          _pulseController.value = 1.0;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0D1B2A),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0D1B2A),
            elevation: 0,
            title: const Text(
              'VPN App',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.settings, color: Colors.white70),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ProxySettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),

                // Connection status indicator
                Text(
                  _statusText(status),
                  style: TextStyle(
                    color: _buttonColor(status),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3,
                  ),
                ),

                const SizedBox(height: 40),

                // Large circular connect button
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    final scale = isAnimating ? _pulseAnimation.value : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: GestureDetector(
                        onTap: () async {
                          if (vpn.isConnected) {
                            await vpn.disconnect();
                          } else if (!vpn.isConnecting) {
                            await vpn.connect();
                          }
                        },
                        child: Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF0D1B2A),
                            border: Border.all(
                              color: _buttonColor(status),
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _glowColor(status),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                              BoxShadow(
                                color: _glowColor(status).withOpacity(0.3),
                                blurRadius: 80,
                                spreadRadius: 20,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                vpn.isConnected
                                    ? Icons.power_settings_new
                                    : Icons.power_settings_new_outlined,
                                size: 64,
                                color: _buttonColor(status),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                vpn.isConnected ? 'TAP TO\nDISCONNECT' : 'TAP TO\nCONNECT',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _buttonColor(status),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 48),

                // External IP
                if (vpn.isConnected) ...[
                  _InfoCard(
                    icon: Icons.public,
                    label: 'External IP',
                    value: vpn.externalIp ?? 'Fetching...',
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.timer,
                    label: 'Connected for',
                    value: _formatUptime(_uptime),
                  ),
                  const SizedBox(height: 16),
                ],

                // Proxy info
                if (vpn.config != null && !vpn.isConnected) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: _InfoCard(
                      icon: Icons.dns,
                      label: 'Proxy',
                      value: vpn.config!.address,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Error message
                if (vpn.errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF1744).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFFF1744).withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        vpn.errorMessage!,
                        style: const TextStyle(
                          color: Color(0xFFFF6B6B),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // No config warning
                if (vpn.config == null) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Tap the ⚙ icon to configure your SOCKS5 proxy',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                const Spacer(),

                // Bottom configure button
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProxySettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.tune, color: Colors.white54),
                    label: const Text(
                      'Proxy Settings',
                      style: TextStyle(color: Colors.white54, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2B3C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
