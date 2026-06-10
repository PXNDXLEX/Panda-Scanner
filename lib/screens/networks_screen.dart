import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/scanner_service.dart';

class NetworksScreen extends StatefulWidget {
  const NetworksScreen({super.key});

  @override
  State<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends State<NetworksScreen> {
  final ScannerService _scannerService = ScannerService();
  List<NetworkModel> _networks = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;
  String? _currentGateway;

  @override
  void initState() {
    super.initState();
    _initData();
    _refreshTimer = Timer.periodic(Duration(seconds: Platform.isAndroid || Platform.isIOS ? 600 : 10), (_) => _fetchNetworks());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    final localIp = await _scannerService.getLocalIP();
    if (localIp != null) {
      _currentGateway = await _scannerService.getGateway(localIp);
    }
    await _fetchNetworks();
  }

  Future<void> _fetchNetworks() async {
    try {
      final response = await Supabase.instance.client
          .from('networks')
          .select()
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _networks = (response as List).map((n) => NetworkModel.fromJson(n)).toList();
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return Center(child: Text('Not logged in', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Saved Networks', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: Theme.of(context).textTheme.bodyLarge?.color),
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _networks.isEmpty
                  ? const Center(child: Text('No saved networks.', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _networks.length,
                      itemBuilder: (context, index) {
                        final net = _networks[index];
                        final isConnected = _currentGateway == net.gatewayIp;
                        final isShared = net.ownerId != user.id;

                        return Card(
                          color: Theme.of(context).colorScheme.surface,
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: Icon(Icons.router, color: isConnected ? const Color(0xFF10B981) : Colors.grey),
                            title: Row(
                              children: [
                                Text(net.name, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                                if (isShared)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3B82F6),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Shared', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Gateway: ${net.gatewayIp}', style: const TextStyle(color: Colors.grey)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isConnected ? const Color(0xFF10B981) : Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isConnected ? 'Connected' : 'Offline',
                                      style: TextStyle(color: isConnected ? const Color(0xFF10B981) : Colors.redAccent, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                            onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => NetworkDetailsScreen(network: net)));
                            },
                          ),
                        );
                      },
                    ),
    );
  }
}

class NetworkDetailsScreen extends StatelessWidget {
  final NetworkModel network;
  const NetworkDetailsScreen({super.key, required this.network});

  IconData _getIcon(String type) {
    switch (type) {
      case 'router': return Icons.router;
      case 'laptop': return Icons.laptop;
      case 'smartphone': return Icons.smartphone;
      case 'tv': return Icons.tv;
      case 'gamepad': return Icons.gamepad;
      default: return Icons.device_unknown;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(network.name, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: Theme.of(context).textTheme.bodyLarge?.color),
        foregroundColor: Theme.of(context).textTheme.bodyLarge?.color,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('devices')
            .stream(primaryKey: ['id'])
            .eq('network_id', network.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
          }
          
          final data = snapshot.data ?? [];
          if (data.isEmpty) {
            return const Center(child: Text('No devices found in database for this network.', style: TextStyle(color: Colors.grey)));
          }
          
          final devices = data.map((d) => DeviceModel.fromJson(d)).toList();
          devices.sort((a, b) => (a.customName ?? a.hostname ?? a.ipAddress).compareTo(b.customName ?? b.hostname ?? b.ipAddress));

          DateTime? mostRecent;
          for (var d in devices) {
            if (d.lastSeen != null) {
              if (mostRecent == null || d.lastSeen!.isAfter(mostRecent)) {
                mostRecent = d.lastSeen;
              }
            }
          }

          String formatDt(DateTime dt) {
            final local = dt.toLocal();
            return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} a las ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
          }

          final isShared = network.ownerId != Supabase.instance.client.auth.currentUser?.id;

          return Column(
            children: [
              if (mostRecent != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: const Color(0xFF3B82F6).withOpacity(0.1),
                  child: Text(
                    'Última actualización de la red: ${formatDt(mostRecent)}',
                    style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final name = device.customName?.isNotEmpty == true ? device.customName! : (device.hostname ?? device.ipAddress);
                    
                    final isOffline = device.lastSeen == null || DateTime.now().difference(device.lastSeen!).inSeconds > 45;

                    return ListTile(
                      leading: Icon(_getIcon(device.iconType), color: Theme.of(context).textTheme.bodyLarge?.color),
                      title: Text(name, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${device.ipAddress} | ${device.brand ?? "Unknown"}', style: const TextStyle(color: Colors.grey)),
                          if (isShared && device.lastSeen != null)
                            Text('Última vez visto: ${formatDt(device.lastSeen!)}', style: const TextStyle(color: Colors.grey, fontSize: 12))
                          else
                            Text(isOffline ? 'Offline' : 'Connected', style: TextStyle(color: isOffline ? Colors.redAccent : const Color(0xFF10B981), fontSize: 12)),
                        ]
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
