import 'package:flutter/foundation.dart';
import '../services/auth_service.dart';

/// AuthProvider manages the state of app security PIN:
/// - Checking if PIN is configured on first install
/// - Handling authentication and unlocking
/// - Handling PIN creation and reset
class AuthProvider with ChangeNotifier {
  bool _isPinConfigured = false;
  bool _isAuthenticated = false;
  bool _isLoading = true;

  bool get isPinConfigured => _isPinConfigured;
  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;

  AuthProvider() {
    checkPinStatus();
  }

  /// Checks whether a PIN is already set in persistent storage
  Future<void> checkPinStatus() async {
    _isLoading = true;
    notifyListeners();

    _isPinConfigured = await AuthService.isPinSet();
    _isAuthenticated = AuthService.isAuthenticated;
    _isLoading = false;
    notifyListeners();
  }

  /// Verifies entered 4-digit PIN and unlocks session on success
  Future<bool> verifyAndUnlock(String pin) async {
    final valid = await AuthService.verifyPin(pin);
    if (valid) {
      _isAuthenticated = true;
      AuthService.setAuthenticated(true);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Verifies the master reset code (9876)
  bool verifyMasterCode(String code) {
    return AuthService.verifyMasterResetCode(code);
  }

  /// Saves a new 4-digit PIN and automatically unlocks session
  Future<bool> setPin(String newPin) async {
    final success = await AuthService.setPin(newPin);
    if (success) {
      _isPinConfigured = true;
      _isAuthenticated = true;
      AuthService.setAuthenticated(true);
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Locks the session
  void lock() {
    _isAuthenticated = false;
    AuthService.setAuthenticated(false);
    notifyListeners();
  }
}

