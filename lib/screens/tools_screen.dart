import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart' as webview_win;
import 'package:webview_flutter/webview_flutter.dart' as webview_mobile;
import 'package:url_launcher/url_launcher.dart';
import 'package:dart_ping/dart_ping.dart';
import '../services/scanner_service.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  final _ipController = TextEditingController(text: '8.8.8.8');
  Process? _pingProcess;
  bool _isPinging = false;
  final List<String> _output = [];
  final ScrollController _scrollController = ScrollController();

  void _togglePing() async {
    _runCommand('ping');
  }

  void _toggleTracert() async {
    _runCommand('tracert');
  }

  void _runCommand(String cmd) async {
    if (_isPinging) {
      _pingProcess?.kill();
      setState(() => _isPinging = false);
      return;
    }

    final target = _ipController.text.trim();
    if (target.isEmpty) return;

    setState(() {
      _isPinging = true;
      _output.clear();
      _output.add('${cmd.toUpperCase()}ing $target...');
    });

    try {
      if (cmd == 'ping') {
        List<String> args;
        if (Platform.isWindows) {
          args = ['-t', target];
        } else {
          args = ['-c', '10', target]; // Android ping command
        }

        _pingProcess = await Process.start('ping', args);
        
        _pingProcess!.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
          if (line.trim().isNotEmpty) {
            setState(() => _output.add(line));
            _scrollToBottom();
          }
        });
        
        _pingProcess!.stderr.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
          if (line.trim().isNotEmpty) {
            setState(() => _output.add('ERROR: $line'));
            _scrollToBottom();
          }
        });

        _pingProcess!.exitCode.then((code) {
          if (mounted) {
            setState(() {
              _isPinging = false;
              _output.add('Ping stopped (Exit code: $code)');
            });
            _scrollToBottom();
          }
        });
      } else if (cmd == 'tracert') {
        if (Platform.isWindows) {
          _pingProcess = await Process.start('tracert', ['-d', target]);
          _pingProcess!.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
            if (line.trim().isNotEmpty) {
              setState(() => _output.add(line));
              _scrollToBottom();
            }
          });
          _pingProcess!.exitCode.then((code) {
            if (mounted) setState(() => _isPinging = false);
          });
        } else {
          // Native Dart Traceroute for Android/iOS
          _runDartTraceroute(target);
        }
      }
    } catch (e) {
      setState(() {
        _isPinging = false;
        _output.add('Failed to start command: $e');
      });
    }
  }

  Future<void> _runDartTraceroute(String target) async {
    setState(() {
      _isPinging = true;
      _output.clear();
      _output.add('Tracing route to $target...');
    });
    
    int maxHops = 30;
    for (int ttl = 1; ttl <= maxHops; ttl++) {
      if (!mounted || !_isPinging) break;
      
      final ping = Ping(target, count: 1, timeout: 1, ttl: ttl);
      await for (final event in ping.stream) {
        if (event.error != null) {
          // Any error during a traceroute hop (like timeout or host unreachable)
          // is treated as a timeout in standard traceroute output.
          setState(() => _output.add('$ttl  * * * Request timed out.'));
        } else if (event.response != null) {
          final ip = event.response!.ip ?? target;
          final time = event.response!.time?.inMilliseconds ?? '<1';
          setState(() => _output.add('$ttl  ${time}ms  $ip'));
          _scrollToBottom();
          
          if (ip == target) {
            setState(() {
              _output.add('Trace complete.');
              _isPinging = false;
            });
            return;
          }
        }
      }
    }
    setState(() => _isPinging = false);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _pingProcess?.kill();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ipController,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                  decoration: const InputDecoration(
                    labelText: 'Target IP / Domain',
                    labelStyle: TextStyle(color: Colors.grey),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF10B981))),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _isPinging ? _togglePing : _togglePing,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isPinging ? Colors.red : const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                ),
                child: Text(_isPinging ? 'Stop' : 'Ping', style: const TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isPinging ? null : _toggleTracert,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                ),
                child: const Text('Tracert', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E293B)),
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _output.length,
                itemBuilder: (context, index) {
                  return Text(
                    _output[index],
                    style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class GatewayWebviewScreen extends StatefulWidget {
  const GatewayWebviewScreen({super.key});

  @override
  State<GatewayWebviewScreen> createState() => _GatewayWebviewScreenState();
}

class _GatewayWebviewScreenState extends State<GatewayWebviewScreen> {
  final ScannerService _scannerService = ScannerService();
  webview_win.WebviewController? _winWebviewController;
  webview_mobile.WebViewController? _mobileWebviewController;
  final TextEditingController _portController = TextEditingController(text: '80');
  
  String? _gatewayIp;
  bool _isWebviewInitialized = false;
  bool _isLoading = true;
  String _status = 'Detecting Gateway...';

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    final ip = await _scannerService.getLocalIP();
    if (ip != null) {
      final gateway = await _scannerService.getGateway(ip);
      if (gateway != null && mounted) {
        setState(() {
          _gatewayIp = gateway;
          _status = 'Initializing Webview...';
        });
        await _initWebview();
        return;
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _status = 'Gateway not detected';
      });
    }
  }

  Future<void> _initWebview() async {
    try {
      if (Platform.isWindows) {
        _winWebviewController = webview_win.WebviewController();
        await _winWebviewController!.initialize();
        await _winWebviewController!.setBackgroundColor(Colors.transparent);
        await _winWebviewController!.setPopupWindowPolicy(webview_win.WebviewPopupWindowPolicy.deny);
      } else {
        _mobileWebviewController = webview_mobile.WebViewController()
          ..setJavaScriptMode(webview_mobile.JavaScriptMode.unrestricted);
      }
      if (mounted) {
        setState(() {
          _isWebviewInitialized = true;
          _isLoading = false;
        });
      }
      _loadUrl();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _status = 'Webview Error: $e';
        });
      }
    }
  }

  void _loadUrl() {
    if (_gatewayIp != null && _isWebviewInitialized) {
      final port = _portController.text.trim();
      final url = 'http://$_gatewayIp:$port';
      if (Platform.isWindows) {
        _winWebviewController?.loadUrl(url);
      } else {
        _mobileWebviewController?.loadRequest(Uri.parse(url));
      }
    }
  }

  Future<void> _openExternal() async {
    if (_gatewayIp != null) {
      final port = _portController.text.trim();
      final url = Uri.parse('http://$_gatewayIp:$port');
      if (!await launchUrl(url)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir el navegador externo')));
        }
      }
    }
  }

  @override
  void dispose() {
    _winWebviewController?.dispose();
    // _mobileWebviewController doesn't have a direct dispose
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF10B981)),
            const SizedBox(height: 16),
            Text(_status, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (!_isWebviewInitialized) {
      return Center(
        child: Text(_status, style: const TextStyle(color: Colors.red, fontSize: 16)),
      );
    }

    return Column(
      children: [
        // Top Bar for Port changing
        Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surface,
          child: Row(
            children: [
              Text('Gateway: $_gatewayIp :', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _portController,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.all(8),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF10B981))),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _loadUrl,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                child: const Text('Go', style: TextStyle(color: Colors.white)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _openExternal,
                icon: Icon(Icons.open_in_browser, color: Theme.of(context).textTheme.bodyLarge?.color),
                label: Text('External', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
              ),
            ],
          ),
        ),
        // Webview
        Expanded(
          child: Platform.isWindows
              ? webview_win.Webview(_winWebviewController!)
              : webview_mobile.WebViewWidget(controller: _mobileWebviewController!),
        ),
      ],
    );
  }
}
