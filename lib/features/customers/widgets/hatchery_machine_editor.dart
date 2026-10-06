import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/hatchery_machine_model.dart';
import '../../../data/repositories/hatchery_machine_repository.dart';
import '../../../l10n/app_localizations.dart' show AppLocalizationsX;

/// Registration form shared by hatchery management and sampling dialogs.
/// Physical machine codes are fixed after creation; capacity edits keep the
/// immutable catalog row id and its physical code.
class HatcheryMachineEditorDialog extends StatefulWidget {
  const HatcheryMachineEditorDialog({
    super.key,
    required this.hatcheryId,
    required this.kind,
    required this.repository,
    this.machine,
  });

  final String hatcheryId;
  final String kind;
  final HatcheryMachineRepository repository;
  final HatcheryMachineModel? machine;

  @override
  State<HatcheryMachineEditorDialog> createState() =>
      _HatcheryMachineEditorDialogState();
}

class _HatcheryMachineEditorDialogState
    extends State<HatcheryMachineEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _code = TextEditingController(text: widget.machine?.code ?? '');
  late final _batch = TextEditingController(
    text: widget.machine?.batchSize.toString() ?? '',
  );
  late final _trolley = TextEditingController(
    text: widget.machine?.trolleyCapacity.toString() ?? '',
  );
  late final _tray = TextEditingController(
    text: widget.machine?.traySize.toString() ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _batch.dispose();
    _trolley.dispose();
    _tray.dispose();
    super.dispose();
  }

  int? get _batchValue => int.tryParse(_batch.text.trim());
  int? get _trolleyValue => int.tryParse(_trolley.text.trim());
  int? get _trayValue => int.tryParse(_tray.text.trim());

  @override
  Widget build(BuildContext context) {
    final batch = _batchValue;
    final trolley = _trolleyValue;
    final tray = _trayValue;
    final counts =
        batch != null &&
            trolley != null &&
            tray != null &&
            batch > 0 &&
            trolley > 0 &&
            tray > 0
        ? HatcheryMachineModel.calculateCounts(
            batchSize: batch,
            trolleyCapacity: trolley,
            traySize: tray,
          )
        : null;
    final machineLabel = widget.kind == 'setter'
        ? context.tr('Setter')
        : context.tr('Hatcher');
    return AlertDialog(
      title: Text(
        widget.machine == null
            ? context
                  .tr('Register {machine}')
                  .replaceFirst('{machine}', machineLabel)
            : context
                  .tr('Edit {machine} capacities')
                  .replaceFirst('{machine}', machineLabel),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _code,
                  enabled: widget.machine == null,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: context.tr('Machine ID / number'),
                  ),
                  validator: (value) => value?.trim().isNotEmpty == true
                      ? null
                      : context.tr('Enter a machine ID.'),
                ),
                _positiveIntegerField(
                  controller: _batch,
                  label: context.tr(
                    widget.kind == 'setter'
                        ? 'Setter capacity'
                        : 'Hatcher capacity',
                  ),
                ),
                _positiveIntegerField(
                  controller: _trolley,
                  label: context.tr('Trolley capacity'),
                ),
                _positiveIntegerField(
                  controller: _tray,
                  label: context.tr('Tray size'),
                ),
                if (counts != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${context.tr('Trolleys:')} ${counts.trolleyCount}',
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${context.tr('Trays per trolley:')} ${counts.traysPerTrolley}',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: _saving || counts == null ? null : _save,
          child: Text(context.tr('Save')),
        ),
      ],
    );
  }

  Widget _positiveIntegerField({
    required TextEditingController controller,
    required String label,
  }) => TextFormField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    onChanged: (_) => setState(() {}),
    validator: (value) {
      final parsed = int.tryParse(value?.trim() ?? '');
      return parsed != null && parsed > 0
          ? null
          : context.tr('Enter a positive whole number.');
    },
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final batch = _batchValue!;
    final trolley = _trolleyValue!;
    final tray = _trayValue!;
    final counts = HatcheryMachineModel.calculateCounts(
      batchSize: batch,
      trolleyCapacity: trolley,
      traySize: tray,
    );
    setState(() => _saving = true);
    try {
      final previous = widget.machine;
      final machine = HatcheryMachineModel(
        id: previous?.id ?? const Uuid().v4(),
        hatcheryId: widget.hatcheryId,
        kind: widget.kind,
        code: previous?.code ?? _code.text,
        // `name` remains a required legacy storage column. New registrations
        // use their normalized physical ID; existing rows keep their old name.
        name: previous?.name ?? HatcheryMachineModel.normalizeCode(_code.text),
        batchSize: batch,
        trolleyCapacity: trolley,
        traySize: tray,
        trolleyCount: counts.trolleyCount,
        traysPerTrolley: counts.traysPerTrolley,
        createdAt: previous?.createdAt,
        updatedAt: DateTime.now().toUtc(),
        createdBy: previous?.createdBy,
      );
      await widget.repository.saveMachine(machine);
      if (mounted) Navigator.pop(context, machine);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Machine could not be saved.'))),
      );
    }
  }
}

/// Catalog manager opened from hatchery management or an audit sampling form.
class HatcheryMachineManagementSheet extends StatefulWidget {
  const HatcheryMachineManagementSheet({
    super.key,
    required this.hatcheryId,
    required this.repository,
    this.readOnly = false,
  });

  final String hatcheryId;
  final HatcheryMachineRepository repository;
  final bool readOnly;

  @override
  State<HatcheryMachineManagementSheet> createState() =>
      _HatcheryMachineManagementSheetState();
}

class _HatcheryMachineManagementSheetState
    extends State<HatcheryMachineManagementSheet> {
  late Future<List<HatcheryMachineModel>> _machines = widget.repository
      .getByHatchery(widget.hatcheryId);

  Future<void> _refresh() async {
    setState(
      () => _machines = widget.repository.getByHatchery(widget.hatcheryId),
    );
    await _machines;
  }

  Future<void> _edit(String kind, [HatcheryMachineModel? machine]) async {
    final saved = await showDialog<HatcheryMachineModel>(
      context: context,
      builder: (_) => HatcheryMachineEditorDialog(
        hatcheryId: widget.hatcheryId,
        kind: kind,
        repository: widget.repository,
        machine: machine,
      ),
    );
    if (saved != null && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: FutureBuilder<List<HatcheryMachineModel>>(
        future: _machines,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(context.tr('Registered machines could not be loaded.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final machines = snapshot.data!;
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr('Registered machines'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final kind in const ['setter', 'hatcher']) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          kind == 'setter'
                              ? context.tr('Setters')
                              : context.tr('Hatchers'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: widget.readOnly ? null : () => _edit(kind),
                        icon: const Icon(Icons.add),
                        label: Text(context.tr('Register')),
                      ),
                    ],
                  ),
                  for (final machine in machines.where(
                    (item) => item.kind == kind,
                  ))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(machine.code),
                      subtitle: Text(
                        '${machine.trolleyCount} ${context.tr('trolleys')} · '
                        '${machine.traysPerTrolley} ${context.tr('trays per trolley')}',
                      ),
                      trailing: IconButton(
                        tooltip: context.tr('Edit capacities'),
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: widget.readOnly
                            ? null
                            : () => _edit(kind, machine),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    ),
  );
}
