import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/scanner_service.dart';
import '../models/models.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScannerService _scannerService = ScannerService();
  
  NetworkModel? _currentNetwork;
  List<DeviceModel> _devices = [];
  final Map<String, bool> _deviceStatusMap = {};
  bool _isScanning = false;
  String _statusMessage = 'Ready';
  String? _localIp;
  Timer? _autoScanTimer;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _initNetwork();
    _autoScanTimer = Timer.periodic(Duration(seconds: Platform.isAndroid || Platform.isIOS ? 600 : 15), (_) {
      if (!_isScanning && _currentNetwork != null && mounted) {
        _startScan();
      }
    });
  }

  @override
  void dispose() {
    _autoScanTimer?.cancel();
    super.dispose();
  }

  Future<void> _initNetwork() async {
    setState(() => _statusMessage = 'Loading MAC vendors...');
    await _scannerService.loadMacVendors();

    setState(() => _statusMessage = 'Detecting network...');
    _localIp = await _scannerService.getLocalIP();
    if (_localIp == null) {
      setState(() => _statusMessage = 'No local network connection detected.');
      return;
    }
    
    final network = await _scannerService.getOrCreateNetwork('My Network');
    if (network != null) {
      setState(() {
        _currentNetwork = network;
        _statusMessage = 'Connected to ${network.name} (Gateway: ${network.gatewayIp})';
      });
      _loadSavedDevices();
    } else {
      setState(() => _statusMessage = 'Failed to load network from database.');
    }
  }

  Future<void> _loadSavedDevices() async {
    if (_currentNetwork == null) return;
    final devices = await _scannerService.getSavedDevices(_currentNetwork!.id);
    setState(() {
      _devices = devices;
      _sortDevices();
    });
  }

  int _ipCompare(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i=0; i<4; i++) {
      if (aParts.length <= i || bParts.length <= i) return 0;
      int cmp = aParts[i].compareTo(bParts[i]);
      if (cmp != 0) return cmp;
    }
    return 0;
  }

  void _sortDevices() {
    _devices.sort((d1, d2) => _ipCompare(d1.ipAddress, d2.ipAddress));
  }

  Future<void> _startScan() async {
    if (_currentNetwork == null) return;
    final ip = await _scannerService.getLocalIP();
    if (ip == null) return;

    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning subnet...';
    });

    _scannerService.performScan(_currentNetwork!.id, ip, _currentNetwork!.gatewayIp ?? '').listen((device) {
      setState(() {
        final existingIndex = _devices.indexWhere((d) => d.ipAddress == device.ipAddress);
        if (existingIndex >= 0) {
          // Update MAC/Hostname if it was empty, but keep custom edits
          final existing = _devices[existingIndex];
          _devices[existingIndex] = DeviceModel(
            id: existing.id,
            networkId: existing.networkId,
            ipAddress: device.ipAddress,
            macAddress: device.macAddress ?? existing.macAddress,
            hostname: device.hostname ?? existing.hostname,
            customName: existing.customName,
            brand: existing.brand,
            iconType: existing.iconType,
            isFavorite: existing.isFavorite,
            lastSeen: device.lastSeen ?? existing.lastSeen,
          );
        } else {
          _devices.add(device);
        }
        _sortDevices();
      });
    }, onDone: () {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _statusMessage = 'Scan complete. Found ${_devices.length} devices.';
        });
        
        // Registrar historial de conexiones en la base de datos solo si hubo cambios
        for (var device in _devices) {
          if (device.id == null || device.id!.isEmpty) continue;
          
          final isOffline = device.lastSeen != null && DateTime.now().difference(device.lastSeen!).inSeconds > 45;
          final currentStatus = !isOffline;
          
          if (!_deviceStatusMap.containsKey(device.id)) {
            _deviceStatusMap[device.id!] = currentStatus;
            if (device.personId != null) {
              _scannerService.logDeviceStatus(device.id!, currentStatus ? 'online' : 'offline');
            }
          } else if (_deviceStatusMap[device.id] != currentStatus) {
            _deviceStatusMap[device.id!] = currentStatus;
            if (device.personId != null) {
              _scannerService.logDeviceStatus(device.id!, currentStatus ? 'online' : 'offline');
            }
            
            final name = device.customName?.isNotEmpty == true ? device.customName! : (device.hostname ?? device.ipAddress);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    currentStatus ? 'Dispositivo Conectado: $name' : 'Dispositivo Desconectado: $name',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: currentStatus ? const Color(0xFF10B981) : Colors.redAccent,
                  duration: const Duration(seconds: 3),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      }
    });
  }

  void _showDeviceDetails(DeviceModel device, int index) {
    final customNameController = TextEditingController(text: device.customName);
    final brandController = TextEditingController(text: device.brand);
    bool isFav = device.isFavorite;
    String selectedIcon = device.iconType;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Edit Device', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color)),
                    IconButton(
                      icon: Icon(isFav ? Icons.star : Icons.star_border, color: Colors.amber, size: 30),
                      onPressed: () {
                        setModalState(() => isFav = !isFav);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text('IP: ${device.ipAddress}', style: const TextStyle(color: Colors.grey)),
                Text('MAC: ${device.macAddress ?? "Unknown"}', style: const TextStyle(color: Colors.grey)),
                Text('Hostname: ${device.hostname ?? "Unknown"}', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 20),
                TextField(
                  controller: customNameController,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                  decoration: const InputDecoration(labelText: 'Custom Name', labelStyle: TextStyle(color: Colors.grey)),
                ),
                TextField(
                  controller: brandController,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                  decoration: const InputDecoration(labelText: 'Brand', labelStyle: TextStyle(color: Colors.grey)),
                ),
                const SizedBox(height: 20),
                Text('Icon Type:', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                DropdownButton<String>(
                  value: selectedIcon,
                  dropdownColor: Theme.of(context).colorScheme.surface,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                  items: const [
                    DropdownMenuItem(value: 'device_unknown', child: Text('Unknown')),
                    DropdownMenuItem(value: 'laptop', child: Text('Laptop/PC')),
                    DropdownMenuItem(value: 'smartphone', child: Text('Smartphone')),
                    DropdownMenuItem(value: 'router', child: Text('Router')),
                    DropdownMenuItem(value: 'tv', child: Text('Smart TV')),
                    DropdownMenuItem(value: 'gamepad', child: Text('Console')),
                  ],
                  onChanged: (val) {
                    if (val != null) setModalState(() => selectedIcon = val);
                  },
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                    onPressed: () async {
                      final updated = DeviceModel(
                        id: device.id,
                        networkId: device.networkId,
                        ipAddress: device.ipAddress,
                        macAddress: device.macAddress,
                        hostname: device.hostname,
                        customName: customNameController.text.trim(),
                        brand: brandController.text.trim(),
                        iconType: selectedIcon,
                        isFavorite: isFav,
                      );
                      setState(() {
                        final realIndex = _devices.indexWhere((d) => d.ipAddress == updated.ipAddress);
                        if (realIndex >= 0) {
                          _devices[realIndex] = updated;
                        }
                      });
                      await _scannerService.updateDevice(updated);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
    );
  }

  IconData _getIconData(String type) {
    switch (type) {
      case 'laptop': return Icons.laptop;
      case 'smartphone': return Icons.smartphone;
      case 'router': return Icons.router;
      case 'tv': return Icons.tv;
      case 'gamepad': return Icons.gamepad;
      default: return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Status Header
          Container(
            padding: const EdgeInsets.all(20),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _currentNetwork?.name ?? 'Unknown Network',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (_currentNetwork != null)
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.grey, size: 20),
                              onPressed: _renameNetworkDialog,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusMessage,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (_isScanning)
                  const CircularProgressIndicator(color: Color(0xFF10B981))
                else ...[
                  ElevatedButton.icon(
                    onPressed: _currentNetwork == null ? null : _startScan,
                    icon: const Icon(Icons.search),
                    label: const Text('Scan'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.share, color: Theme.of(context).textTheme.bodyLarge?.color),
                    onPressed: _currentNetwork == null ? null : _shareNetworkDialog,
                    tooltip: 'Share Network',
                  ),
                ],
              ],
            ),
          ),
          
          // Search Bar
          if (_currentNetwork != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: TextField(
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                decoration: InputDecoration(
                  hintText: 'Search by IP, MAC, Name, Brand...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.toLowerCase();
                  });
                },
              ),
            ),

          // Device List
          Expanded(
            child: _devices.isEmpty && !_isScanning
                ? const Center(child: Text('No devices found.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: _devices.where((d) {
                      if (_searchQuery.isEmpty) return true;
                      final q = _searchQuery;
                      return (d.ipAddress.toLowerCase().contains(q)) ||
                             (d.macAddress?.toLowerCase().contains(q) ?? false) ||
                             (d.hostname?.toLowerCase().contains(q) ?? false) ||
                             (d.brand?.toLowerCase().contains(q) ?? false) ||
                             (d.customName?.toLowerCase().contains(q) ?? false);
                    }).length,
                    itemBuilder: (context, index) {
                      final filteredDevices = _devices.where((d) {
                        if (_searchQuery.isEmpty) return true;
                        final q = _searchQuery;
                        return (d.ipAddress.toLowerCase().contains(q)) ||
                               (d.macAddress?.toLowerCase().contains(q) ?? false) ||
                               (d.hostname?.toLowerCase().contains(q) ?? false) ||
                               (d.brand?.toLowerCase().contains(q) ?? false) ||
                               (d.customName?.toLowerCase().contains(q) ?? false);
                      }).toList();
                      
                      final device = filteredDevices[index];
                      final name = device.customName?.isNotEmpty == true ? device.customName! : (device.hostname ?? device.ipAddress);
                      
                      final isOffline = device.lastSeen != null && DateTime.now().difference(device.lastSeen!).inSeconds > 45;
                      String timeText = '';
                      if (device.lastSeen != null) {
                        final diff = DateTime.now().difference(device.lastSeen!);
                        if (isOffline) {
                          if (diff.inMinutes < 60) timeText = 'Offline hace ${diff.inMinutes} min';
                          else if (diff.inHours < 24) timeText = 'Offline hace ${diff.inHours} hr';
                          else timeText = 'Offline hace ${diff.inDays} días';
                        } else {
                          timeText = 'Online';
                        }
                      }

                      return Opacity(
                        opacity: isOffline ? 0.4 : 1.0,
                        child: ListTile(
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                backgroundColor: const Color(0xFF3B82F6).withOpacity(0.2),
                                child: Icon(_getIconData(device.iconType), color: const Color(0xFF3B82F6)),
                              ),
                              if (device.isFavorite)
                                const Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Icon(Icons.star, color: Colors.amber, size: 16),
                                )
                            ],
                          ),
                          title: Row(
                            children: [
                              Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white)),
                              if (device.ipAddress == _localIp)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Este equipo', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              if (device.iconType == 'router')
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Gateway', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                            ]
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${device.ipAddress} | ${device.brand ?? device.macAddress ?? "Unknown MAC"}', style: const TextStyle(color: Colors.grey)),
                              if (timeText.isNotEmpty)
                                Text(timeText, style: TextStyle(color: isOffline ? Colors.redAccent : const Color(0xFF10B981), fontSize: 12)),
                            ],
                          ),
                          trailing: const Icon(Icons.edit, color: Colors.grey, size: 20),
                          onTap: () => _showDeviceDetails(device, index),
                        ).animate().fadeIn(delay: Duration(milliseconds: 50 * (index % 15))).slideX(),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareNetworkDialog() async {
    final emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Share Network', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(
              labelText: 'Guest Email',
              labelStyle: TextStyle(color: Colors.grey),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF10B981))),
            ),
            style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
            keyboardType: TextInputType.emailAddress,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim().toLowerCase();
                if (email.isNotEmpty && _currentNetwork != null) {
                  try {
                    await Supabase.instance.client.from('network_shares').insert({
                      'network_id': _currentNetwork!.id,
                      'guest_email': email,
                      'status': 'pending',
                    });
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Invitation sent to $email')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text('Share', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _renameNetworkDialog() async {
    if (_currentNetwork == null) return;
    final controller = TextEditingController(text: _currentNetwork!.name);
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Rename Network', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
            decoration: const InputDecoration(
              labelText: 'New Name',
              labelStyle: TextStyle(color: Colors.grey),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = controller.text.trim();
                if (newName.isNotEmpty) {
                  try {
                    await Supabase.instance.client
                        .from('networks')
                        .update({'name': newName})
                        .eq('id', _currentNetwork!.id);
                    setState(() {
                      _currentNetwork = NetworkModel(
                        id: _currentNetwork!.id,
                        ownerId: _currentNetwork!.ownerId,
                        name: newName,
                        gatewayIp: _currentNetwork!.gatewayIp,
                        gatewayMac: _currentNetwork!.gatewayMac,
                      );
                    });
                  } catch (e) {
                    print('Error renaming network: $e');
                  }
                  if (mounted) Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            )
          ]
        );
      }
    );
  }
}
