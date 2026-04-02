import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/proxy_config.dart';
import '../providers/vpn_provider.dart';
import '../services/ip_check_service.dart';

class ProxySettingsScreen extends StatefulWidget {
  const ProxySettingsScreen({super.key});

  @override
  State<ProxySettingsScreen> createState() => _ProxySettingsScreenState();
}

class _ProxySettingsScreenState extends State<ProxySettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final config = context.read<VpnProvider>().config;
    if (config != null) {
      _ipController.text = config.ip;
      _portController.text = config.port.toString();
      _usernameController.text = config.username ?? '';
      _passwordController.text = config.password ?? '';
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final config = ProxyConfig(
      ip: _ipController.text.trim(),
      port: int.parse(_portController.text.trim()),
      username: _usernameController.text.trim().isEmpty
          ? null
          : _usernameController.text.trim(),
      password: _passwordController.text.trim().isEmpty
          ? null
          : _passwordController.text.trim(),
    );

    await context.read<VpnProvider>().saveConfig(config);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Proxy settings saved!'),
          backgroundColor: Color(0xFF00E676),
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      // Try to check external IP through this proxy
      // For simplicity, just test if we can reach the proxy IP
      final ip = _ipController.text.trim();
      final port = int.parse(_portController.text.trim());

      final socket = await Socket.connect(ip, port)
          .timeout(const Duration(seconds: 5));
      await socket.close();

      final ipCheck = IpCheckService();
      final externalIp = await ipCheck.getExternalIp();

      setState(() {
        _testResult = '✅ Proxy reachable. Your IP: ${externalIp ?? 'unknown'}';
      });
    } catch (e) {
      setState(() {
        _testResult = '❌ Connection failed: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1B2A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Proxy Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'SOCKS5 Proxy Configuration',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),

                // IP Address
                _buildField(
                  controller: _ipController,
                  label: 'IP Address',
                  hint: '163.198.212.187',
                  icon: Icons.computer,
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'IP address is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Port
                _buildField(
                  controller: _portController,
                  label: 'Port',
                  hint: '8000',
                  icon: Icons.settings_ethernet,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Port is required';
                    }
                    final port = int.tryParse(v.trim());
                    if (port == null || port < 1 || port > 65535) {
                      return 'Enter a valid port (1-65535)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Username
                _buildField(
                  controller: _usernameController,
                  label: 'Username',
                  hint: 'optional',
                  icon: Icons.person_outline,
                  validator: (_) => null,
                ),
                const SizedBox(height: 16),

                // Password
                _buildField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'optional',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  validator: (_) => null,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Colors.white38,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                const SizedBox(height: 32),

                // Test result
                if (_testResult != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2B3C),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      _testResult!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Test button
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white54,
                          ),
                        )
                      : const Icon(Icons.network_check, color: Colors.white54),
                  label: Text(
                    _isTesting ? 'Testing...' : 'Test Connection',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Save button
                ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 4,
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.white38),
        suffixIcon: suffixIcon,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF1A2B3C),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF0066FF)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF1744)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF1744)),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFF6B6B)),
      ),
    );
  }
}
