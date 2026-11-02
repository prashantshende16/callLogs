import 'package:shared_preferences/shared_preferences.dart';

/// AuthService manages the 4-digit security PIN for app access,
/// including first-time setup, PIN verification, and the master reset code (9876).
class AuthService {
  static const String _keyPin = 'app_security_pin';
  static const String masterResetCode = '9876';

  static bool _isAuthenticated = false;

  /// Returns true if the user has authenticated in this app session
  static bool get isAuthenticated => _isAuthenticated;

  /// Sets the authentication status for the current session
  static void setAuthenticated(bool value) {
    _isAuthenticated = value;
  }

  /// Checks if a 4-digit PIN has been configured
  static Future<bool> isPinSet() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_keyPin);
    return pin != null && pin.trim().length == 4;
  }

  /// Verifies if the entered PIN matches the saved PIN
  static Future<bool> verifyPin(String enteredPin) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(_keyPin);
    return savedPin != null && savedPin == enteredPin.trim();
  }

  /// Verifies if the entered code is the master reset code (9876)
  static bool verifyMasterResetCode(String code) {
    return code.trim() == masterResetCode;
  }

  /// Saves a new 4-digit PIN
  static Future<bool> setPin(String newPin) async {
    if (newPin.trim().length != 4) return false;
    final prefs = await SharedPreferences.getInstance();
    return await prefs.setString(_keyPin, newPin.trim());
  }

  /// Clears the saved PIN (used during reset)
  static Future<bool> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.remove(_keyPin);
  }
}
