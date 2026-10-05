import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/panel_sample_schema.dart';
import '../../../data/models/panel_sampling_state.dart';
import '../../../data/models/hatchery_machine_model.dart';
import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../data/models/sampling_code.dart';
import '../../../data/models/sampling_scope.dart';
import '../../../data/repositories/poultry_hierarchy_repository.dart';
import '../../../data/repositories/hatchery_machine_repository.dart';
import '../../../l10n/app_localizations.dart' show AppLocalizationsX;
import '../../../providers/customers_provider.dart';
import '../providers/audit_provider.dart';
import '../../customers/widgets/hatchery_machine_editor.dart';

/// Shared scope tabs for a single panel. State is loaded lazily so screens
/// which do not render sampling controls never open the sampling database.
class SamplingScopeControls extends StatefulWidget {
  const SamplingScopeControls({
    super.key,
    required this.panelKey,
    this.houseRepository,
    this.machineRepository,
  });

  final String panelKey;
  final PoultryHierarchyRepository? houseRepository;
  final HatcheryMachineRepository? machineRepository;

  @override
  State<SamplingScopeControls> createState() => _SamplingScopeControlsState();
}

class _SamplingScopeControlsState extends State<SamplingScopeControls> {
  late Future<PanelSamplingState> _load;

  PoultryHierarchyRepository get _houseRepository =>
      widget.houseRepository ?? PoultryHierarchyRepository();
  HatcheryMachineRepository get _machineRepository =>
      widget.machineRepository ?? HatcheryMachineRepository();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load = context.read<AuditProvider>().loadPanelSamplingState(
      widget.panelKey,
    );
  }

  @override
  void didUpdateWidget(covariant SamplingScopeControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panelKey != widget.panelKey) {
      _load = context.read<AuditProvider>().loadPanelSamplingState(
        widget.panelKey,
      );
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PanelSamplingState>(
    future: _load,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context
                  .tr('Sampling could not be loaded: {error}')
                  .replaceFirst('{error}', '${snapshot.error}'),
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        );
      }
      final latest = context.watch<AuditProvider>().samplingStateFor(
        widget.panelKey,
      );
      return _buildControls(context, latest ?? snapshot.data!);
    },
  );

  Widget _buildControls(BuildContext context, PanelSamplingState state) {
    final provider = context.watch<AuditProvider>();
    final config = PanelSampleSchema.samplingConfigFor(widget.panelKey);
    final activeId =
        provider.activeSampleIdFor(widget.panelKey) ??
        state.resolvedActiveSampleId;
    final activeSample = state.samples
        .where((sample) => sample.sampleId == activeId)
        .firstOrNull;
    final chain = activeSample == null
        ? const <SamplingNode>[]
        : _chain(state, activeSample);
    final selectedByLevel = <SamplingScopeLevel, SamplingNode>{
      for (final node in chain) node.level: node,
    };
    final childrenByLevel = <SamplingScopeLevel, List<SamplingNode>>{};
    String? parentId;
    for (final level in config.levels) {
      childrenByLevel[level] = state.childrenOf(parentId, level);
      // Pooled levels have no node. Keep the closest selected ancestor so a
      // later comparison attaches to that branch rather than the root.
      parentId = selectedByLevel[level]?.id ?? parentId;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Sampling'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final level in config.levels)
              if (!(config.pairedLevels?.last == level))
                _levelControls(
                  context,
                  provider,
                  state,
                  config,
                  level,
                  childrenByLevel[level] ?? const [],
                  selectedByLevel[level],
                  selectedByLevel,
                  activeId,
                ),
            if (config.terminalLevel == SamplingScopeLevel.sample)
              _terminalSamples(
                context,
                provider,
                state,
                config,
                selectedByLevel,
                activeId,
              ),
            if (activeSample != null)
              _activeSampleCode(context, provider, state, activeSample),
          ],
        ),
      ),
    );
  }

  Widget _levelControls(
    BuildContext context,
    AuditProvider provider,
    PanelSamplingState state,
    PanelSamplingConfig config,
    SamplingScopeLevel level,
    List<SamplingNode> nodes,
    SamplingNode? selected,
    Map<SamplingScopeLevel, SamplingNode> selectedByLevel,
    String? activeId,
  ) {
    final readOnly = provider.isReadOnly || provider.isLoading;
    final paired = config.pairedLevels?.contains(level) ?? false;
    final label = _levelLabel(context, level, paired: paired);
    final parentId = _nearestSelectedParentId(config, level, selectedByLevel);
    final isPaired = config.pairedLevels?.contains(level) ?? false;
    final displayNodes = isPaired
        ? nodes
              .where((node) => node.level == config.pairedLevels!.first)
              .toList()
        : nodes;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 2,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Tooltip(
                message: context
                    .tr('Add {scope}')
                    .replaceFirst('{scope}', label),
                child: TextButton.icon(
                  onPressed: readOnly
                      ? null
                      : () => _add(
                          context,
                          provider,
                          state,
                          level,
                          parentId,
                          config,
                        ),
                  icon: const Icon(Icons.add_circle_outline),
                  label: Text(
                    context.tr('Add {scope}').replaceFirst('{scope}', label),
                  ),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (level != SamplingScopeLevel.tray)
                ChoiceChip(
                  label: Text(
                    context.tr('Pooled'),
                    style: TextStyle(
                      color: displayNodes.isEmpty
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  selected: displayNodes.isEmpty,
                  // Pooled is the default while no identity exists. Once a
                  // comparison identity has been added, it is intentionally
                  // unavailable: changing modes would orphan or reinterpret
                  // measurements already attached to that branch.
                  onSelected: null,
                ),
              for (final node in displayNodes)
                InputChip(
                  label: Text(
                    _identityLabel(node, isPaired),
                    style: TextStyle(
                      color: node.id == selected?.id
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  selected: node.id == selected?.id,
                  deleteIconColor: node.id == selected?.id
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  onPressed: readOnly
                      ? null
                      : () => _selectBranch(context, provider, state, node),
                  onDeleted: readOnly
                      ? null
                      : () => _delete(context, provider, node),
                  deleteButtonTooltipMessage: context
                      .tr('Remove {scope}')
                      .replaceFirst('{scope}', _identityLabel(node, isPaired)),
                  avatar: readOnly
                      ? null
                      : IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 16,
                          tooltip: context.tr('Edit identity'),
                          icon: Icon(
                            Icons.edit_outlined,
                            color: node.id == selected?.id
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                          onPressed: () =>
                              _edit(context, provider, node, config),
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _terminalSamples(
    BuildContext context,
    AuditProvider provider,
    PanelSamplingState state,
    PanelSamplingConfig config,
    Map<SamplingScopeLevel, SamplingNode> selectedByLevel,
    String? activeId,
  ) {
    final parentId = config.levels.isEmpty
        ? null
        : _nearestSelectedParentId(
            config,
            config.levels.last,
            selectedByLevel,
            includeLevel: true,
          );
    final samples = state.childrenOf(parentId, SamplingScopeLevel.sample);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Sample'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final sample in samples)
                ChoiceChip(
                  label: Text(
                    'SA${sample.sampleNumber ?? ''}',
                    style: TextStyle(
                      color: sample.sampleId == activeId
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  selected: sample.sampleId == activeId,
                  onSelected:
                      provider.isReadOnly ||
                          provider.isLoading ||
                          sample.sampleId == null
                      ? null
                      : (_) => provider.selectPanelSample(
                          widget.panelKey,
                          sample.sampleId!,
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    AuditProvider provider,
    PanelSamplingState state,
    SamplingScopeLevel level,
    String? parentId,
    PanelSamplingConfig config,
  ) async {
    final identity = await _identityDialog(
      context,
      level,
      config,
      state: state,
      parentId: parentId,
    );
    if (identity == null || !context.mounted) return;
    try {
      final created = await provider.addPanelScopeIdentity(
        widget.panelKey,
        level: level,
        parentId: parentId,
        identity: identity,
      );
      if (!context.mounted) return;
      await _finishAddingScope(context, provider, config, created);
    } on StateError catch (error) {
      if (!error.message.contains('measured Pooled')) {
        if (context.mounted) _showSamplingError(context, error.message);
        return;
      }
      if (!context.mounted) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(context.tr('Reset Pooled sample?')),
          content: Text(
            context.tr(
              'Adding this comparison will delete measurements in the current Pooled sample under this parent.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr('Delete and continue')),
            ),
          ],
        ),
      );
      if (discard == true && context.mounted) {
        final created = await provider.addPanelScopeIdentity(
          widget.panelKey,
          level: level,
          parentId: parentId,
          identity: identity,
          discardPooledData: true,
        );
        if (!context.mounted) return;
        await _finishAddingScope(context, provider, config, created);
      }
    } on ArgumentError catch (error) {
      if (context.mounted) {
        _showSamplingError(context, error.message?.toString() ?? '');
      }
    } catch (error) {
      if (context.mounted) _showSamplingError(context, '');
    }
  }

  void _showSamplingError(BuildContext context, String diagnostic) {
    if (!context.mounted) return;
    final message = diagnostic.toLowerCase().contains('already exists')
        ? context.tr('That identity already exists under this parent.')
        : context.tr('Sampling identity could not be saved. Try again.');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finishAddingScope(
    BuildContext context,
    AuditProvider provider,
    PanelSamplingConfig config,
    SamplingNode created,
  ) async {
    if (created.sampleId != null) {
      await provider.selectPanelSample(widget.panelKey, created.sampleId!);
      return;
    }
    final sample = await provider.addPanelTerminalSample(
      widget.panelKey,
      parentId: created.id,
      identity: _defaultTerminalIdentity(config),
    );
    if (sample.sampleId != null && context.mounted) {
      await provider.selectPanelSample(widget.panelKey, sample.sampleId!);
    }
  }

  Future<Map<String, String>?> _identityDialog(
    BuildContext context,
    SamplingScopeLevel level,
    PanelSamplingConfig config, {
    Map<String, String>? initial,
    PanelSamplingState? state,
    String? parentId,
  }) async {
    if (level == SamplingScopeLevel.house) {
      return _houseIdentityDialog(context, initial: initial);
    }
    final pair = config.pairedLevels?.contains(level) ?? false;
    final levels = pair ? config.pairedLevels! : [level];
    if (levels.any(_isMachineLevel)) {
      return _machineIdentityDialog(context, levels, initial: initial);
    }
    if (level == SamplingScopeLevel.trolley ||
        level == SamplingScopeLevel.tray) {
      return _numberIdentityDialog(
        context,
        level,
        state: state,
        parentId: parentId,
        initial: initial,
      );
    }
    final values = <SamplingScopeLevel, String>{
      for (final item in levels)
        item:
            initial?[item.name] ??
            (levels.length == 1 && initial != null
                ? initial['code'] ?? ''
                : ''),
    };
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            context
                .tr('Add {scope}')
                .replaceFirst(
                  '{scope}',
                  _levelLabel(context, level, paired: pair),
                ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in levels)
                TextFormField(
                  initialValue: values[item],
                  onChanged: (value) =>
                      setDialogState(() => values[item] = value),
                  decoration: InputDecoration(
                    labelText: _levelLabel(context, item),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: () {
                final identity = <String, String>{};
                for (final item in levels) {
                  final value = values[item]?.trim() ?? '';
                  if (value.isNotEmpty) identity[item.name] = value;
                }
                if (identity.length == levels.length) {
                  Navigator.pop(
                    dialogContext,
                    pair ? identity : {'code': identity.values.single},
                  );
                }
              },
              child: Text(context.tr('Save')),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  bool _isMachineLevel(SamplingScopeLevel level) =>
      level == SamplingScopeLevel.setter || level == SamplingScopeLevel.hatcher;

  Future<Map<String, String>?> _machineIdentityDialog(
    BuildContext context,
    List<SamplingScopeLevel> levels, {
    Map<String, String>? initial,
  }) async {
    final hatcheryId = context.read<AuditProvider>().context?.hatcheryId;
    List<HatcheryMachineModel> loaded = [];
    if (hatcheryId != null && hatcheryId.isNotEmpty) {
      try {
        loaded = await _machineRepository.getByHatchery(hatcheryId);
      } catch (_) {
        if (context.mounted) {
          _showSamplingError(
            context,
            context.tr('Registered machines could not be loaded.'),
          );
        }
        return null;
      }
    }
    if (!context.mounted) return null;
    final machines = [...loaded];
    final selected = <SamplingScopeLevel, String?>{};
    final legacyCodes = <SamplingScopeLevel, String?>{};
    for (final level in levels) {
      final kind = level.name;
      final id = initial?['${kind}MachineId'];
      final code =
          initial?[kind] ??
          (levels.length == 1 ? (initial?['code'] ?? initial?['name']) : null);
      final match = machines
          .where(
            (machine) =>
                machine.kind == kind &&
                ((id != null && machine.id == id) ||
                    (id == null &&
                        code != null &&
                        machine.code == code.toUpperCase())),
          )
          .firstOrNull;
      if (match != null) {
        selected[level] = match.id;
      } else if (code != null && code.isNotEmpty) {
        final legacy = _legacyMachineValue(code);
        selected[level] = legacy;
        legacyCodes[level] = code;
      }
    }

    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final ready = levels.every((level) => selected[level] != null);
          return AlertDialog(
            title: Text(
              context
                  .tr('Add {scope}')
                  .replaceFirst(
                    '{scope}',
                    levels.length == 1
                        ? _levelLabel(context, levels.single)
                        : context.tr('Setter / Hatcher'),
                  ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final level in levels) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('machine-${level.name}'),
                    initialValue: selected[level],
                    decoration: InputDecoration(
                      labelText: _levelLabel(context, level),
                    ),
                    items: [
                      for (final machine in machines.where(
                        (machine) => machine.kind == level.name,
                      ))
                        DropdownMenuItem(
                          value: machine.id,
                          child: Text('${machine.code} · ${machine.name}'),
                        ),
                      if (legacyCodes[level] != null)
                        DropdownMenuItem(
                          value: _legacyMachineValue(legacyCodes[level]!),
                          child: Text(
                            '${context.tr('Legacy')} · ${legacyCodes[level]}',
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selected[level] = value),
                  ),
                  Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: hatcheryId == null || hatcheryId.isEmpty
                            ? null
                            : () async {
                                final machine =
                                    await showDialog<HatcheryMachineModel>(
                                      context: dialogContext,
                                      builder: (_) =>
                                          HatcheryMachineEditorDialog(
                                            hatcheryId: hatcheryId,
                                            kind: level.name,
                                            repository: _machineRepository,
                                          ),
                                    );
                                if (machine != null) {
                                  machines.removeWhere(
                                    (item) => item.id == machine.id,
                                  );
                                  machines.add(machine);
                                  setDialogState(
                                    () => selected[level] = machine.id,
                                  );
                                }
                              },
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.tr('Register machine')),
                      ),
                      if (machines.any(
                        (machine) =>
                            machine.kind == level.name &&
                            machine.id == selected[level],
                      ))
                        TextButton.icon(
                          onPressed: () async {
                            final existing = machines.firstWhere(
                              (machine) =>
                                  machine.kind == level.name &&
                                  machine.id == selected[level],
                            );
                            final machine =
                                await showDialog<HatcheryMachineModel>(
                                  context: dialogContext,
                                  builder: (_) => HatcheryMachineEditorDialog(
                                    hatcheryId: hatcheryId!,
                                    kind: level.name,
                                    repository: _machineRepository,
                                    machine: existing,
                                  ),
                                );
                            if (machine != null) {
                              machines.removeWhere(
                                (item) => item.id == machine.id,
                              );
                              machines.add(machine);
                              setDialogState(() {});
                            }
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(context.tr('Edit capacities')),
                        ),
                    ],
                  ),
                ],
                if (levels.any(
                  (level) =>
                      !machines.any((machine) => machine.kind == level.name),
                ))
                  Text(
                    context.tr(
                      'Register or select a machine for this hatchery before adding numbered trolley and tray options.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(context.tr('Cancel')),
              ),
              FilledButton(
                onPressed: ready
                    ? () {
                        final result = <String, String>{};
                        for (final level in levels) {
                          final value = selected[level]!;
                          if (value.startsWith('legacy:')) {
                            final raw = value.substring('legacy:'.length);
                            result[level.name] = raw;
                          } else {
                            final machine = machines.firstWhere(
                              (item) => item.id == value,
                            );
                            result[level.name] = machine.code;
                            result['${level.name}MachineId'] = machine.id;
                          }
                        }
                        if (levels.length == 1) {
                          result['code'] = result[levels.single.name]!;
                        }
                        Navigator.pop(dialogContext, result);
                      }
                    : null,
                child: Text(context.tr('Save')),
              ),
            ],
          );
        },
      ),
    );
  }

  String _legacyMachineValue(String code) => 'legacy:$code';

  Future<Map<String, String>?> _numberIdentityDialog(
    BuildContext context,
    SamplingScopeLevel level, {
    PanelSamplingState? state,
    String? parentId,
    Map<String, String>? initial,
  }) async {
    final machineId = _machineIdForNumberedScope(state, parentId);
    HatcheryMachineModel? machine;
    if (machineId != null) {
      try {
        machine = await _machineRepository.getById(machineId);
      } catch (_) {
        machine = null;
      }
    }
    if (!context.mounted) return null;
    final label = _levelLabel(context, level);
    final maximum = machine == null
        ? 0
        : level == SamplingScopeLevel.trolley
        ? machine.trolleyCount
        : machine.traysPerTrolley;
    final original = initial?['code'] ?? initial?['name'];
    final originalNumber = _numberFromIdentity(original, level);
    final isInRange =
        originalNumber != null &&
        originalNumber > 0 &&
        originalNumber <= maximum;
    var selected = isInRange
        ? originalNumber.toString()
        : original == null
        ? null
        : 'legacy:$original';
    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(context.tr('Add {scope}').replaceFirst('{scope}', label)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (machine == null)
                Text(
                  context.tr(
                    'Select or register a setter or hatcher before adding numbered trolley and tray options.',
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: label),
                items: [
                  for (var number = 1; number <= maximum; number++)
                    DropdownMenuItem(
                      value: '$number',
                      child: Text('$label $number'),
                    ),
                  if (selected?.startsWith('legacy:') == true)
                    DropdownMenuItem(
                      value: selected,
                      child: Text(
                        '${context.tr('Legacy')} · ${selected!.substring(7)}',
                      ),
                    ),
                ],
                onChanged: maximum == 0 && selected == null
                    ? null
                    : (value) => setDialogState(() => selected = value),
              ),
              if (originalNumber != null &&
                  maximum > 0 &&
                  originalNumber > maximum)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    context.tr(
                      'This saved value is above the registered capacity. It remains available for this existing sampling branch.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () {
                      final value = selected!;
                      if (value.startsWith('legacy:')) {
                        Navigator.pop(dialogContext, {
                          'code': value.substring(7),
                        });
                        return;
                      }
                      final number = int.parse(value);
                      final prefix = level == SamplingScopeLevel.trolley
                          ? 'TR'
                          : 'T';
                      Navigator.pop(dialogContext, {
                        'code': '$prefix$number',
                        'name': '$label $number',
                      });
                    },
              child: Text(context.tr('Save')),
            ),
          ],
        ),
      ),
    );
  }

  int? _numberFromIdentity(String? raw, SamplingScopeLevel level) {
    if (raw == null) return null;
    final prefix = level == SamplingScopeLevel.tray
        ? r'(?:T|Tray\s+)'
        : r'(?:TR|Trolley\s+)';
    final match = RegExp(
      '^(?:$prefix)?([0-9]+)\$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    final number = match == null ? null : int.tryParse(match.group(1)!);
    return number != null && number > 0 ? number : null;
  }

  String? _machineIdForNumberedScope(
    PanelSamplingState? state,
    String? parentId,
  ) {
    if (state == null) return null;
    var current = parentId;
    while (current != null) {
      final node = state.nodes.where((item) => item.id == current).firstOrNull;
      if (node == null) return null;
      final hatcherId = node.identity['hatcherMachineId'];
      final setterId = node.identity['setterMachineId'];
      if (hatcherId != null && hatcherId.isNotEmpty) return hatcherId;
      if (setterId != null && setterId.isNotEmpty) return setterId;
      current = node.parentId;
    }
    return null;
  }

  Future<Map<String, String>?> _houseIdentityDialog(
    BuildContext context, {
    Map<String, String>? initial,
  }) async {
    final provider = context.read<AuditProvider>();
    final flockId = provider.context?.flockId;
    if (flockId == null || flockId.isEmpty) return null;
    final List<HouseModel> houses;
    try {
      houses = await _houseRepository.listHouses(flockId);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('Registered houses could not be loaded.')),
          ),
        );
      }
      return null;
    }
    if (!context.mounted) return null;
    final existingId = initial?['house'] ?? initial?['id'];
    final existingCode = initial?['code'] ?? initial?['name'];
    final selectedHouse = houses
        .where(
          (house) =>
              (existingId != null && house.id == existingId) ||
              (existingCode != null &&
                  (house.code == existingCode || house.name == existingCode)),
        )
        .firstOrNull;
    final choices = <String, Map<String, String>>{
      for (final house in houses)
        house.id: {
          'id': house.id,
          'code': house.code?.trim().isNotEmpty == true
              ? house.code!.trim()
              : house.name,
          'name': house.name,
        },
      if (selectedHouse == null && existingCode != null)
        existingId ?? existingCode: {
          'id': ?existingId,
          'code': existingCode,
          'name': ?initial?['name'],
        },
    };
    var selected =
        selectedHouse?.id ??
        (existingId != null && choices.containsKey(existingId)
            ? existingId
            : existingCode != null && choices.containsKey(existingCode)
            ? existingCode
            : null);
    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            context
                .tr('Add {scope}')
                .replaceFirst('{scope}', context.tr('House')),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (houses.isEmpty && selected == null)
                Text(
                  context.tr(
                    'No houses are registered for this flock. Add houses in Flock Management, then return here.',
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  decoration: InputDecoration(labelText: context.tr('House')),
                  items: [
                    for (final entry in choices.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          entry.value['name'] ?? entry.value['code']!,
                        ),
                      ),
                  ],
                  onChanged: choices.isEmpty
                      ? null
                      : (value) => setDialogState(() => selected = value),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('Cancel')),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(dialogContext, choices[selected]),
              child: Text(context.tr('Save')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeSampleCode(
    BuildContext context,
    AuditProvider provider,
    PanelSamplingState state,
    SamplingNode activeSample,
  ) {
    final path = state.pathFor(activeSample.sampleId!);
    CustomersProvider? reference;
    try {
      reference = context.read<CustomersProvider>();
    } catch (_) {
      reference = null;
    }
    final auditContext = provider.context;
    final fullCode = SamplingCode.build(
      customerCode: reference
          ?.customerById(auditContext?.customerId ?? '')
          ?.samplingCode,
      hatcheryCode: reference
          ?.hatcheryById(auditContext?.hatcheryId)
          ?.samplingCode,
      flockCode: reference?.flockById(auditContext?.flockId)?.samplingCode,
      breedAbbreviation: samplingBreedAbbreviations[auditContext?.breed],
      path: path,
    );
    final fallback = <String>[
      if (path.house != null) 'H${path.house}',
      if (path.setter != null) 'S${path.setter}',
      if (path.hatcher != null) 'HT${path.hatcher}',
      if (path.trolley != null) 'TR${path.trolley}',
      if (path.tray != null) 'T${path.tray}',
      'SA${path.sampleNumber}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${context.tr('Active sample:')} ${fullCode ?? fallback}'),
          if (fullCode == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.tr(
                  'Complete customer, hatchery, and flock sampling codes to show the full sample code.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    AuditProvider provider,
    SamplingNode node,
    PanelSamplingConfig config,
  ) async {
    final state = provider.samplingStateFor(widget.panelKey);
    final activeSampleId =
        provider.activeSampleIdFor(widget.panelKey) ??
        state?.resolvedActiveSampleId;
    final identity = await _identityDialog(
      context,
      node.level,
      config,
      initial: node.identity,
      state: state,
      parentId: node.parentId,
    );
    if (identity != null && context.mounted) {
      try {
        await provider.editPanelScopeIdentity(
          widget.panelKey,
          node.id,
          identity,
        );
        final refreshed = provider.samplingStateFor(widget.panelKey);
        if (activeSampleId != null &&
            refreshed?.samples.any(
                  (sample) => sample.sampleId == activeSampleId,
                ) ==
                true) {
          await provider.selectPanelSample(widget.panelKey, activeSampleId);
        }
      } on ArgumentError catch (error) {
        if (context.mounted) {
          _showSamplingError(context, error.message?.toString() ?? '');
        }
      } catch (error) {
        if (context.mounted) _showSamplingError(context, '$error');
      }
    }
  }

  Future<void> _delete(
    BuildContext context,
    AuditProvider provider,
    SamplingNode node,
  ) async {
    late final SamplingDeletePreview preview;
    try {
      preview = await provider.previewPanelScopeDeletion(
        widget.panelKey,
        node.id,
      );
    } catch (_) {
      if (context.mounted) _showSamplingError(context, '');
      return;
    }
    if (!context.mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context
              .tr('Delete {scope}?')
              .replaceFirst('{scope}', preview.scopeLabel),
        ),
        content: Text(
          context
              .tr(
                'This removes {branches} branches, {measurements} measurements, {photos} photos, and {notes} notes.',
              )
              .replaceFirst('{branches}', '${preview.descendantCount}')
              .replaceFirst('{measurements}', '${preview.measurementCount}')
              .replaceFirst('{photos}', '${preview.photoCount}')
              .replaceFirst('{notes}', '${preview.noteCount}'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      try {
        await provider.deletePanelScopeNode(widget.panelKey, node.id);
      } catch (error) {
        if (context.mounted) _showSamplingError(context, '$error');
      }
    }
  }

  Future<void> _selectBranch(
    BuildContext context,
    AuditProvider provider,
    PanelSamplingState state,
    SamplingNode node,
  ) async {
    final config = PanelSampleSchema.samplingConfigFor(widget.panelKey);
    if (node.sampleId != null) {
      await provider.selectPanelSample(widget.panelKey, node.sampleId!);
      return;
    }
    final sample = _firstSampleBelow(state, node.id);
    if (sample?.sampleId != null) {
      await provider.selectPanelSample(widget.panelKey, sample!.sampleId!);
    } else {
      final created = await provider.addPanelTerminalSample(
        widget.panelKey,
        parentId: node.id,
        identity: _defaultTerminalIdentity(config),
      );
      if (created.sampleId != null) {
        await provider.selectPanelSample(widget.panelKey, created.sampleId!);
      }
    }
  }

  Map<String, String>? _defaultTerminalIdentity(PanelSamplingConfig config) =>
      config.terminalLevel == SamplingScopeLevel.tray
      ? const {'code': 'T1', 'name': 'Tray 1'}
      : null;

  List<SamplingNode> _chain(PanelSamplingState state, SamplingNode node) {
    final result = <SamplingNode>[node];
    var current = node;
    while (current.parentId != null) {
      final parent = state.nodes
          .where((item) => item.id == current.parentId)
          .firstOrNull;
      if (parent == null) break;
      result.add(parent);
      current = parent;
    }
    return result.reversed.toList();
  }

  String? _nearestSelectedParentId(
    PanelSamplingConfig config,
    SamplingScopeLevel level,
    Map<SamplingScopeLevel, SamplingNode> selectedByLevel, {
    bool includeLevel = false,
  }) {
    final limit = config.levels.indexOf(level) + (includeLevel ? 1 : 0);
    String? parentId;
    for (var i = 0; i < limit; i++) {
      final selected = selectedByLevel[config.levels[i]];
      if (selected != null) parentId = selected.id;
    }
    return parentId;
  }

  SamplingNode? _firstSampleBelow(PanelSamplingState state, String nodeId) {
    final descendants = <String>{nodeId};
    var changed = true;
    while (changed) {
      changed = false;
      for (final node in state.nodes) {
        if (node.parentId != null &&
            descendants.contains(node.parentId) &&
            descendants.add(node.id)) {
          changed = true;
        }
      }
    }
    return state.samples
        .where((sample) => descendants.contains(sample.id))
        .firstOrNull;
  }

  String _identityLabel(SamplingNode node, bool paired) => paired
      ? '${node.identity['setter'] ?? ''} / ${node.identity['hatcher'] ?? ''}'
      : node.identity['name'] ??
            node.identity['code'] ??
            node.identityKey ??
            '';

  String _levelLabel(
    BuildContext context,
    SamplingScopeLevel level, {
    bool paired = false,
  }) => switch (level) {
    SamplingScopeLevel.house => context.tr('House'),
    SamplingScopeLevel.setter => context.tr(
      paired ? 'Setter / Hatcher' : 'Setter',
    ),
    SamplingScopeLevel.hatcher => context.tr('Hatcher'),
    SamplingScopeLevel.trolley => context.tr('Trolley'),
    SamplingScopeLevel.tray => context.tr('Tray'),
    SamplingScopeLevel.sample => context.tr('Sample'),
  };
}
