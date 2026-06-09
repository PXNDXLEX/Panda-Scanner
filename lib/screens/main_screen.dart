import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'tools_screen.dart';
import 'networks_screen.dart';
import 'people_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart'; // To access themeNotifier

import 'dart:async';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final AuthService _authService = AuthService();
  Timer? _notificationTimer;
  List<Map<String, dynamic>> _pendingInvites = [];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
    _notificationTimer = Timer.periodic(const Duration(seconds: 10), (_) => _fetchNotifications());
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchNotifications() async {
    final email = Supabase.instance.client.auth.currentUser?.email?.toLowerCase();
    if (email == null) return;

    try {
      final response = await Supabase.instance.client
          .from('network_shares')
          .select('id, network_id, guest_email, status, networks(name)')
          .eq('guest_email', email)
          .eq('status', 'pending');
          
      if (mounted) {
        setState(() {
          _pendingInvites = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('Error fetching notifications: $e');
    }
  }

  final List<Widget> _screens = [
    const DashboardScreen(), // Make sure DashboardScreen doesn't have an AppBar, we will put it here
    const NetworksScreen(),
    const PeopleScreen(),
    const ToolsScreen(),
    const GatewayWebviewScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panda Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(themeNotifier.value == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              setState(() {
                themeNotifier.value = themeNotifier.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
              });
            },
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () => _showNotificationsDialog(_pendingInvites),
              ),
              if (_pendingInvites.isNotEmpty)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text('${_pendingInvites.length}', style: const TextStyle(color: Colors.white, fontSize: 10), textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.signOut();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed('/');
              }
            },
          )
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.devices),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.list),
            label: 'Networks',
          ),
          NavigationDestination(
            icon: Icon(Icons.people),
            label: 'People',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal),
            label: 'Tools',
          ),
          NavigationDestination(
            icon: Icon(Icons.router),
            label: 'Gateway',
          ),
        ],
      ),
    );
  }

  void _showNotificationsDialog(List<Map<String, dynamic>> invites) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Notificaciones', style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: invites.isEmpty
                ? const Center(child: Text('No tienes invitaciones pendientes.'))
                : ListView.builder(
                    itemCount: invites.length,
                    itemBuilder: (context, index) {
                      final invite = invites[index];
                      final networkName = invite['networks'] != null ? invite['networks']['name'] : 'Unknown Network';
                      return ListTile(
                        title: const Text('Invitación de Red'),
                        subtitle: Text('Red: $networkName'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check, color: Colors.green),
                              onPressed: () async {
                                await Supabase.instance.client
                                    .from('network_shares')
                                    .update({'status': 'accepted'})
                                    .eq('id', invite['id']);
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () async {
                                await Supabase.instance.client
                                    .from('network_shares')
                                    .delete()
                                    .eq('id', invite['id']);
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
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
      },
    );
  }
}
