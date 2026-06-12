import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/repositories/admin_repository.dart';
import '../../../data/repositories/customer_repository.dart';

/// Admin-only screen to manage who can sign in and what they can see.
/// Set a user's role (admin / auditor / customer), approve or disable them,
/// and — for auditors — pick which customers they may audit. All writes are
/// enforced server-side by RLS; this screen only works for an admin account
/// while online.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final AdminRepository _adminRepo = AdminRepository();
  final CustomerRepository _customerRepo = CustomerRepository();

  bool _loading = true;
  String? _error;
  List<AdminProfile> _profiles = const [];
  List<CustomerModel> _customers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _adminRepo.listProfiles(),
        _customerRepo.getAllCustomers(),
      ]);
      if (!mounted) return;
      setState(() {
        _profiles = results[0] as List<AdminProfile>;
        _customers = results[1] as List<CustomerModel>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Could not load users. This screen needs an internet connection '
            'and an admin account.\n\n$e';
        _loading = false;
      });
    }
  }

  String _customerName(String? id) {
    if (id == null) return '—';
    for (final c in _customers) {
      if (c.id == id) return c.name;
    }
    return id;
  }

  Future<void> _openEditor(AdminProfile profile) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _UserEditorSheet(
        profile: profile,
        customers: _customers,
        adminRepo: _adminRepo,
      ),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Access')),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSizes.spaceXl),
            child: Column(
              children: [
                const Icon(
                  Icons.cloud_off,
                  size: AppSizes.iconLg,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(height: AppSizes.spaceMd),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body,
                ),
                const SizedBox(height: AppSizes.spaceLg),
                FilledButton(
                  onPressed: _load,
                  child: const Text(AppStrings.retry),
                ),
              ],
            ),
          ),
        ],
      );
    }
    if (_profiles.isEmpty) {
      return const Center(child: Text('No users found.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceSm),
      itemCount: _profiles.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final p = _profiles[index];
        return ListTile(
          leading: CircleAvatar(child: Text(_initials(p))),
          title: Text(p.displayName),
          subtitle: Text(
            p.role == 'customer'
                ? '${p.email ?? ''}\nCustomer: ${_customerName(p.customerId)}'
                : (p.email ?? ''),
          ),
          isThreeLine: p.role == 'customer',
          trailing: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _RoleChip(role: p.role),
              _StatusChip(status: p.status),
            ],
          ),
          onTap: () => _openEditor(p),
        );
      },
    );
  }

  String _initials(AdminProfile p) {
    final name = p.displayName.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    return parts.take(2).map((e) => e[0].toUpperCase()).join();
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      'admin' => Colors.purple,
      'customer' => Colors.teal,
      _ => Colors.blue,
    };
    return Chip(
      label: Text(role, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: TextStyle(color: color),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => AppColors.statusGood,
      'disabled' => AppColors.statusError,
      _ => AppColors.statusWarning,
    };
    return Chip(
      label: Text(status, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      labelStyle: TextStyle(color: color),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _UserEditorSheet extends StatefulWidget {
  final AdminProfile profile;
  final List<CustomerModel> customers;
  final AdminRepository adminRepo;

  const _UserEditorSheet({
    required this.profile,
    required this.customers,
    required this.adminRepo,
  });

  @override
  State<_UserEditorSheet> createState() => _UserEditorSheetState();
}

class _UserEditorSheetState extends State<_UserEditorSheet> {
  late String _role = widget.profile.role;
  late String _status = widget.profile.status;
  late String? _customerId = widget.profile.customerId;

  Set<String> _assigned = {};
  bool _loadingAssignments = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (_role == 'auditor') _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    setState(() => _loadingAssignments = true);
    try {
      final ids = await widget.adminRepo.auditorCustomerIds(widget.profile.id);
      if (!mounted) return;
      setState(() {
        _assigned = ids;
        _loadingAssignments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAssignments = false);
    }
  }

  Future<void> _save() async {
    if (_role == 'customer' && (_customerId == null || _customerId!.isEmpty)) {
      _toast('Pick which customer this account belongs to.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.adminRepo.updateProfile(
        id: widget.profile.id,
        role: _role,
        status: _status,
        customerId: _customerId,
      );
      // Keep the auditor scope in sync; clear it for non-auditors.
      await widget.adminRepo.setAuditorCustomers(
        widget.profile.id,
        _role == 'auditor' ? _assigned : <String>{},
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Save failed: $e');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.profile.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (widget.profile.email != null)
              Text(
                widget.profile.email!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: AppSizes.spaceLg),
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: const [
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'auditor', child: Text('Auditor')),
                DropdownMenuItem(value: 'customer', child: Text('Customer')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _role = v);
                if (v == 'auditor') _loadAssignments();
              },
            ),
            const SizedBox(height: AppSizes.spaceMd),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Status'),
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Pending')),
                DropdownMenuItem(value: 'approved', child: Text('Approved')),
                DropdownMenuItem(value: 'disabled', child: Text('Disabled')),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: AppSizes.spaceLg),
            if (_role == 'customer') _buildCustomerPicker(),
            if (_role == 'auditor') _buildAuditorAssignments(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(AppStrings.save),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerPicker() {
    return DropdownButtonFormField<String>(
      initialValue: _customerId,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Belongs to customer'),
      items: widget.customers
          .map(
            (c) => DropdownMenuItem(
              value: c.id,
              child: Text(c.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _customerId = v),
    );
  }

  Widget _buildAuditorAssignments() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Customers this auditor can access',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSizes.spaceXs),
        if (_loadingAssignments)
          const Padding(
            padding: EdgeInsets.all(AppSizes.spaceMd),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.customers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSizes.spaceSm),
            child: Text('No customers exist yet.'),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView(
              shrinkWrap: true,
              children: widget.customers.map((c) {
                final checked = _assigned.contains(c.id);
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: checked,
                  title: Text(c.name),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _assigned.add(c.id);
                      } else {
                        _assigned.remove(c.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
