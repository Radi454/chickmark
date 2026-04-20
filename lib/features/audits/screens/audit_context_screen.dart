import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/customers_provider.dart';
import '../../../data/models/flock_model.dart';
import '../../auth/providers/auth_provider.dart';
import 'chick_quality_screen.dart';
import 'hatch_analysis_screen.dart';
import 'setter_optimizing_screen.dart';
import 'hatcher_optimizing_screen.dart';
import 'egg_storage_screen.dart';

class AuditContextScreen extends StatefulWidget {
  final String auditType;

  const AuditContextScreen({super.key, required this.auditType});

  @override
  State<AuditContextScreen> createState() => _AuditContextScreenState();
}

class _AuditContextScreenState extends State<AuditContextScreen> {
  String? _selectedCustomerId;
  String? _selectedFlockId;
  String? _selectedBreed;
  final List<String> _breeds = [
    'Ross308',
    'Arbo',
    'Avian',
    'Cobb500',
    'Hubbard',
    'IR',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (!(auth.user?.canEditAudits ?? false)) {
        Navigator.of(context).pop();
        return;
      }
      context.read<CustomersProvider>().loadCustomers(currentUser: auth.user);
    });
  }

  @override
  Widget build(BuildContext context) {
    final customersProvider = context.watch<CustomersProvider>();
    final customers = customersProvider.filteredCustomers;

    final flocks = customersProvider.selectedCustomer?.id == _selectedCustomerId
        ? customersProvider.flocks
        : <FlockModel>[];

    final showFlockDropdown = [
      'Chick Quality',
      'Hatch Analysis',
      'Egg Storage',
    ].contains(widget.auditType);
    final showBreedDropdown = [
      'Setter Optimizing',
      'Hatcher Optimizing',
    ].contains(widget.auditType);

    return Scaffold(
      appBar: GradientAppBar(title: widget.auditType),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer dropdown
            _buildDropdownCard(
              icon: Icons.business,
              title: 'Customer',
              value: _selectedCustomerId,
              items: customers.map((c) => c.id).toList(),
              itemLabels: customers.map((c) => c.name).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCustomerId = value;
                  _selectedFlockId = null; // Reset flock when customer changes
                });
                final matches = customers.where((c) => c.id == value);
                final customer = matches.isEmpty ? null : matches.first;
                if (customer != null) {
                  customersProvider.selectCustomer(customer);
                }
              },
            ),

            const SizedBox(height: 16),

            // Flock dropdown (for CQ/HA/ES)
            if (showFlockDropdown) ...[
              _buildDropdownCard(
                icon: Icons.pets,
                title: 'Flock',
                value: _selectedFlockId,
                items: flocks.map((f) => f.id).toList(),
                itemLabels: flocks.map((f) => f.flockId).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedFlockId = value;
                  });
                },
              ),
              const SizedBox(height: 16),
            ],

            // Breed dropdown (for SO/HO)
            if (showBreedDropdown) ...[
              _buildDropdownCard(
                icon: Icons.egg,
                title: 'Breed',
                value: _selectedBreed,
                items: _breeds,
                itemLabels: _breeds,
                onChanged: (value) {
                  setState(() {
                    _selectedBreed = value;
                  });
                },
              ),
              const SizedBox(height: 16),
            ],

            // Continue button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _canContinue() ? _handleContinue : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownCard({
    required IconData icon,
    required String title,
    required String? value,
    required List<String> items,
    required List<String> itemLabels,
    required Function(String?) onChanged,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: items.contains(value) ? value : null,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: items.asMap().entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.value,
                  child: Text(itemLabels[entry.key]),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }

  bool _canContinue() {
    if (_selectedCustomerId == null) return false;

    if ([
      'Chick Quality',
      'Hatch Analysis',
      'Egg Storage',
    ].contains(widget.auditType)) {
      return _selectedFlockId != null;
    }

    if ([
      'Setter Optimizing',
      'Hatcher Optimizing',
    ].contains(widget.auditType)) {
      return _selectedBreed != null;
    }

    return false;
  }

  void _handleContinue() {
    final contextData = AuditContextData(
      auditType: widget.auditType,
      customerId: _selectedCustomerId!,
      flockId: _selectedFlockId,
      breed: _selectedBreed,
      date: DateTime.now().toIso8601String().split('T')[0],
    );

    Widget screen;
    switch (widget.auditType) {
      case 'Chick Quality':
        screen = ChickQualityScreen(context: contextData);
        break;
      case 'Hatch Analysis':
        screen = HatchAnalysisScreen(context: contextData);
        break;
      case 'Setter Optimizing':
        screen = SetterOptimizingScreen(context: contextData);
        break;
      case 'Hatcher Optimizing':
        screen = HatcherOptimizingScreen(context: contextData);
        break;
      case 'Egg Storage':
        screen = EggStorageScreen(context: contextData);
        break;
      default:
        return;
    }

    Navigator.push(context, MaterialPageRoute(builder: (context) => screen));
  }
}

class AuditContextData {
  final String auditType;
  final String customerId;
  final String? flockId;
  final String? breed;
  final String date;

  AuditContextData({
    required this.auditType,
    required this.customerId,
    this.flockId,
    this.breed,
    required this.date,
  });
}
