import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/app_theme.dart';

class BenchmarksScreen extends StatefulWidget {
  const BenchmarksScreen({super.key});

  @override
  State<BenchmarksScreen> createState() => _BenchmarksScreenState();
}

class _BenchmarksScreenState extends State<BenchmarksScreen> {
  static const List<String> _breeds = [
    'All',
    'Ross 308',
    'Cobb 500',
    'Lohmann',
    'Arbor Acres',
  ];

  static const List<int> _ages = [30, 35, 40, 45, 50];

  static const List<String> _parameters = [
    'Hatchability',
    'Fertility',
    'HOF',
    'Infertile',
    'EarlyDead',
    'LateDead',
  ];

  String _selectedBreed = 'Ross 308';
  int _selectedAge = 35;

  // Rebuilt whenever filters change
  late Future<Map<String, double?>> _benchmarksFuture;

  @override
  void initState() {
    super.initState();
    _loadBenchmarks();
  }

  void _loadBenchmarks() {
    setState(() {
      _benchmarksFuture = _fetchAll();
    });
  }

  Future<Map<String, double?>> _fetchAll() async {
    final db = context.read<AppProvider>().db;
    final results = <String, double?>{};
    for (final param in _parameters) {
      results[param] =
          await db.getBenchmark(_selectedBreed, _selectedAge.toDouble(), param);
    }
    return results;
  }

  // ── Edit dialog ────────────────────────────────────────────────────────────

  void _showEditDialog(String parameter, double? currentValue) {
    final ctrl =
        TextEditingController(text: currentValue?.toStringAsFixed(2) ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $parameter'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$_selectedBreed  •  $_selectedAge weeks',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: parameter,
                  suffixText: '%',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null) return 'Enter a valid number';
                  if (parsed < 0 || parsed > 100) return '0 – 100 only';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final newValue = double.parse(ctrl.text.trim());
              final db = context.read<AppProvider>().db;
              await db.updateBenchmarkValue(
                  _selectedBreed, _selectedAge, parameter, newValue);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadBenchmarks();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  // ── Reset confirmation ──────────────────────────────────────────────────────

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to Defaults?'),
        content: const Text(
          'This will restore all benchmark values to the factory defaults. '
          'Any custom changes will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () async {
              final db = context.read<AppProvider>().db;
              await db.resetBenchmarks();
              if (ctx.mounted) Navigator.pop(ctx);
              _loadBenchmarks();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Benchmarks reset to defaults.'),
                    backgroundColor: AppTheme.green,
                  ),
                );
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Benchmark Management'),
        actions: [
          TextButton.icon(
            onPressed: _confirmReset,
            icon: const Icon(Icons.restore, color: Colors.white),
            label: const Text(
              'Reset to Defaults',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Filter row ──────────────────────────────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                // Breed dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Breed',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedBreed,
                            isExpanded: true,
                            items: _breeds
                                .map((b) => DropdownMenuItem(
                                      value: b,
                                      child: Text(b,
                                          style: const TextStyle(fontSize: 13)),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedBreed = v);
                              _loadBenchmarks();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Age dropdown
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Age (weeks)',
                          style: TextStyle(
                              fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedAge,
                            isExpanded: true,
                            items: _ages
                                .map((a) => DropdownMenuItem(
                                      value: a,
                                      child: Text('$a wks',
                                          style: const TextStyle(fontSize: 13)),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedAge = v);
                              _loadBenchmarks();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Table header ───────────────────────────────────────────────────
          Container(
            color: AppTheme.primary.withValues(alpha: 0.07),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: const [
                Expanded(
                  flex: 3,
                  child: Text('Parameter',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.textPrimary)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Value (%)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.textPrimary)),
                ),
                SizedBox(
                  width: 64,
                  child: Text('Action',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppTheme.textPrimary)),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── FutureBuilder table body ────────────────────────────────────────
          Expanded(
            child: FutureBuilder<Map<String, double?>>(
              future: _benchmarksFuture,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error loading benchmarks.\n${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.red),
                    ),
                  );
                }

                final data = snap.data ?? {};
                final isAllBreed = _selectedBreed == 'All';

                if (isAllBreed) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Select a specific breed to view and edit benchmarks.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 14),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: _parameters.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (ctx, i) {
                    final param = _parameters[i];
                    final value = data[param];
                    return _BenchmarkRow(
                      parameter: param,
                      value: value,
                      onEdit: () => _showEditDialog(param, value),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Benchmark row widget ──────────────────────────────────────────────────────

class _BenchmarkRow extends StatelessWidget {
  final String parameter;
  final double? value;
  final VoidCallback onEdit;

  const _BenchmarkRow({
    required this.parameter,
    required this.value,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Parameter label
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  parameter,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary),
                ),
                Text(
                  _paramDescription(parameter),
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          // Value
          Expanded(
            flex: 2,
            child: Text(
              value != null ? '${value!.toStringAsFixed(2)}%' : '—',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: value != null ? AppTheme.secondary : AppTheme.textSecondary,
              ),
            ),
          ),
          // Edit button
          SizedBox(
            width: 64,
            child: Center(
              child: IconButton(
                icon: const Icon(Icons.edit_outlined,
                    size: 20, color: AppTheme.primary),
                tooltip: 'Edit',
                onPressed: onEdit,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _paramDescription(String param) {
    switch (param) {
      case 'Hatchability':
        return 'Hatched / total eggs set';
      case 'Fertility':
        return 'Fertile / total eggs set';
      case 'HOF':
        return 'Hatch of fertile';
      case 'Infertile':
        return 'Infertile eggs (%)';
      case 'EarlyDead':
        return 'Early dead embryos (%)';
      case 'LateDead':
        return 'Late dead embryos (%)';
      default:
        return '';
    }
  }
}
