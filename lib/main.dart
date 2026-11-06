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
          seedColor: const Color(0xFF2563EB),
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
/// 1. 4-digit PIN setup (first install) or unlock window
/// 2. Permission onboarding screen if not granted
/// 3. Main HomeScreen
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

    // 1. First time setup: ask to set 4-digit password
    if (!authProvider.isPinConfigured) {
      return PinLockScreen(
        mode: PinScreenMode.setup,
        onSuccess: () {
          authProvider.checkPinStatus();
        },
      );
    }

    // 2. Normal launch: ask 4-digit password to unlock
    if (!authProvider.isAuthenticated) {
      return PinLockScreen(
        mode: PinScreenMode.unlock,
        onSuccess: () {
          authProvider.checkPinStatus();
        },
      );
    }

    // 3. If required permissions are not granted, show onboarding
    if (!permProvider.areAllGranted) {
      return PermissionScreen(
        onPermissionsGranted: () {
          permProvider.checkPermissions();
        },
      );
    }

    // 4. Authenticated & granted: Open HomeScreen
    return const HomeScreen();
  }
}
