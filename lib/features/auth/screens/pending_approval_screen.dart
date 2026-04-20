import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/chick_mark_logo.dart';
import '../../../widgets/section_card.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../services/supabase/supabase_service.dart';
import '../providers/auth_provider.dart';

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  final _emailController = TextEditingController();
  bool _resetSent = false;
  bool _isSendingReset = false;
  String? _resetError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handlePasswordReset() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() {
        _resetError = 'Please enter a valid email.';
      });
      return;
    }

    setState(() {
      _isSendingReset = true;
      _resetError = null;
    });

    final sent = await SupabaseService().sendPasswordReset(email);
    if (!mounted) return;
    setState(() {
      _isSendingReset = false;
      _resetSent = sent;
      _resetError = sent ? null : 'Reset link could not be sent right now.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Pending Approval'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const ChickMarkLogo(logoSize: 100),
            const SizedBox(height: 32),
            SectionCard(
              child: Column(
                children: [
                  const Icon(
                    Icons.hourglass_empty,
                    size: 64,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Awaiting Approval',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Your account is currently pending approval from an administrator. You will receive an email once your account has been approved.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionCard(
              title: 'Forgot Password',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_resetSent) ...[
                    const Text(
                      'Enter your email address to receive a password reset link:',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
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
                    if (_resetError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _resetError!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isSendingReset ? null : _handlePasswordReset,
                      child: _isSendingReset
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Send Reset Link'),
                    ),
                  ] else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[700]),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Password reset link sent to ${_emailController.text}',
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () async {
                await context.read<AuthProvider>().logout();
                if (context.mounted) {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/login', (_) => false);
                }
              },
              child: const Text('Back to Login'),
            ),
          ],
        ),
      ),
    );
  }
}
