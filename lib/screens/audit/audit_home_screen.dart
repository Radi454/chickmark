import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/customer.dart';
import '../../models/flock.dart';
import '../../utils/app_theme.dart';
import '../../widgets/add_customer_dialog.dart';
import '../../widgets/add_flock_dialog.dart';
import '../../widgets/chickmark_logo.dart';
import 'hatch_analysis_screen.dart';
import 'setter_measurements_screen.dart';
import 'hatcher_measurements_screen.dart';
import 'vaccine_storage_screen.dart';
import 'egg_storage_screen.dart';

class AuditHomeScreen extends StatefulWidget {
  const AuditHomeScreen({super.key});

  @override
  State<AuditHomeScreen> createState() => _AuditHomeScreenState();
}

class _AuditHomeScreenState extends State<AuditHomeScreen> {
  Customer? _selectedCustomer;
  Flock? _selectedFlock;
  bool _isStarting = false;
  bool _isLoadingFlocks = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _onCustomerChanged(Customer? customer) async {
    setState(() {
      _selectedCustomer = customer;
      _selectedFlock = null;
      _isLoadingFlocks = true;
    });
    if (customer != null) {
      await context.read<AppProvider>().loadFlocks(customer.id);
    }
    if (mounted) setState(() => _isLoadingFlocks = false);
  }

  Future<void> _addCustomer() async {
    final customer = await showDialog<Customer>(
      context: context,
      builder: (_) => const AddCustomerDialog(),
    );
    if (customer != null && mounted) {
      setState(() {
        _selectedCustomer = customer;
        _selectedFlock = null;
        _isLoadingFlocks = true;
      });
      await context.read<AppProvider>().loadFlocks(customer.id);
      if (mounted) setState(() => _isLoadingFlocks = false);
    }
  }

  Future<void> _addFlock() async {
    if (_selectedCustomer == null) return;
    final flock = await showDialog<Flock>(
      context: context,
      builder: (_) => AddFlockDialog(customerId: _selectedCustomer!.id),
    );
    if (flock != null && mounted) {
      setState(() => _selectedFlock = flock);
    }
  }

  Future<void> _startSession() async {
    if (_selectedCustomer == null || _selectedFlock == null) return;
    setState(() => _isStarting = true);
    try {
      await context
          .read<AppProvider>()
          .startNewAudit(_selectedCustomer!, _selectedFlock!);
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        if (provider.currentSession != null) {
          return _ActiveSessionView(provider: provider);
        }
        return _buildNoSessionView(context, provider);
      },
    );
  }

  Widget _buildNoSessionView(BuildContext context, AppProvider provider) {
    final activeFlocks = provider.flocks
        .where((f) => f.status == 'active')
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Hero header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              decoration: const BoxDecoration(
                color: AppTheme.background,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFEDE0D8), width: 1),
                ),
              ),
              child: const Center(child: ChickMarkLogo(height: 88)),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Session picker card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'New Session',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Customer row
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<Customer>(
                                    initialValue: _selectedCustomer,
                                    decoration: const InputDecoration(
                                      labelText: 'Customer',
                                      prefixIcon: Icon(Icons.business, size: 18),
                                      isDense: true,
                                    ),
                                    items: provider.customers
                                        .map((c) => DropdownMenuItem(
                                              value: c,
                                              child: Text(
                                                c.name,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ))
                                        .toList(),
                                    onChanged: _onCustomerChanged,
                                    hint: const Text('Select customer'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  onPressed: _addCustomer,
                                  icon: const Icon(Icons.add, size: 18),
                                  tooltip: 'New customer',
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        AppTheme.primary.withValues(alpha: 0.12),
                                    foregroundColor: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Flock row
                            Row(
                              children: [
                                Expanded(
                                  child: _isLoadingFlocks
                                      ? const LinearProgressIndicator()
                                      : DropdownButtonFormField<Flock>(
                                          initialValue: _selectedFlock,
                                          decoration: const InputDecoration(
                                            labelText: 'Flock',
                                            prefixIcon: Icon(Icons.egg_outlined, size: 18),
                                            isDense: true,
                                          ),
                                          items: activeFlocks
                                              .map((f) => DropdownMenuItem(
                                                    value: f,
                                                    child: Text(
                                                      '${f.flockCode} — ${f.breed}',
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ))
                                              .toList(),
                                          onChanged: _selectedCustomer == null
                                              ? null
                                              : (f) => setState(
                                                  () => _selectedFlock = f),
                                          hint: Text(
                                            _selectedCustomer == null
                                                ? 'Select customer first'
                                                : 'Select flock',
                                          ),
                                          disabledHint: const Text(
                                              'Select customer first'),
                                        ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  onPressed: _selectedCustomer == null
                                      ? null
                                      : _addFlock,
                                  icon: const Icon(Icons.add, size: 18),
                                  tooltip: 'New flock',
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        AppTheme.primary.withValues(alpha: 0.12),
                                    foregroundColor: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Start session button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: (_selectedCustomer != null &&
                                        _selectedFlock != null &&
                                        !_isStarting)
                                    ? _startSession
                                    : null,
                                icon: _isStarting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.play_arrow),
                                label: const Text('Start Session'),
                                style: ElevatedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Recent Audits header
                    Row(
                      children: [
                        const Text(
                          'Recent Audits',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${provider.auditSessions.length} total',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Recent Audits list
                    if (provider.auditSessions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'No audits yet.\nSelect a customer and flock above to begin.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: provider.auditSessions.length,
                        itemBuilder: (context, index) {
                          final session = provider.auditSessions[index];
                          final completedCount = _effectiveCompletedCount(session.completedSections);
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.science,
                                    color: AppTheme.primary, size: 22),
                              ),
                              title: Text(
                                session.breed,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                              subtitle: Text(
                                DateFormat('dd MMM yyyy').format(session.auditDate),
                                style: const TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 12),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$completedCount/5',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: completedCount == 5
                                          ? AppTheme.green
                                          : AppTheme.accent,
                                    ),
                                  ),
                                  const Text(
                                    'sections',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                              onTap: () => provider.setCurrentSession(session),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers shared across session views ───────────────────────────────────────

bool _isHatchAnalysisDone(List<String> completed) {
  if (completed.contains('hatch_analysis')) return true;
  return completed.contains('hatchery_results') ||
      completed.contains('egg_breakout') ||
      completed.contains('chick_quality');
}

int _effectiveCompletedCount(List<String> completed) {
  final hatchDone = _isHatchAnalysisDone(completed) ? 1 : 0;
  final others = ['setter_measurements', 'hatcher_measurements',
      'vaccine_storage', 'egg_storage']
      .where(completed.contains)
      .length;
  return hatchDone + others;
}

// ── Active Session View ────────────────────────────────────────────────────────

class _ActiveSessionView extends StatelessWidget {
  final AppProvider provider;

  const _ActiveSessionView({required this.provider});

  static const _sections = [
    _SectionMeta(
      key: 'hatch_analysis',
      label: 'Hatch Analysis',
      icon: Icons.analytics,
    ),
    _SectionMeta(
      key: 'setter_measurements',
      label: 'Setter Measurements',
      icon: Icons.thermostat,
    ),
    _SectionMeta(
      key: 'hatcher_measurements',
      label: 'Hatcher Measurements',
      icon: Icons.device_thermostat,
    ),
    _SectionMeta(
      key: 'vaccine_storage',
      label: 'Vaccine Storage',
      icon: Icons.vaccines,
    ),
    _SectionMeta(
      key: 'egg_storage',
      label: 'Egg Storage',
      icon: Icons.inventory_2,
    ),
  ];

  void _navigateTo(BuildContext context, String sectionKey) {
    Widget screen;
    switch (sectionKey) {
      case 'hatch_analysis':
        screen = const HatchAnalysisScreen();
        break;
      case 'setter_measurements':
        screen = const SetterMeasurementsScreen();
        break;
      case 'hatcher_measurements':
        screen = const HatcherMeasurementsScreen();
        break;
      case 'vaccine_storage':
        screen = const VaccineStorageScreen();
        break;
      case 'egg_storage':
        screen = const EggStorageScreen();
        break;
      default:
        return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _endSession(BuildContext context, AppProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text(
          'This will close the current audit session. You can resume it later from Recent Audits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.clearCurrentSession();
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session saved. You can resume it from Recent Audits.'),
          backgroundColor: AppTheme.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = provider.currentSession!;
    final completed = session.completedSections;
    final completedCount = _effectiveCompletedCount(completed);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChickMarkAppBarTitle(),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.green.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.green.withValues(alpha: 0.6)),
              ),
              child: const Text(
                'ACTIVE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.green,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '$completedCount/5',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Session info card
          _SessionInfoCard(session: session),

          // Section grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.2,
              ),
              itemCount: _sections.length,
              itemBuilder: (context, index) {
                final meta = _sections[index];
                final isDone = meta.key == 'hatch_analysis'
                    ? _isHatchAnalysisDone(completed)
                    : completed.contains(meta.key);
                return _SectionGridButton(
                  meta: meta,
                  isDone: isDone,
                  onTap: () => _navigateTo(context, meta.key),
                );
              },
            ),
          ),

          // End session button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _endSession(context, provider),
                icon: const Icon(Icons.stop_circle_outlined, color: AppTheme.red),
                label: const Text(
                  'End Session',
                  style: TextStyle(
                      color: AppTheme.red, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionInfoCard extends StatelessWidget {
  final dynamic session;

  const _SessionInfoCard({required this.session});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 6),
                Text(
                  DateFormat('EEEE, dd MMM yyyy').format(session.auditDate),
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _InfoChip(
                    label: 'Breed',
                    value: session.breed,
                    icon: Icons.egg_alt,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoChip(
                    label: 'Flock Age',
                    value: '${session.flockAgeWeeks.toStringAsFixed(1)} wks',
                    icon: Icons.access_time,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoChip(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textSecondary)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionMeta {
  final String key;
  final String label;
  final IconData icon;

  const _SectionMeta(
      {required this.key, required this.label, required this.icon});
}

class _SectionGridButton extends StatelessWidget {
  final _SectionMeta meta;
  final bool isDone;
  final VoidCallback onTap;

  const _SectionGridButton({
    required this.meta,
    required this.isDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDone
                  ? AppTheme.green.withValues(alpha: 0.5)
                  : Colors.grey.shade200,
              width: isDone ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDone
                          ? AppTheme.green.withValues(alpha: 0.1)
                          : AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      meta.icon,
                      size: 26,
                      color: isDone ? AppTheme.green : AppTheme.primary,
                    ),
                  ),
                  if (isDone)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: AppTheme.green,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(Icons.check,
                            size: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                meta.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDone ? AppTheme.green : AppTheme.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
