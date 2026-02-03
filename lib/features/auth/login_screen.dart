import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../models/traces_user.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _plateNumberCtrl = TextEditingController();
  final _busModelCtrl = TextEditingController();
  final _contactNumberCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  late List<TextEditingController> _otpControllers;

  UserRole _role = UserRole.passenger;
  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _error;

  bool _isOtpSent = false;
  String? _currentOtp;
  bool _canResendOtp = true;
  int _resendSecondsLeft = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(6, (_) => TextEditingController());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _plateNumberCtrl.dispose();
    _busModelCtrl.dispose();
    _contactNumberCtrl.dispose();
    _otpCtrl.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<bool> sendOtpEmailViaMailJet(String email, String otp) async {
    const publicKey = "319057b52fb24a70056b67b81621cc96";
    const privateKey = "fac4af48e2a18b05e1dd178e7cacd48e";

    final response = await http.post(
      Uri.parse("https://api.mailjet.com/v3.1/send"),
      headers: {
        "Content-Type": "application/json",
        "Authorization":
            "Basic " + base64Encode(utf8.encode("$publicKey:$privateKey")),
      },
      body: jsonEncode({
        "Messages": [
          {
            "From": {"Email": "jayjayzjpa@gmail.com", "Name": "TRACES OTP"},
            "To": [
              {"Email": email},
            ],
            "Subject": "Your OTP Code",
            "TextPart": "Your OTP code is: $otp",
          },
        ],
      }),
    );

    return response.statusCode == 200;
  }

  void _updateOtpValue() {
    String otp = "";
    for (var box in _otpControllers) {
      otp += box.text.trim();
    }
    _otpCtrl.text = otp;
  }

  void startResendTimer() {
    _resendSecondsLeft = 30;
    _canResendOtp = false;

    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _canResendOtp = true;
          _resendSecondsLeft = 0;
        });
      } else {
        setState(() {
          _resendSecondsLeft -= 1;
        });
      }
    });
  }

  Future<void> sendOtp() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    for (var ctrl in _otpControllers) {
      ctrl.clear();
    }
    _otpCtrl.clear();

    try {
      // Delay to avoid Mailjet + Firebase rate limits
      await Future.delayed(const Duration(milliseconds: 800));

      final otp = (Random().nextInt(900000) + 100000).toString();
      _currentOtp = otp;

      final sent = await sendOtpEmailViaMailJet(email, otp);

      if (!sent) {
        setState(() => _error = 'Failed to send OTP. Try again.');
        return;
      }

      setState(() {
        _isOtpSent = true;
      });

      startResendTimer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "OTP sent! If you can't see it, check your Spam folder.",
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = 'Error sending OTP.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    if (mounted) {
      FocusScope.of(context).unfocus();
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = ref.read(authControllerProvider.notifier);

    try {
      if (_isLogin) {
        await auth.login(
          ref,
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );

        if (!mounted) return;

        final user = ref.read(authControllerProvider);
        if (user != null && mounted) {
          final target = user.role == UserRole.passenger
              ? '/passenger'
              : '/driver';
          Navigator.of(context).pushReplacementNamed(target);
        }
      } else {
        if (!_isOtpSent) {
          await sendOtp();
          return;
        }

        if (_otpCtrl.text.trim() != _currentOtp) {
          // Delay to prevent rapid retry abuse
          await Future.delayed(const Duration(milliseconds: 700));

          setState(() => _error = "Invalid OTP. Try again.");
          return;
        }

        if (_role == UserRole.driver) {
          await auth.registerDriver(
            ref,
            name: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text.trim(),
            plateNumber: _plateNumberCtrl.text.trim(),
            busModel: _busModelCtrl.text.trim(),
            contactNumber: _contactNumberCtrl.text.trim(),
          );
        } else {
          await auth.register(
            ref,
            name: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text.trim(),
            role: _role,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account created successfully! Please login.'),
              backgroundColor: Colors.green,
            ),
          );

          _nameCtrl.clear();
          _emailCtrl.clear();
          _passwordCtrl.clear();
          _plateNumberCtrl.clear();
          _busModelCtrl.clear();
          _contactNumberCtrl.clear();
          for (var ctrl in _otpControllers) {
            ctrl.clear();
          }

          setState(() {
            _isLogin = true;
            _isOtpSent = false;
            _currentOtp = null;
            _otpCtrl.clear();
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      final code = e.code;
      final message = e.message ?? 'Authentication failed.';

      if (code == 'too-many-requests') {
        setState(() {
          _error = "Too many attempts. Please try again in a few minutes.";
        });
      } else if (code == 'wrong-password' || code == 'invalid-credential') {
        setState(() {
          _error = 'Invalid email or password.';
        });
      } else if (code == 'user-not-found' || code == 'no-user') {
        setState(() {
          _error = 'Account not found. Please register first.';
        });
      } else {
        setState(() {
          _error = message;
        });
      }
    } on FirebaseException catch (e) {
      final code = e.code;
      if (code == 'too-many-requests') {
        setState(() {
          _error = "Too many attempts. Please try again in a few minutes.";
        });
      } else {
        setState(() {
          _error = e.message ?? 'Firebase error.';
        });
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('too-many-requests')) {
        setState(() {
          _error = "Too many attempts. Please try again in a few minutes.";
        });
      } else {
        setState(() => _error = msg);
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade400,
              Colors.blue.shade600,
              Colors.blue.shade800,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/images/school_bus.png',
                      width: 100,
                      height: 100,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'T.R.AC.E.S.S',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 3,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          offset: const Offset(2, 2),
                          blurRadius: 5,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'School Bus Tracking System',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.white, Colors.blue.shade50],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              Text(
                                _isLogin ? 'Welcome Back!' : 'Create Account',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isLogin
                                    ? 'Sign in to continue'
                                    : 'Sign up to get started',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (!_isLogin) ...[
                                TextFormField(
                                  controller: _nameCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Full Name',
                                    prefixIcon: Icon(
                                      Icons.person,
                                      color: Colors.blue.shade700,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.blue.shade700,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (!_isLogin &&
                                        (value == null ||
                                            value.trim().isEmpty)) {
                                      return 'Please enter your name';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                              ],
                              TextFormField(
                                controller: _emailCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(
                                    Icons.email,
                                    color: Colors.blue.shade700,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.blue.shade700,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) => value!.contains('@')
                                    ? null
                                    : 'Invalid email',
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _passwordCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: Icon(
                                    Icons.lock,
                                    color: Colors.blue.shade700,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                      color: Colors.blue.shade700,
                                      width: 2,
                                    ),
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.grey.shade600,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                obscureText: _obscurePassword,
                                validator: (value) => value!.length < 6
                                    ? 'Password must be at least 6 characters'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              if (!_isLogin) ...[
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: DropdownButtonFormField<UserRole>(
                                    value: _role,
                                    decoration: InputDecoration(
                                      labelText: 'Role',
                                      prefixIcon: Icon(
                                        Icons.badge,
                                        color: Colors.blue.shade700,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 16,
                                          ),
                                    ),
                                    items: const [
                                      DropdownMenuItem(
                                        value: UserRole.passenger,
                                        child: Text('Passenger (Student)'),
                                      ),
                                      DropdownMenuItem(
                                        value: UserRole.driver,
                                        child: Text('Driver'),
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _role = value!),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (_role == UserRole.driver) ...[
                                  TextFormField(
                                    controller: _plateNumberCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Plate Number',
                                      prefixIcon: Icon(
                                        Icons.credit_card,
                                        color: Colors.blue.shade700,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.blue.shade700,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _busModelCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Bus Model',
                                      prefixIcon: Icon(
                                        Icons.directions_bus,
                                        color: Colors.blue.shade700,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.blue.shade700,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _contactNumberCtrl,
                                    decoration: InputDecoration(
                                      labelText: 'Contact Number',
                                      prefixIcon: Icon(
                                        Icons.phone,
                                        color: Colors.blue.shade700,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.blue.shade700,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                if (_isOtpSent) ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.blue.shade200,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.security,
                                              color: Colors.blue.shade700,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              "Enter OTP Code",
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            const gap = 8.0;
                                            final boxWidth =
                                                ((constraints.maxWidth -
                                                            (gap * 5)) /
                                                        6)
                                                    .clamp(30.0, 48.0);

                                            return Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: List.generate(6, (
                                                index,
                                              ) {
                                                return Padding(
                                                  padding: EdgeInsets.only(
                                                    right: index == 5 ? 0 : gap,
                                                  ),
                                                  child: SizedBox(
                                                    width: boxWidth,
                                                    height: 55,
                                                    child: TextField(
                                                      onChanged: (value) {
                                                        if (value.isEmpty) {
                                                          if (index > 0) {
                                                            FocusScope.of(
                                                              context,
                                                            ).previousFocus();
                                                          }
                                                        } else {
                                                          if (index < 5) {
                                                            FocusScope.of(
                                                              context,
                                                            ).nextFocus();
                                                          } else {
                                                            FocusScope.of(
                                                              context,
                                                            ).unfocus();
                                                          }
                                                        }
                                                        _updateOtpValue();
                                                      },
                                                      controller:
                                                          _otpControllers[index],
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLength: 1,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      decoration: InputDecoration(
                                                        counterText: "",
                                                        filled: true,
                                                        fillColor: Colors.white,
                                                        contentPadding:
                                                            const EdgeInsets.all(
                                                              0,
                                                            ),
                                                        border: OutlineInputBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          borderSide:
                                                              BorderSide(
                                                                color: Colors
                                                                    .blue
                                                                    .shade300,
                                                              ),
                                                        ),
                                                        enabledBorder:
                                                            OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                              borderSide:
                                                                  BorderSide(
                                                                    color: Colors
                                                                        .blue
                                                                        .shade300,
                                                                  ),
                                                            ),
                                                        focusedBorder:
                                                            OutlineInputBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                              borderSide:
                                                                  BorderSide(
                                                                    color: Colors
                                                                        .blue
                                                                        .shade700,
                                                                    width: 2,
                                                                  ),
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                            );
                                          },
                                        ),

                                        const SizedBox(height: 12),
                                        TextButton.icon(
                                          onPressed: _canResendOtp
                                              ? sendOtp
                                              : null,
                                          icon: Icon(
                                            Icons.refresh,
                                            color: _canResendOtp
                                                ? Colors.blue.shade700
                                                : Colors.grey,
                                          ),
                                          label: Text(
                                            _canResendOtp
                                                ? "Resend OTP"
                                                : "Resend in $_resendSecondsLeft s",
                                            style: TextStyle(
                                              color: _canResendOtp
                                                  ? Colors.blue.shade700
                                                  : Colors.grey,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          "Check your Spam folder if you can't see it.",
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                              ],
                              if (_error != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.red.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.error_outline,
                                        color: Colors.red.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 3,
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _isLogin
                                              ? "Sign In"
                                              : "Create Account",
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  for (var ctrl in _otpControllers) {
                                    ctrl.clear();
                                  }
                                  setState(() {
                                    _isLogin = !_isLogin;
                                    _isOtpSent = false;
                                    _currentOtp = null;
                                    _otpCtrl.clear();
                                    _error = null;
                                  });
                                },
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      color: Colors.grey.shade700,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: _isLogin
                                            ? "Don't have an account? "
                                            : "Already have an account? ",
                                      ),
                                      TextSpan(
                                        text: _isLogin ? "Sign Up" : "Sign In",
                                        style: TextStyle(
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
