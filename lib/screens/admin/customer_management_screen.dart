import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/customer.dart';
import '../../models/flock.dart';
import '../../models/audit_session.dart';
import '../../utils/app_theme.dart';
import '../../widgets/add_customer_dialog.dart';

class CustomerManagementScreen extends StatefulWidget {
  const CustomerManagementScreen({super.key});

  @override
  State<CustomerManagementScreen> createState() =>
      _CustomerManagementScreenState();
}

class _CustomerManagementScreenState extends State<CustomerManagementScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // Which customer IDs are expanded to show their flocks
  final Set<String> _expanded = {};

  // Flock lists cached per customer id
  final Map<String, List<Flock>> _flockCache = {};

  // Last audit date cache per customer id
  final Map<String, DateTime?> _lastAuditCache = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<void> _toggleExpand(String customerId) async {
    if (_expanded.contains(customerId)) {
      setState(() => _expanded.remove(customerId));
      return;
    }
    // Load flocks for this customer
    final provider = context.read<AppProvider>();
    final flocks = await provider.db.getFlocksByCustomer(customerId);
    final sessions = await provider.db.getAuditSessions(customerId: customerId);
    final lastAudit = sessions.isNotEmpty ? sessions.first.auditDate : null;
    setState(() {
      _flockCache[customerId] = flocks;
      _lastAuditCache[customerId] = lastAudit;
      _expanded.add(customerId);
    });
  }

  int _activeFlockCount(String customerId) {
    final flocks = _flockCache[customerId] ?? [];
    return flocks.where((f) => f.status == 'active').length;
  }

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _showAddCustomerDialog() {
    showDialog(
      context: context,
      builder: (ctx) => const AddCustomerDialog(),
    );
  }

  void _showEditCustomerDialog(Customer customer) {
    final nameCtrl = TextEditingController(text: customer.name);
    final emailCtrl = TextEditingController(text: customer.email ?? '');
    final phoneCtrl = TextEditingController(text: customer.phone ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Customer'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
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
              final updated = Customer(
                id: customer.id,
                name: nameCtrl.text.trim(),
                email: emailCtrl.text.trim().isEmpty
                    ? null
                    : emailCtrl.text.trim(),
                phone: phoneCtrl.text.trim().isEmpty
                    ? null
                    : phoneCtrl.text.trim(),
                address: customer.address,
                createdAt: customer.createdAt,
              );
              await context.read<AppProvider>().updateCustomer(updated);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
    });
  }

  void _confirmDeleteCustomer(Customer customer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text(
            'This will permanently delete "${customer.name}" and all associated data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.red),
            onPressed: () async {
              final provider = context.read<AppProvider>();
              await provider.db.deleteCustomer(customer.id);
              await provider.loadCustomers();
              if (!mounted) return;
              setState(() {
                _expanded.remove(customer.id);
                _flockCache.remove(customer.id);
                _lastAuditCache.remove(customer.id);
              });
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAddFlockDialog(String customerId) {
    final codeCtrl = TextEditingController();
    final breedCtrl = TextEditingController();
    DateTime entryDate = DateTime.now();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add Flock'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(labelText: 'Flock Code *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: breedCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Breed *',
                        hintText: 'e.g. Ross 308'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Entry Date',
                        style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      DateFormat('dd MMM yyyy').format(entryDate),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    trailing: const Icon(Icons.calendar_today,
                        color: AppTheme.primary),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: entryDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDlgState(() => entryDate = picked);
                      }
                    },
                  ),
                ],
              ),
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
                final provider = context.read<AppProvider>();
                await provider.createFlock(
                  customerId,
                  codeCtrl.text.trim(),
                  breedCtrl.text.trim(),
                  entryDate,
                );
                // Refresh flock cache
                final updatedFlocks =
                    await provider.db.getFlocksByCustomer(customerId);
                setState(() => _flockCache[customerId] = updatedFlocks);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    ).then((_) {
      codeCtrl.dispose();
      breedCtrl.dispose();
    });
  }

  void _showEditFlockDialog(Flock flock) {
    final codeCtrl = TextEditingController(text: flock.flockCode);
    final breedCtrl = TextEditingController(text: flock.breed);
    DateTime entryDate = flock.entryDate;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Edit Flock'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: codeCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Flock Code *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: breedCtrl,
                    decoration: const InputDecoration(labelText: 'Breed *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Entry Date',
                        style: TextStyle(fontSize: 13)),
                    subtitle: Text(
                      DateFormat('dd MMM yyyy').format(entryDate),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    trailing: const Icon(Icons.calendar_today,
                        color: AppTheme.primary),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: entryDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDlgState(() => entryDate = picked);
                      }
                    },
                  ),
                ],
              ),
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
                final updated = Flock(
                  id: flock.id,
                  customerId: flock.customerId,
                  flockCode: codeCtrl.text.trim(),
                  breed: breedCtrl.text.trim(),
                  entryDate: entryDate,
                  status: flock.status,
                  createdAt: flock.createdAt,
                );
                final provider = context.read<AppProvider>();
                await provider.updateFlock(updated);
                final updatedFlocks =
                    await provider.db.getFlocksByCustomer(flock.customerId);
                setState(
                    () => _flockCache[flock.customerId] = updatedFlocks);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    ).then((_) {
      codeCtrl.dispose();
      breedCtrl.dispose();
    });
  }

  void _markAsSold(Flock flock) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Sold?'),
        content: Text('Mark flock "${flock.flockCode}" as sold?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber),
            onPressed: () async {
              final provider = context.read<AppProvider>();
              await provider.markFlockAsSold(flock.id);
              final updatedFlocks =
                  await provider.db.getFlocksByCustomer(flock.customerId);
              setState(
                  () => _flockCache[flock.customerId] = updatedFlocks);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Mark Sold'),
          ),
        ],
      ),
    );
  }

  void _showFlockHistory(Flock flock) async {
    final sessions =
        await context.read<AppProvider>().getFlockAudits(flock.id);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _FlockHistorySheet(flock: flock, sessions: sessions),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<AppProvider>().customers;
    final filtered = customers
        .where((c) =>
            c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search customers…',
                prefixIcon:
                    const Icon(Icons.search, color: AppTheme.textSecondary),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),

          // Customer list
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline,
                            size: 48,
                            color: AppTheme.textSecondary
                                .withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        Text(
                          _query.isEmpty
                              ? 'No customers yet.\nTap + to add one.'
                              : 'No results for "$_query".',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 80),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final customer = filtered[i];
                      final isExpanded = _expanded.contains(customer.id);
                      final flocks = _flockCache[customer.id] ?? [];
                      final lastAudit = _lastAuditCache[customer.id];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            // Customer header
                            ListTile(
                              onTap: () => _toggleExpand(customer.id),
                              leading: CircleAvatar(
                                backgroundColor:
                                    AppTheme.primary.withValues(alpha: 0.12),
                                child: Text(
                                  customer.name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                customer.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (isExpanded)
                                    Text(
                                      '${_activeFlockCount(customer.id)} active flock(s)',
                                      style: const TextStyle(fontSize: 12),
                                    )
                                  else
                                    Text(
                                      customer.email ?? customer.phone ?? '',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (lastAudit != null)
                                    Text(
                                      'Last audit: ${DateFormat('dd MMM yyyy').format(lastAudit)}',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textSecondary),
                                    ),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 20, color: AppTheme.primary),
                                    onPressed: () =>
                                        _showEditCustomerDialog(customer),
                                    tooltip: 'Edit',
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 20, color: AppTheme.red),
                                    onPressed: () =>
                                        _confirmDeleteCustomer(customer),
                                    tooltip: 'Delete',
                                  ),
                                  Icon(
                                    isExpanded
                                        ? Icons.keyboard_arrow_up
                                        : Icons.keyboard_arrow_down,
                                    color: AppTheme.textSecondary,
                                  ),
                                ],
                              ),
                            ),

                            // Expanded flock list
                            if (isExpanded) ...[
                              const Divider(height: 1),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Row(
                                  children: [
                                    const Text('Flocks',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                            color: AppTheme.textSecondary)),
                                    const Spacer(),
                                    TextButton.icon(
                                      onPressed: () =>
                                          _showAddFlockDialog(customer.id),
                                      icon: const Icon(Icons.add, size: 16),
                                      label: const Text('Add Flock'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: AppTheme.primary,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (flocks.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                                  child: Text('No flocks yet.',
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 13)),
                                )
                              else
                                ...flocks.map((flock) =>
                                    _FlockTile(
                                      flock: flock,
                                      onEdit: () =>
                                          _showEditFlockDialog(flock),
                                      onMarkSold: flock.status == 'active'
                                          ? () => _markAsSold(flock)
                                          : null,
                                      onHistory: () =>
                                          _showFlockHistory(flock),
                                    )),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCustomerDialog,
        backgroundColor: AppTheme.accent,
        foregroundColor: Colors.white,
        tooltip: 'Add Customer',
        child: const Icon(Icons.person_add_outlined),
      ),
    );
  }
}

// ── Flock tile ─────────────────────────────────────────────────────────────

class _FlockTile extends StatelessWidget {
  final Flock flock;
  final VoidCallback onEdit;
  final VoidCallback? onMarkSold;
  final VoidCallback onHistory;

  const _FlockTile({
    required this.flock,
    required this.onEdit,
    this.onMarkSold,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final ageWeeks = flock.currentAgeWeeks.toStringAsFixed(1);
    final isSold = flock.status == 'sold';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isSold
            ? Colors.grey.shade100
            : AppTheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSold
              ? Colors.grey.shade300
              : AppTheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      flock.flockCode,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isSold
                            ? AppTheme.textSecondary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isSold ? Colors.grey : AppTheme.green)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isSold ? 'Sold' : 'Active',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isSold ? Colors.grey.shade600 : AppTheme.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${flock.breed}  •  $ageWeeks wks old  •  '
                  'Entry: ${DateFormat('dd MMM yy').format(flock.entryDate)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert,
                size: 20, color: AppTheme.textSecondary),
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'sell') onMarkSold?.call();
              if (v == 'history') onHistory();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (!isSold)
                const PopupMenuItem(
                    value: 'sell', child: Text('Mark as Sold')),
              const PopupMenuItem(
                  value: 'history', child: Text('View History')),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Flock history bottom sheet ────────────────────────────────────────────

class _FlockHistorySheet extends StatelessWidget {
  final Flock flock;
  final List<AuditSession> sessions;

  const _FlockHistorySheet({required this.flock, required this.sessions});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Audit History — ${flock.flockCode}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(),
          if (sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('No audits recorded for this flock.',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: sessions.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final s = sessions[i];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor:
                          AppTheme.primary.withValues(alpha: 0.1),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ),
                    title: Text(
                      DateFormat('dd MMM yyyy').format(s.auditDate),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    subtitle: Text(
                      '${s.flockAgeWeeks.toStringAsFixed(1)} wks  •  '
                      '${s.completedSections.length} section(s) completed',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: s.isCompleted
                        ? const Icon(Icons.check_circle,
                            color: AppTheme.green, size: 18)
                        : const Icon(Icons.pending_outlined,
                            color: AppTheme.amber, size: 18),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
