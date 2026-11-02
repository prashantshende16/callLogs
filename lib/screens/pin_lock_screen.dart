import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

enum PinScreenMode {
  setup, // First install: enter 4 digits twice to set
  unlock, // Normal launch: enter 4 digits to unlock
  change, // Settings: enter old pin/master code, then enter new pin twice
}

class PinLockScreen extends StatefulWidget {
  final PinScreenMode mode;
  final VoidCallback? onSuccess;

  const PinLockScreen({
    Key? key,
    this.mode = PinScreenMode.unlock,
    this.onSuccess,
  }) : super(key: key);

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  late PinScreenMode _currentMode;

  // Keypad entered digits
  String _enteredPin = '';

  // For setup/change mode:
  int _step = 1; // 1: first enter, 2: confirm enter
  String _firstEnteredPin = '';
  String? _errorMessage;

  // Change mode specific step (1: verify old, 2: enter new, 3: confirm new)
  int _changeStep = 1;

  @override
  void initState() {
    super.initState();
    _currentMode = widget.mode;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentMode == PinScreenMode.change,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A), // Dark slate / secure theme
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 24),
              // Optional back button only when changing PIN from settings
              if (_currentMode == PinScreenMode.change)
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              const Spacer(flex: 1),

              // Shield Icon & Title
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.4), width: 2),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  size: 38,
                  color: Color(0xFF60A5FA),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                _getTitle(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _getSubtitle(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),

              // 4 PIN Dots Indicator
              _buildPinDots(),
              const SizedBox(height: 16),

              // Error Message
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                const SizedBox(height: 20),

              const Spacer(flex: 2),

              // Numeric Keypad
              _buildKeypad(),
              const SizedBox(height: 16),

              // Forgot Password Option (only in unlock mode)
              if (_currentMode == PinScreenMode.unlock)
                TextButton(
                  onPressed: _showForgotPasswordDialog,
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(
                      color: Color(0xFF93C5FD),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _getTitle() {
    if (_currentMode == PinScreenMode.setup) {
      return _step == 1 ? 'Set 4-Digit Password' : 'Confirm Password';
    } else if (_currentMode == PinScreenMode.change) {
      if (_changeStep == 1) return 'Verify Current Password';
      if (_changeStep == 2) return 'Enter New 4-Digit PIN';
      return 'Confirm New PIN';
    } else {
      return 'Android Services';
    }
  }

  String _getSubtitle() {
    if (_currentMode == PinScreenMode.setup) {
      return _step == 1
          ? 'Create a 4-digit security password to protect access to the app'
          : 'Please re-enter your 4-digit password to confirm';
    } else if (_currentMode == PinScreenMode.change) {
      if (_changeStep == 1) return 'Enter your current PIN or Master Reset Code (9876)';
      if (_changeStep == 2) return 'Choose a new 4-digit passcode';
      return 'Re-enter your new 4-digit passcode';
    } else {
      return 'Enter your 4-digit password to continue';
    }
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (index) {
        final isFilled = index < _enteredPin.length;
        final hasError = _errorMessage != null;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hasError
                ? const Color(0xFFEF4444)
                : isFilled
                    ? const Color(0xFF3B82F6)
                    : Colors.transparent,
            border: Border.all(
              color: hasError
                  ? const Color(0xFFEF4444)
                  : isFilled
                      ? const Color(0xFF3B82F6)
                      : Colors.white38,
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildKeypad() {
    final buttons = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', 'delete'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: buttons.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((val) {
                if (val.isEmpty) {
                  return const SizedBox(width: 72, height: 72);
                }
                if (val == 'delete') {
                  return InkWell(
                    onTap: _onDeletePressed,
                    borderRadius: BorderRadius.circular(36),
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.backspace_outlined,
                        color: Colors.white70,
                        size: 26,
                      ),
                    ),
                  );
                }
                return InkWell(
                  onTap: () => _onDigitPressed(val),
                  borderRadius: BorderRadius.circular(36),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      val,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _onDigitPressed(String digit) {
    if (_enteredPin.length >= 4) return;
    setState(() {
      _errorMessage = null;
      _enteredPin += digit;
    });

    if (_enteredPin.length == 4) {
      // Defer processing to let the 4th dot light up
      Future.delayed(const Duration(milliseconds: 120), () {
        _processCompletePin(_enteredPin);
      });
    }
  }

  void _onDeletePressed() {
    if (_enteredPin.isNotEmpty) {
      setState(() {
        _errorMessage = null;
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
      });
    }
  }

  Future<void> _processCompletePin(String pin) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (_currentMode == PinScreenMode.setup) {
      if (_step == 1) {
        // First entry done, ask for confirmation
        setState(() {
          _firstEnteredPin = pin;
          _enteredPin = '';
          _step = 2;
          _errorMessage = null;
        });
      } else {
        // Confirmation entry
        if (pin == _firstEnteredPin) {
          // Both match! Save PIN
          await auth.setPin(pin);
          if (widget.onSuccess != null) {
            widget.onSuccess!();
          }
        } else {
          // Mismatch, reset to step 1
          setState(() {
            _errorMessage = 'Passwords do not match. Please try again.';
            _enteredPin = '';
            _firstEnteredPin = '';
            _step = 1;
          });
        }
      }
    } else if (_currentMode == PinScreenMode.unlock) {
      final success = await auth.verifyAndUnlock(pin);
      if (success) {
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        }
      } else {
        setState(() {
          _errorMessage = 'Incorrect password. Try again or tap Forgot Password.';
          _enteredPin = '';
        });
      }
    } else if (_currentMode == PinScreenMode.change) {
      if (_changeStep == 1) {
        // Verify current PIN or master reset code (9876)
        final isOldValid = await auth.verifyAndUnlock(pin);
        final isMaster = auth.verifyMasterCode(pin);

        if (isOldValid || isMaster) {
          setState(() {
            _changeStep = 2;
            _enteredPin = '';
            _errorMessage = null;
          });
        } else {
          setState(() {
            _errorMessage = 'Invalid current PIN. Enter current PIN or 9876.';
            _enteredPin = '';
          });
        }
      } else if (_changeStep == 2) {
        // Enter new PIN
        setState(() {
          _firstEnteredPin = pin;
          _enteredPin = '';
          _changeStep = 3;
          _errorMessage = null;
        });
      } else if (_changeStep == 3) {
        // Confirm new PIN
        if (pin == _firstEnteredPin) {
          await auth.setPin(pin);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Password updated successfully!'),
                backgroundColor: Color(0xFF10B981),
              ),
            );
            Navigator.of(context).pop();
          }
        } else {
          setState(() {
            _errorMessage = 'Passwords do not match. Try entering new PIN again.';
            _enteredPin = '';
            _firstEnteredPin = '';
            _changeStep = 2;
          });
        }
      }
    }
  }

  /// Displays the Master Reset Code dialog
  void _showForgotPasswordDialog() {
    final resetController = TextEditingController();
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.lock_reset_rounded, color: Color(0xFF60A5FA)),
                  SizedBox(width: 10),
                  Text(
                    'Reset Password',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter the 4-digit Master Reset Code to reset your password:',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: resetController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      letterSpacing: 8,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '••••',
                      hintStyle: const TextStyle(color: Colors.white30, letterSpacing: 8),
                      filled: true,
                      fillColor: const Color(0xFF0F172A),
                      errorText: dialogError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF3B82F6)),
                      ),
                      counterText: '',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                  onPressed: () {
                    final enteredCode = resetController.text.trim();
                    final auth = Provider.of<AuthProvider>(context, listen: false);

                    if (auth.verifyMasterCode(enteredCode)) {
                      Navigator.of(ctx).pop();
                      // Transition current screen in-place to setup mode so user creates a new PIN
                      setState(() {
                        _currentMode = PinScreenMode.setup;
                        _enteredPin = '';
                        _firstEnteredPin = '';
                        _step = 1;
                        _errorMessage = null;
                      });
                    } else {
                      setDialogState(() {
                        dialogError = 'Invalid Master Code (9876)';
                      });
                    }
                  },
                  child: const Text('Verify & Reset'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
