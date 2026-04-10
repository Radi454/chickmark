import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../database/database_helper.dart';
import '../../models/user.dart';
import 'login_screen.dart';
import '../home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Text Controllers
  final _usernameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _locationController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // State Variables
  DateTime? _selectedBirthdate;
  String? _selectedGender;
  String? _selectedRole;
  
  bool _isBroiler = false;
  bool _isLayer = false;
  bool _isBreeder = false;
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _pickBirthdate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        _selectedBirthdate = date;
      });
    }
  }

  void _register() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedBirthdate == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your birthdate')));
        return;
      }
      if (_selectedGender == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your gender')));
        return;
      }
      if (_selectedRole == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select your role (Owner/Vet)')));
        return;
      }

      setState(() => _isLoading = true);
      
      final dbHelper = DatabaseHelper();
      final existingUser = await dbHelper.getUserByUsername(_usernameController.text);
      if (existingUser != null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username already exists!')));
        return;
      }

      final user = UserModel(
        id: const Uuid().v4(),
        username: _usernameController.text,
        mobile: _mobileController.text,
        email: _emailController.text,
        birthdate: _selectedBirthdate!.toIso8601String(),
        gender: _selectedGender!,
        location: _locationController.text,
        role: _selectedRole ?? '',
        isBroiler: _isBroiler,
        isLayer: _isLayer,
        isBreeder: _isBreeder,
        password: _passwordController.text,
        createdAt: DateTime.now().toIso8601String(),
      );

      await dbHelper.insertUser(user);
      
      if (!mounted) return;
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _locationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(ThemeData theme, String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: theme.colorScheme.surface,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM dd, yyyy');
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              theme.colorScheme.primary.withAlpha(20),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: FadeInUp(
                duration: const Duration(milliseconds: 600),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Create Account',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Sign up to get started with ChickMark',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withAlpha(179),
                        ),
                      ),
                      const SizedBox(height: 40),

                      // 1. Username
                      TextFormField(
                        controller: _usernameController,
                        decoration: _inputDecoration(theme, 'Username', Icons.person_outline),
                        validator: (v) => v!.isEmpty ? 'Enter username' : null,
                      ),
                      const SizedBox(height: 16),

                      // 8. Contact Info (Mobile)
                      TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        decoration: _inputDecoration(theme, 'Mobile Number', Icons.phone_outlined),
                        validator: (v) => v!.isEmpty ? 'Enter mobile number' : null,
                      ),
                      const SizedBox(height: 16),

                      // 8. Contact Info (Email)
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDecoration(theme, 'Email Address (Optional)', Icons.email_outlined),
                      ),
                      const SizedBox(height: 16),

                      // 4. Birthdate
                      InkWell(
                        onTap: _pickBirthdate,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: _inputDecoration(theme, 'Birthdate', Icons.calendar_today),
                          child: Text(
                            _selectedBirthdate == null 
                                ? 'Select Date' 
                                : dateFormat.format(_selectedBirthdate!),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 5. Gender
                      DropdownButtonFormField<String>(
                        decoration: _inputDecoration(theme, 'Gender', Icons.wc),
                        initialValue: _selectedGender,
                        items: ['Male', 'Female'].map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          setState(() {
                            _selectedGender = newValue;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // 6. Location
                      TextFormField(
                        controller: _locationController,
                        decoration: _inputDecoration(theme, 'Location', Icons.location_on_outlined),
                        validator: (v) => v!.isEmpty ? 'Enter your location' : null,
                      ),
                      const SizedBox(height: 24),

                      // 7. Role (Owner - Vet)
                      DropdownButtonFormField<String>(
                        decoration: _inputDecoration(theme, 'Role', Icons.work_outline),
                        initialValue: _selectedRole,
                        items: ['Owner', 'Vet'].map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          setState(() {
                            _selectedRole = newValue;
                          });
                        },
                      ),
                      
                      // 7. Breeding Type (Conditional logic)
                      if (_selectedRole != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Breeding Type', 
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(12),
                            color: theme.colorScheme.surface,
                          ),
                          child: Column(
                            children: [
                              CheckboxListTile(
                                title: const Text('Broiler'),
                                value: _isBroiler,
                                activeColor: theme.colorScheme.primary,
                                onChanged: (val) => setState(() => _isBroiler = val ?? false),
                              ),
                              CheckboxListTile(
                                title: const Text('Layer'),
                                value: _isLayer,
                                activeColor: theme.colorScheme.primary,
                                onChanged: (val) => setState(() => _isLayer = val ?? false),
                              ),
                              CheckboxListTile(
                                title: const Text('Breeder'),
                                value: _isBreeder,
                                activeColor: theme.colorScheme.primary,
                                onChanged: (val) => setState(() => _isBreeder = val ?? false),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // 2. Password
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                        ),
                        validator: (v) => v!.length < 6 ? 'Password too short' : null,
                      ),
                      const SizedBox(height: 16),

                      // 3. Confirm Password
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: 'Confirm Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: theme.colorScheme.surface,
                        ),
                        validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
                      ),
                      const SizedBox(height: 32),

                      // Register Button
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                          child: _isLoading
                              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Create Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Social Logins
                      Row(
                        children: [
                          Expanded(child: Divider(color: Colors.grey.shade400)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text('OR', style: TextStyle(color: Colors.grey.shade600)),
                          ),
                          Expanded(child: Divider(color: Colors.grey.shade400)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildSocialButton(theme, Icons.g_mobiledata, 'Google', Colors.red),
                          _buildSocialButton(theme, Icons.facebook, 'Facebook', Colors.blue.shade800),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Login Link
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            PageRouteBuilder(
                              pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
                              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                return FadeTransition(opacity: animation, child: child);
                              },
                            ),
                          );
                        },
                        child: Text.rich(
                          TextSpan(
                            text: 'Already have an account? ',
                            style: TextStyle(color: theme.colorScheme.onSurface.withAlpha(179)),
                            children: [
                              TextSpan(
                                text: 'Sign In',
                                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
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
        ),
      ),
    );
  }

  Widget _buildSocialButton(ThemeData theme, IconData icon, String tooltip, Color brandColor) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 32, color: brandColor),
        tooltip: tooltip,
        onPressed: () {
          // TODO: Implement Social Sign In
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign in with $tooltip initiated')));
        },
      ),
    );
  }
}
