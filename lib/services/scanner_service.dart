import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:dart_ping/dart_ping.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/models.dart';

class ScannerService {
  final SupabaseClient _supabase = Supabase.instance.client;
  Map<String, String>? _macVendors;

  Future<void> loadMacVendors() async {
    if (_macVendors != null) return;
    try {
      final jsonStr = await rootBundle.loadString('assets/mac_vendors.json');
      final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
      _macVendors = jsonMap.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      print('Failed to load MAC vendors: $e');
      _macVendors = {};
    }
  }

  String? getBrandFromMac(String? mac) {
    if (mac == null || _macVendors == null) return null;
    final cleanMac = mac.replaceAll('-', ':').toUpperCase();
    if (cleanMac.length >= 8) {
      final prefix = cleanMac.substring(0, 8);
      return _macVendors![prefix];
    }
    return null;
  }

  Future<String?> getLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        // Skip loopback or virtual interfaces like WSL, VMware, etc if possible.
        // For simplicity, we just return the first valid non-loopback IP.
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  Future<String?> getGateway(String localIp) async {
    if (Platform.isWindows) {
      try {
        final result = await Process.run('arp', ['-a'], stdoutEncoding: const Utf8Codec(allowMalformed: true));
        final output = result.stdout.toString();
        // Look for the first dynamic entry matching the subnet
        final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
        final regex = RegExp('$subnet\\.\\d+\\s+([0-9a-fA-F\\-]{17})\\s+dinámico', caseSensitive: false);
        final enRegex = RegExp('$subnet\\.\\d+\\s+([0-9a-fA-F\\-]{17})\\s+dynamic', caseSensitive: false);
        
        final match = regex.firstMatch(output) ?? enRegex.firstMatch(output);
        if (match != null) {
          final ipMatch = RegExp('$subnet\\.\\d+').firstMatch(match.group(0)!);
          if (ipMatch != null) return ipMatch.group(0);
        }
      } catch (e) {
        // ignore
      }
    } else {
      try {
        final gateway = await NetworkInfo().getWifiGatewayIP();
        if (gateway != null && gateway.isNotEmpty) return gateway;
      } catch (e) {
        // ignore
      }
    }
    // Fallback: assume gateway is .1
    final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
    return '$subnet.1';
  }

  /// Sweeps the local subnet. For example, if IP is 192.168.1.5, it pings 192.168.1.1 to 192.168.1.254.
  Stream<DeviceModel> scanNetwork(String networkId, String baseIp) async* {
    final subnet = baseIp.substring(0, baseIp.lastIndexOf('.'));
    
    // Concurrency limit helper could be added, but for now we dispatch sequentially and listen asynchronously
    for (int i = 1; i < 255; i++) {
      final targetIp = '$subnet.$i';
      final ping = Ping(targetIp, count: 1, timeout: 1);
      
      ping.stream.listen((event) async {
        if (event.response != null && event.error == null) {
          // Device is online
          String? macAddress;
          String? hostname;
          
          if (Platform.isWindows) {
            macAddress = await _getMacFromArpWindows(targetIp);
            hostname = await _getHostnameWindows(targetIp);
          }

          final device = DeviceModel(
            networkId: networkId,
            ipAddress: targetIp,
            macAddress: macAddress,
            hostname: hostname,
          );
          
          _saveDevice(device);
        }
      });
      // We yield a dummy to keep the stream alive or manage differently. 
      // Actually, since we want a continuous stream, we should use a StreamController.
    }
  }

  // Rewrite scanNetwork with StreamController for better concurrency handling
  Stream<DeviceModel> performScan(String networkId, String baseIp, String gatewayIp) {
    final StreamController<DeviceModel> controller = StreamController();
    final subnet = baseIp.substring(0, baseIp.lastIndexOf('.'));
    
    int completed = 0;
    
    if (Platform.isWindows) {
      for (int i = 1; i < 255; i++) {
        final targetIp = '$subnet.$i';
        // Native Windows Ping
        Process.run(
          'ping', 
          ['-n', '1', '-w', '500', targetIp],
          stdoutEncoding: const Utf8Codec(allowMalformed: true),
        ).then((result) async {
          if (result.stdout.toString().toUpperCase().contains('TTL=')) {
            String? macAddress = await _getMacFromArpWindows(targetIp);
            String? hostname = await _getHostnameWindows(targetIp);
            String? brand = getBrandFromMac(macAddress);
            
            String iconType = 'device_unknown';
            if (targetIp == gatewayIp || (targetIp.endsWith('.1') && gatewayIp.isEmpty)) {
              iconType = 'router';
              if (brand == null) brand = 'Router / Puerta de enlace';
            } else if (brand != null) {
              final b = brand.toLowerCase();
              if (b.contains('apple') || b.contains('samsung') || b.contains('xiaomi') || b.contains('huawei') || b.contains('motorola') || b.contains('oppo')) iconType = 'smartphone';
              else if (b.contains('intel') || b.contains('dell') || b.contains('hp ') || b.contains('lenovo') || b.contains('asus') || b.contains('acer')) iconType = 'laptop';
              else if (b.contains('lg ') || b.contains('sony') || b.contains('hisense') || b.contains('tcl') || b.contains('roku')) iconType = 'tv';
              else if (b.contains('nintendo') || b.contains('playstation') || b.contains('xbox')) iconType = 'gamepad';
            }

            final device = DeviceModel(
              networkId: networkId,
              ipAddress: targetIp,
              macAddress: macAddress,
              hostname: hostname,
              brand: brand,
              iconType: iconType,
              lastSeen: DateTime.now(),
            );
            _saveDevice(device);
            controller.add(device);
          }
        }).whenComplete(() {
          completed++;
          if (completed >= 254) controller.close();
        });
      }
    } else {
      // Run mobile pings in batches to prevent ANRs
      Future<void> runBatches() async {
        for (int start = 1; start < 255; start += 20) {
          int end = start + 20;
          if (end > 255) end = 255;
          
          List<Future<void>> chunk = [];
          
          for (int j = start; j < end; j++) {
            final targetIp = '$subnet.$j';
            final completer = Completer<void>();
            final ping = Ping(targetIp, count: 1, timeout: 1);
            
            ping.stream.listen((event) {
              if (event.response != null && event.error == null) {
                String iconType = 'device_unknown';
                if (targetIp == gatewayIp || (targetIp.endsWith('.1') && gatewayIp.isEmpty)) {
                  iconType = 'router';
                } else {
                  iconType = 'smartphone'; // Safe default for mobile
                }

                final device = DeviceModel(
                  networkId: networkId,
                  ipAddress: targetIp,
                  macAddress: null, // Restricted on Android 10+
                  hostname: null,
                  brand: null,
                  iconType: iconType,
                  lastSeen: DateTime.now(),
                );
                _saveDevice(device);
                controller.add(device);
              }
            }).onDone(() {
              completed++;
              completer.complete();
              if (completed == 254) controller.close();
            });
            
            chunk.add(completer.future);
          }
          await Future.wait(chunk);
        }
      }
      runBatches();
    }
    return controller.stream;
  }

  Future<String?> _getMacFromArpWindows(String ip) async {
    try {
      final result = await Process.run('arp', ['-a', ip], stdoutEncoding: const Utf8Codec(allowMalformed: true));
      final output = result.stdout.toString();
      final regex = RegExp(r'([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})');
      final match = regex.firstMatch(output);
      if (match != null) {
        return match.group(0)?.replaceAll('-', ':');
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  Future<String?> _getHostnameWindows(String ip) async {
    try {
      final result = await Process.run('ping', ['-a', '-n', '1', ip], stdoutEncoding: const Utf8Codec(allowMalformed: true));
      final output = result.stdout.toString();
      final regex = RegExp(r'Pinging\s+([^\s]+)\s+\[');
      final match = regex.firstMatch(output);
      if (match != null) {
        return match.group(1);
      }
    } catch (e) {
      // Ignore
    }
    return null;
  }

  Future<NetworkModel?> getOrCreateNetwork(String name) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final localIp = await getLocalIP();
    if (localIp == null) return null;
    
    final gatewayIp = await getGateway(localIp);
    String? gatewayMac;
    if (gatewayIp != null && Platform.isWindows) {
      gatewayMac = await _getMacFromArpWindows(gatewayIp);
    }
    
    // Try to find existing network by gateway
    if (gatewayIp != null) {
      try {
        final response = await _supabase
            .from('networks')
            .select()
            .eq('owner_id', user.id)
            .eq('gateway_ip', gatewayIp)
            .limit(1)
            .maybeSingle();
            
        if (response != null && response.isNotEmpty) {
          return NetworkModel.fromJson(response);
        }
      } catch (e) {
        print('Supabase select error in getOrCreateNetwork: $e');
        // Let it fall through to create a new network if not found, or maybe just return a local one
      }
    }

    // Create new network
    final newNetwork = NetworkModel(
      id: '', // Supabase will generate UUID
      ownerId: user.id,
      name: name,
      gatewayIp: gatewayIp,
      gatewayMac: gatewayMac,
    );

    try {
      final insertResponse = await _supabase
          .from('networks')
          .insert(newNetwork.toJson())
          .select()
          .single();
      return NetworkModel.fromJson(insertResponse);
    } catch(e) {
      print('Supabase insert error in getOrCreateNetwork: $e');
      // If we completely fail to talk to Supabase, just return a local un-synced model
      // so the app can at least scan.
      return NetworkModel(id: 'local_only', ownerId: user.id, name: name, gatewayIp: gatewayIp, gatewayMac: gatewayMac);
    }
  }

  Future<void> _saveDevice(DeviceModel device) async {
    try {
      final existing = await _supabase
          .from('devices')
          .select('id')
          .eq('network_id', device.networkId)
          .eq('ip_address', device.ipAddress)
          .maybeSingle();

      if (existing != null && existing['id'] != null) {
        // Remove null fields so we don't overwrite existing custom names with null from scan
        final updateData = device.toJson();
        updateData.removeWhere((key, value) => value == null && key != 'last_seen');
        
        await _supabase.from('devices').update(updateData).eq('id', existing['id']);
      } else {
        await _supabase.from('devices').insert(device.toJson());
      }
    } catch (e) {
      print('Silenced error in _saveDevice: $e');
    }
  }

  Future<List<DeviceModel>> getSavedDevices(String networkId) async {
    try {
      final response = await _supabase
          .from('devices')
          .select()
          .eq('network_id', networkId);
      
      return (response as List).map((e) => DeviceModel.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> updateDevice(DeviceModel device) async {
    try {
      if (device.id != null && device.id!.isNotEmpty) {
        await _supabase.from('devices').update(device.toJson()).eq('id', device.id!);
      } else {
        await _saveDevice(device);
      }
    } catch (e) {
      print('Error updating device: $e');
    }
  }

  Future<void> logDeviceStatus(String deviceId, String status) async {
    try {
      await _supabase.from('device_history').insert({
        'device_id': deviceId,
        'status': status,
      });
    } catch (e) {
      print('Error logging status: $e');
    }
  }
}
