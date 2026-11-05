import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/call_record_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/permission_screen.dart';
import 'services/native_call_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize native MethodChannel listeners
  NativeCallService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => CallRecordProvider()),
      ],
      child: const CallLogKeeperApp(),
    ),
  );
}

class CallLogKeeperApp extends StatelessWidget {
  const CallLogKeeperApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call Log Keeper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB), // Vibrant Blue
          primary: const Color(0xFF2563EB),
          surface: Colors.white,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0F172A),
        ),
      ),
      home: const RootGatekeeper(),
    );
  }
}

/// RootGatekeeper decides whether to show:
/// 1. Permission onboarding screen with full transparency rationale
/// 2. Main HomeScreen (Call history backup list)
class RootGatekeeper extends StatelessWidget {
  const RootGatekeeper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final permProvider = Provider.of<PermissionProvider>(context);

    if (permProvider.isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2563EB)),
        ),
      );
    }

    // 1. If required permissions are not granted, show transparent onboarding
    if (!permProvider.areAllGranted) {
      return PermissionScreen(
        onPermissionsGranted: () {
          permProvider.checkPermissions();
        },
      );
    }

    // 2. Normal launch: Open HomeScreen directly
    return const HomeScreen();
  }
}
