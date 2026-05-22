import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../widgets/chick_mark_logo.dart';
import '../../../widgets/section_card.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/auth/widgets/password_strength_indicator.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/gradient_app_bar.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _fullNameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  static const _kRememberMeKey = 'remember_me_email';

  @override
  void dispose() {
    _fullNameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_formKey.currentState!.validate()) {
      final email = _emailController.text.trim();
      final authProvider = context.read<AuthProvider>();
      final registered = await authProvider.register(
        _fullNameController.text.trim(),
        email,
        _passwordController.text,
      );
      var completed = registered;
      final remoteError = authProvider.errorMessage;
      if (!completed) {
        completed = await authProvider.registerLocalFallback(
          _fullNameController.text.trim(),
          email,
          password: _passwordController.text,
          remoteError: remoteError,
        );
      }
      if (!mounted || !completed) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRememberMeKey, email);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            registered
                ? 'Account created. Sign in to continue.'
                : 'Account created locally. Sign in with this email.',
          ),
        ),
      );
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const GradientAppBar(title: AppStrings.createAccount),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          if (authProvider.state == AuthState.pendingApproval) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushReplacementNamed('/pending-approval');
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  const ChickMarkLogo(logoSize: 80, animated: true),
                  const SizedBox(height: 24),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _fullNameController,
                          focusNode: _fullNameFocusNode,
                          decoration: _fieldDecoration(
                            labelText: 'Full Name',
                            icon: Icons.person_outline_rounded,
                          ),
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _emailFocusNode.requestFocus(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your full name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _emailController,
                          focusNode: _emailFocusNode,
                          decoration: _fieldDecoration(
                            labelText: 'Email',
                            icon: Icons.alternate_email_rounded,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _passwordFocusNode.requestFocus(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          decoration: _fieldDecoration(
                            labelText: 'Password',
                            icon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              _confirmPasswordFocusNode.requestFocus(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a password';
                            }
                            if (value.length < 8) {
                              return 'Password must be at least 8 characters';
                            }
                            if (!value.contains(RegExp(r'\d'))) {
                              return 'Password must contain at least one number';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            setState(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        PasswordStrengthIndicator(
                          password: _passwordController.text,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          focusNode: _confirmPasswordFocusNode,
                          decoration: _fieldDecoration(
                            labelText: 'Confirm Password',
                            icon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleRegister(),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password';
                            }
                            if (value != _passwordController.text) {
                              return 'Passwords do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.green[700],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Your account will be ready to use after it is created.',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (authProvider.state == AuthState.error)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              authProvider.errorMessage ?? 'An error occurred',
                              style: const TextStyle(color: Colors.red),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ElevatedButton(
                          onPressed: authProvider.state == AuthState.loading
                              ? null
                              : _handleRegister,
                          style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: authProvider.state == AuthState.loading
                              ? const CircularProgressIndicator()
                              : const Text(AppStrings.createAccount),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text('Back to Login'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String labelText,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: Icon(icon, size: 22, color: Colors.black54),
      prefixIconConstraints: const BoxConstraints(minWidth: 44),
      suffixIcon: suffixIcon,
    );
  }
}
