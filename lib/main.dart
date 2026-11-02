import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/call_record_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/pin_lock_screen.dart';
import 'services/native_call_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize native MethodChannel listeners
  NativeCallService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => CallRecordProvider()),
      ],
      child: const AndroidServicesApp(),
    ),
  );
}

class AndroidServicesApp extends StatelessWidget {
  const AndroidServicesApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android Services',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A), // Deep Slate Navy
          primary: const Color(0xFF1E3A8A),
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
        ),
      ),
      home: const RootGatekeeper(),
    );
  }
}

/// RootGatekeeper decides whether to show:
/// 1. 4-Digit Password setup (first app install)
/// 2. 4-Digit Password unlock (subsequent launches)
/// 3. Permission onboarding screen
/// 4. Main HomeScreen
class RootGatekeeper extends StatelessWidget {
  const RootGatekeeper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final permProvider = Provider.of<PermissionProvider>(context);

    if (authProvider.isLoading || permProvider.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
        ),
      );
    }

    // 1. First install: Ask to set 4-digit PIN (entered twice)
    if (!authProvider.isPinConfigured) {
      return const PinLockScreen(mode: PinScreenMode.setup);
    }

    // 2. Normal launch: Authenticate with 4-digit PIN
    if (!authProvider.isAuthenticated) {
      return const PinLockScreen(mode: PinScreenMode.unlock);
    }

    // 3. Permissions check
    if (!permProvider.areAllGranted) {
      return PermissionScreen(
        onPermissionsGranted: () {
          permProvider.checkPermissions();
        },
      );
    }

    // 4. Everything authenticated and granted
    return const HomeScreen();
  }
}

