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
      child: const CallLoggerApp(),
    ),
  );
}

class CallLoggerApp extends StatelessWidget {
  const CallLoggerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call Logger',
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

/// RootGatekeeper decides whether to show the Permission onboarding screen
/// or navigate directly into HomeScreen based on active permission status.
class RootGatekeeper extends StatelessWidget {
  const RootGatekeeper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final permProvider = Provider.of<PermissionProvider>(context);

    if (permProvider.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!permProvider.areAllGranted) {
      return PermissionScreen(
        onPermissionsGranted: () {
          permProvider.checkPermissions();
        },
      );
    }

    return const HomeScreen();
  }
}

