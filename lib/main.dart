import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'screens/auth_screen.dart';

// Supabase Configuration
const String supabaseUrl = 'https://oeceatlcveduuuskvmea.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9lY2VhdGxjdmVkdXV1c2t2bWVhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA5NDM1MzIsImV4cCI6MjA5NjUxOTUzMn0.SvKSXj6JzOoeEPlQCGbtHkjEXoZfMNqqh414iChobHg';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

  // Setup Desktop Features (Windows only)
  if (Platform.isWindows) {
    await setupDesktop();
  }

  runApp(const PandaScannerApp());
}

Future<void> setupDesktop() async {
  // Window Manager Setup (Floating window, Always on Top)
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1024, 768),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Launch at Startup Setup
  try {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    launchAtStartup.setup(
      appName: packageInfo.appName,
      appPath: Platform.resolvedExecutable,
    );
    await launchAtStartup.enable();
  } catch (e) {
    debugPrint('Launch at startup setup failed: $e');
  }

  // System Tray Setup
  try {
    final SystemTray systemTray = SystemTray();
    await systemTray.initSystemTray(
      title: "Panda Scanner",
      iconPath: 'windows/runner/resources/app_icon.ico', // Default flutter icon
    );

    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(label: 'Show', onClicked: (menuItem) => windowManager.show()),
      MenuItemLabel(label: 'Hide', onClicked: (menuItem) => windowManager.hide()),
      MenuItemLabel(label: 'Exit', onClicked: (menuItem) => exit(0)),
    ]);
    await systemTray.setContextMenu(menu);

    systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.show();
      } else if (eventName == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });
  } catch (e) {
    debugPrint('System tray setup failed: $e');
  }
}

class PandaScannerApp extends StatelessWidget {
  const PandaScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;

    // Desktop Themes (Hacker Green / Dark Blue)
    final desktopLight = ThemeData.light().copyWith(
      scaffoldBackgroundColor: const Color(0xFFF1F5F9),
      primaryColor: const Color(0xFF10B981),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF10B981),
        secondary: Color(0xFF3B82F6),
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      useMaterial3: true,
    );

    final desktopDark = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      primaryColor: const Color(0xFF10B981),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF10B981),
        secondary: Color(0xFF3B82F6),
        surface: Color(0xFF1E293B),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E293B),
        elevation: 0,
        centerTitle: true,
      ),
      useMaterial3: true,
    );

    // Mobile Themes (Deep Purple / Amber)
    final mobileLight = ThemeData.light().copyWith(
      scaffoldBackgroundColor: const Color(0xFFF3E5F5), // Light purple
      primaryColor: Colors.deepPurple,
      colorScheme: const ColorScheme.light(
        primary: Colors.deepPurple,
        secondary: Colors.amber,
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 4,
        centerTitle: true,
      ),
      useMaterial3: true,
    );

    final mobileDark = ThemeData.dark().copyWith(
      scaffoldBackgroundColor: const Color(0xFF120024), // Very dark purple
      primaryColor: Colors.deepPurpleAccent,
      colorScheme: const ColorScheme.dark(
        primary: Colors.deepPurpleAccent,
        secondary: Colors.amberAccent,
        surface: Color(0xFF230344), // Elevated dark purple
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF230344),
        elevation: 4,
        centerTitle: true,
      ),
      useMaterial3: true,
    );

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, currentTheme, __) {
        return MaterialApp(
          title: 'Panda Scanner',
          debugShowCheckedModeBanner: false,
          themeMode: currentTheme,
          theme: isMobile ? mobileLight : desktopLight,
          darkTheme: isMobile ? mobileDark : desktopDark,
          home: const AuthScreen(),
        );
      }
    );
  }
}


