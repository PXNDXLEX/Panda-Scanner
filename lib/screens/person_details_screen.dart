import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import '../models/models.dart';

class PersonDetailsScreen extends StatefulWidget {
  final PersonModel person;
  const PersonDetailsScreen({super.key, required this.person});

  @override
  State<PersonDetailsScreen> createState() => _PersonDetailsScreenState();
}

class _PersonDetailsScreenState extends State<PersonDetailsScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<DeviceModel> _assignedDevices = [];
  List<Map<String, dynamic>> _dayHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch assigned devices
      final devicesResponse = await Supabase.instance.client
          .from('devices')
          .select()
          .eq('person_id', widget.person.id);
      
      _assignedDevices = (devicesResponse as List).map((d) => DeviceModel.fromJson(d)).toList();

      // 2. Fetch history for selected day
      if (_assignedDevices.isNotEmpty && _selectedDay != null) {
        final startOfDay = DateTime(_selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));

        final deviceIds = _assignedDevices.map((d) => d.id).where((id) => id != null).toList();

        if (deviceIds.isNotEmpty) {
          final historyResponse = await Supabase.instance.client
              .from('device_history')
              .select()
              .inFilter('device_id', deviceIds)
              .gte('timestamp', startOfDay.toUtc().toIso8601String())
              .lt('timestamp', endOfDay.toUtc().toIso8601String())
              .order('timestamp', ascending: false);
              
          _dayHistory = List<Map<String, dynamic>>.from(historyResponse);
        } else {
          _dayHistory = [];
        }
      } else {
        _dayHistory = [];
      }
    } catch (e) {
      print('Error fetching person data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _assignDeviceDialog() async {
    // Fetch all devices from owned/shared networks to allow assignment
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final allDevicesResp = await Supabase.instance.client.from('devices').select();
    final allDevices = (allDevicesResp as List).map((d) => DeviceModel.fromJson(d)).toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text('Asignar Dispositivo', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: allDevices.length,
                  itemBuilder: (context, index) {
                    final device = allDevices[index];
                    final isAssigned = device.personId == widget.person.id;
                    final name = device.customName?.isNotEmpty == true ? device.customName! : (device.hostname ?? device.ipAddress);
                    
                    return CheckboxListTile(
                      title: Text(name, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
                      subtitle: Text(device.ipAddress, style: const TextStyle(color: Colors.grey)),
                      value: isAssigned,
                      activeColor: const Color(0xFF10B981),
                      onChanged: (bool? val) async {
                        try {
                          await Supabase.instance.client
                              .from('devices')
                              .update({'person_id': val == true ? widget.person.id : null})
                              .eq('id', device.id!);
                          setModalState(() {
                            // Local hack to reflect change instantly in modal
                            allDevices[index] = DeviceModel(
                              id: device.id,
                              networkId: device.networkId,
                              ipAddress: device.ipAddress,
                              macAddress: device.macAddress,
                              hostname: device.hostname,
                              brand: device.brand,
                              customName: device.customName,
                              iconType: device.iconType,
                              isFavorite: device.isFavorite,
                              lastSeen: device.lastSeen,
                              personId: val == true ? widget.person.id : null,
                            );
                          });
                          _fetchData();
                        } catch (e) {
                          print('Error assigning device: $e');
                        }
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  String _formatTime(String isoTime) {
    final dt = DateTime.parse(isoTime).toLocal();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.person.name, style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).colorScheme.surface,
        iconTheme: IconThemeData(color: Theme.of(context).textTheme.bodyLarge?.color),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_link),
            tooltip: 'Asignar Dispositivo',
            onPressed: _assignDeviceDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 10, 16),
            lastDay: DateTime.utc(2030, 3, 14),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              _fetchData();
            },
            calendarStyle: CalendarStyle(
              selectedDecoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
              todayDecoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.5), shape: BoxShape.circle),
              defaultTextStyle: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
              weekendTextStyle: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
            ),
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleTextStyle: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 16),
              leftChevronIcon: Icon(Icons.chevron_left, color: Theme.of(context).textTheme.bodyLarge?.color),
              rightChevronIcon: Icon(Icons.chevron_right, color: Theme.of(context).textTheme.bodyLarge?.color),
            ),
          ),
          const Divider(),
          if (_assignedDevices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Dispositivos: ${_assignedDevices.map((d) => d.customName ?? d.hostname ?? d.ipAddress).join(', ')}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _dayHistory.isEmpty
                    ? const Center(child: Text('Sin actividad este día', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: _dayHistory.length,
                        itemBuilder: (context, index) {
                          final event = _dayHistory[index];
                          final isOnline = event['status'] == 'online';
                          final device = _assignedDevices.firstWhere((d) => d.id == event['device_id'], orElse: () => DeviceModel(id: '', networkId: '', ipAddress: 'Unknown'));
                          final deviceName = device.customName ?? device.hostname ?? device.ipAddress;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            child: Row(
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: isOnline ? const Color(0xFF10B981) : Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    if (index != _dayHistory.length - 1)
                                      Container(
                                        width: 2,
                                        height: 40,
                                        color: Colors.grey.withOpacity(0.3),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isOnline ? 'Conectado' : 'Desconectado',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: isOnline ? const Color(0xFF10B981) : Colors.redAccent,
                                        ),
                                      ),
                                      Text(
                                        '$deviceName a las ${_formatTime(event['timestamp'])}',
                                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
