import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

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

/// Shared branch navigator for a single panel. State is loaded lazily so screens
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
      // Pooled scopes retain the nearest selected ancestor.
      parentId = selectedByLevel[level]?.id ?? parentId;
    }
    final branchLevels = config.levels
        .where(
          (level) =>
              level != SamplingScopeLevel.tray &&
              config.pairedLevels?.last != level,
        )
        .toList();
    final colors = Theme.of(context).colorScheme;
    final hasMultipleNativeSamples =
        state.childrenOf(parentId, SamplingScopeLevel.sample).length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            constraints.hasBoundedWidth &&
            constraints.maxWidth >= 600 &&
            branchLevels.isNotEmpty &&
            (config.terminalLevel == SamplingScopeLevel.tray ||
                hasMultipleNativeSamples);
        final branches = Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              colors.onSurface.withValues(alpha: 0.025),
              colors.surface,
            ),
            border: sideBySide
                ? BorderDirectional(
                    end: BorderSide(color: colors.outlineVariant),
                  )
                : Border(bottom: BorderSide(color: colors.outlineVariant)),
          ),
          child: _nestedScopes(
            context,
            provider,
            state,
            config,
            branchLevels,
            childrenByLevel,
            selectedByLevel,
            activeId,
          ),
        );
        final terminal = Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (config.terminalLevel == SamplingScopeLevel.tray)
                _levelControls(
                  context,
                  provider,
                  state,
                  config,
                  SamplingScopeLevel.tray,
                  childrenByLevel[SamplingScopeLevel.tray] ?? const [],
                  selectedByLevel[SamplingScopeLevel.tray],
                  selectedByLevel,
                  activeId,
                ),
              _terminalSamples(
                context,
                provider,
                state,
                config,
                selectedByLevel,
                activeId,
              ),
            ],
          ),
        );
        return Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('Sampling'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.tr(
                              'Select a branch for your measurements.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    _samplingActions(context, provider, config, chain),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              if (sideBySide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 240, child: branches),
                      Expanded(child: terminal),
                    ],
                  ),
                )
              else ...[
                if (branchLevels.isNotEmpty) branches,
                if (config.terminalLevel == SamplingScopeLevel.tray ||
                    hasMultipleNativeSamples)
                  terminal,
              ],
              if (activeSample != null) ...[
                Divider(height: 1, color: colors.outlineVariant),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _activeSampleCode(
                    context,
                    provider,
                    state,
                    activeSample,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _samplingActions(
    BuildContext context,
    AuditProvider provider,
    PanelSamplingConfig config,
    List<SamplingNode> chain,
  ) {
    final editable = chain
        .where(
          (node) =>
              node.level != SamplingScopeLevel.sample &&
              config.pairedLevels?.last != node.level,
        )
        .toList();
    return PopupMenuButton<(SamplingNode, bool)>(
      tooltip: context.tr('Sampling actions'),
      enabled:
          !provider.isReadOnly && !provider.isLoading && editable.isNotEmpty,
      icon: const Icon(Icons.more_horiz),
      onSelected: (action) {
        if (provider.isReadOnly || provider.isLoading) return;
        final (node, remove) = action;
        if (remove) {
          _delete(context, provider, node);
        } else {
          _edit(context, provider, node, config);
        }
      },
      itemBuilder: (context) => [
        for (final node in editable) ...[
          PopupMenuItem(
            key: ValueKey('sampling-edit-${node.id}'),
            value: (node, false),
            child: Text(
              context
                  .tr('Edit {scope}')
                  .replaceFirst(
                    '{scope}',
                    '${_levelLabel(context, node.level, paired: config.pairedLevels?.contains(node.level) ?? false)}: ${_identityLabel(node, config.pairedLevels?.contains(node.level) ?? false)}',
                  ),
            ),
          ),
          PopupMenuItem(
            key: ValueKey('sampling-remove-${node.id}'),
            value: (node, true),
            child: Text(
              context
                  .tr('Remove {scope}')
                  .replaceFirst(
                    '{scope}',
                    '${_levelLabel(context, node.level, paired: config.pairedLevels?.contains(node.level) ?? false)}: ${_identityLabel(node, config.pairedLevels?.contains(node.level) ?? false)}',
                  ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _nestedScopes(
    BuildContext context,
    AuditProvider provider,
    PanelSamplingState state,
    PanelSamplingConfig config,
    List<SamplingScopeLevel> levels,
    Map<SamplingScopeLevel, List<SamplingNode>> childrenByLevel,
    Map<SamplingScopeLevel, SamplingNode> selectedByLevel,
    String? activeId,
  ) {
    if (levels.isEmpty) return const SizedBox.shrink();
    final level = levels.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        if (levels.length > 1)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, top: 12),
            child: _nestedScopes(
              context,
              provider,
              state,
              config,
              levels.skip(1).toList(),
              childrenByLevel,
              selectedByLevel,
              activeId,
            ),
          ),
      ],
    );
  }

  Widget _branchChoice(
    BuildContext context, {
    required String key,
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
    String? serial,
    bool terminal = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey(key),
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                colors.primary.withValues(alpha: 0.08),
                colors.surface,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected ? colors.primary : colors.onSurface,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (serial != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    serial,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Icon(
                  terminal
                      ? (selected ? Icons.check : null)
                      : Icons.chevron_right,
                  textDirection: Directionality.of(context),
                  size: 18,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
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
    final displayNodes = paired
        ? nodes
              .where((node) => node.level == config.pairedLevels!.first)
              .toList()
        : nodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Tooltip(
              message: context.tr('Add {scope}').replaceFirst('{scope}', label),
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
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
                child: Text(
                  context.tr('Add {scope}').replaceFirst('{scope}', label),
                ),
              ),
            ),
          ],
        ),
        if (displayNodes.isEmpty && level != SamplingScopeLevel.tray)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              context.tr('Pooled'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final node in displayNodes) ...[
          if (level == SamplingScopeLevel.tray)
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          _branchChoice(
            context,
            key: 'sampling-node-${node.id}',
            label: _identityLabel(node, paired),
            selected: node.id == selected?.id,
            terminal: level == SamplingScopeLevel.tray,
            serial: node.sampleNumber == null ? null : 'SA${node.sampleNumber}',
            onPressed: readOnly
                ? null
                : () => _selectBranch(context, provider, state, node),
          ),
        ],
      ],
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
    if (config.terminalLevel != SamplingScopeLevel.sample) {
      return const SizedBox.shrink();
    }
    final parentId = config.levels.isEmpty
        ? null
        : _nearestSelectedParentId(
            config,
            config.levels.last,
            selectedByLevel,
            includeLevel: true,
          );
    final samples = state.childrenOf(parentId, SamplingScopeLevel.sample);
    if (samples.length <= 1) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('Sample'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        for (final sample in samples)
          _branchChoice(
            context,
            key: 'sampling-node-${sample.id}',
            label: 'SA${sample.sampleNumber ?? ''}',
            terminal: true,
            selected: sample.sampleId == activeId,
            onPressed:
                provider.isReadOnly ||
                    provider.isLoading ||
                    sample.sampleId == null
                ? null
                : () => provider.selectPanelSample(
                    widget.panelKey,
                    sample.sampleId!,
                  ),
          ),
      ],
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
    String? editingNodeId,
  }) async {
    if (level == SamplingScopeLevel.house) {
      return _houseIdentityDialog(
        context,
        initial: initial,
        state: state,
        parentId: parentId,
        editingNodeId: editingNodeId,
      );
    }
    final pair = config.pairedLevels?.contains(level) ?? false;
    final levels = pair ? config.pairedLevels! : [level];
    if (levels.any(_isMachineLevel)) {
      return _machineIdentityDialog(
        context,
        levels,
        initial: initial,
        state: state,
        parentId: parentId,
        editingNodeId: editingNodeId,
      );
    }
    if (level == SamplingScopeLevel.trolley ||
        level == SamplingScopeLevel.tray) {
      return _numberIdentityDialog(
        context,
        level,
        state: state,
        parentId: parentId,
        initial: initial,
        editingNodeId: editingNodeId,
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
    PanelSamplingState? state,
    String? parentId,
    String? editingNodeId,
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
    final siblings = (state?.nodes ?? const <SamplingNode>[])
        .where(
          (node) =>
              node.parentId == parentId &&
              levels.contains(node.level) &&
              node.id != editingNodeId,
        )
        .toList();
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
    final originalSelection = Map<SamplingScopeLevel, String?>.of(selected);

    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final ready = levels.every((level) => selected[level] != null);
          List<HatcheryMachineModel> optionsFor(SamplingScopeLevel level) {
            final candidates = machines
                .where((machine) => machine.kind == level.name)
                .toList();
            if (levels.length == 1) {
              return candidates
                  .where(
                    (machine) =>
                        machine.id == originalSelection[level] ||
                        !siblings.any(
                          (node) => _nodeUsesMachine(node, level, machine),
                        ),
                  )
                  .toList();
            }
            final otherLevel = levels.firstWhere((item) => item != level);
            final selectedOther = selected[otherLevel];
            if (selectedOther == null) return candidates;
            final otherMachine = machines
                .where((machine) => machine.id == selectedOther)
                .firstOrNull;
            final otherCode =
                otherMachine?.code ??
                (selectedOther.startsWith('legacy:')
                    ? selectedOther.substring('legacy:'.length)
                    : null);
            return candidates.where((machine) {
              final keepOriginalPair =
                  machine.id == originalSelection[level] &&
                  selected[level] == originalSelection[level] &&
                  selectedOther == originalSelection[otherLevel];
              if (keepOriginalPair) return true;
              return !siblings.any((node) {
                if (!_nodeUsesMachine(node, level, machine)) return false;
                if (otherMachine != null) {
                  return _nodeUsesMachine(node, otherLevel, otherMachine);
                }
                final stored =
                    node.identity[otherLevel.name] ??
                    (levels.length == 1 ? node.identity['code'] : null);
                return stored != null &&
                    stored.trim().toUpperCase() ==
                        otherCode?.trim().toUpperCase();
              });
            }).toList();
          }

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
                    key: ValueKey(
                      'machine-${level.name}-${selected[level]}-${optionsFor(level).map((machine) => machine.id).join(',')}',
                    ),
                    initialValue: selected[level],
                    decoration: InputDecoration(
                      labelText: _levelLabel(context, level),
                    ),
                    items: [
                      for (final machine in optionsFor(level))
                        DropdownMenuItem(
                          value: machine.id,
                          child: Text(machine.code),
                        ),
                      if (legacyCodes[level] != null)
                        DropdownMenuItem(
                          value: _legacyMachineValue(legacyCodes[level]!),
                          child: Text(
                            '${context.tr('Legacy')} · ${legacyCodes[level]}',
                          ),
                        ),
                    ],
                    onChanged: (value) => setDialogState(() {
                      selected[level] = value;
                      if (levels.length > 1) {
                        final otherLevel = levels.firstWhere(
                          (item) => item != level,
                        );
                        final selectedOther = selected[otherLevel];
                        if (selectedOther != null &&
                            !optionsFor(
                              otherLevel,
                            ).any((machine) => machine.id == selectedOther)) {
                          selected[otherLevel] = null;
                        }
                      }
                    }),
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
                  if (selected[level] == null && optionsFor(level).isEmpty)
                    Text(
                      machines.any((machine) => machine.kind == level.name)
                          ? context.tr(
                              'All registered machine choices for this scope are already used in this branch.',
                            )
                          : context.tr(
                              'No registered machine was found for this hatchery. Register a machine to add this scope.',
                            ),
                      style: Theme.of(context).textTheme.bodySmall,
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
    String? editingNodeId,
  }) async {
    var machine = await _machineForNumberedScope(context, state, parentId);
    if (!context.mounted) return null;
    final label = _levelLabel(context, level);
    var maximum = machine == null
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
    final usedNumbers = (state?.nodes ?? const <SamplingNode>[])
        .where(
          (node) =>
              node.parentId == parentId &&
              node.level == level &&
              node.id != editingNodeId,
        )
        .map(
          (node) => _numberFromIdentity(
            node.identity['code'] ?? node.identity['name'] ?? node.identityKey,
            level,
          ),
        )
        .whereType<int>()
        .toSet();
    if (originalNumber != null) usedNumbers.remove(originalNumber);
    List<int> availableNumbers() => [
      for (var number = 1; number <= maximum; number++)
        if (!usedNumbers.contains(number)) number,
    ];
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
                    'This machine is not available in the selected hatchery. Edit its scope to select a registered machine before adding numbered options.',
                  ),
                ),
              if (machine != null &&
                  availableNumbers().isEmpty &&
                  selected == null)
                Text(
                  context
                      .tr(
                        'All registered {scope} numbers are already used in this branch.',
                      )
                      .replaceFirst('{scope}', label),
                ),
              DropdownButtonFormField<String>(
                key: ValueKey(selected),
                initialValue: selected,
                decoration: InputDecoration(labelText: label),
                items: [
                  for (final number in availableNumbers())
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
                onChanged: availableNumbers().isEmpty && selected == null
                    ? null
                    : (value) => setDialogState(() => selected = value),
              ),
              if (machine != null)
                TextButton.icon(
                  onPressed: () async {
                    final updated = await showDialog<HatcheryMachineModel>(
                      context: dialogContext,
                      builder: (_) => HatcheryMachineEditorDialog(
                        hatcheryId: machine!.hatcheryId,
                        kind: machine!.kind,
                        repository: _machineRepository,
                        machine: machine,
                      ),
                    );
                    if (updated != null) {
                      setDialogState(() {
                        machine = updated;
                        maximum = level == SamplingScopeLevel.trolley
                            ? updated.trolleyCount
                            : updated.traysPerTrolley;
                        final selectedNumber = int.tryParse(selected ?? '');
                        if (selectedNumber != null &&
                            selectedNumber > maximum) {
                          selected = selectedNumber == originalNumber
                              ? 'legacy:$original'
                              : null;
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(context.tr('Edit capacities')),
                ),
              if (originalNumber != null &&
                  maximum > 0 &&
                  originalNumber > maximum)
                Padding(
                  padding: EdgeInsets.zero,
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

  Future<HatcheryMachineModel?> _machineForNumberedScope(
    BuildContext context,
    PanelSamplingState? state,
    String? parentId,
  ) async {
    if (state == null) return null;
    final hatcheryId = context.read<AuditProvider>().context?.hatcheryId;
    var current = parentId;
    while (current != null) {
      final node = state.nodes.where((item) => item.id == current).firstOrNull;
      if (node == null) return null;
      final levelsWithIdentity =
          [SamplingScopeLevel.hatcher, SamplingScopeLevel.setter].where((
            level,
          ) {
            final machineId = node.identity['${level.name}MachineId'];
            final machineCode =
                node.identity[level.name] ??
                (node.level == level ? node.identity['code'] : null);
            return (machineId != null && machineId.isNotEmpty) ||
                (machineCode != null && machineCode.isNotEmpty);
          }).toList();
      if (levelsWithIdentity.isNotEmpty) {
        // The nearest identity owns capacity. A stale nearer identity must not
        // make us borrow a different ancestor machine's capacity.
        final level = levelsWithIdentity.first;
        final machineId = node.identity['${level.name}MachineId'];
        final machineCode =
            node.identity[level.name] ??
            (node.level == level ? node.identity['code'] : null);
        HatcheryMachineModel? machine;
        if (machineId != null && machineId.isNotEmpty) {
          try {
            machine = await _machineRepository.getById(machineId);
          } catch (_) {
            machine = null;
          }
          if (machine != null &&
              (machine.hatcheryId != hatcheryId ||
                  machine.kind != level.name)) {
            machine = null;
          }
        }
        if (machine == null &&
            hatcheryId != null &&
            hatcheryId.isNotEmpty &&
            machineCode != null &&
            machineCode.isNotEmpty) {
          try {
            final candidates = await _machineRepository.getByHatchery(
              hatcheryId,
              kind: level.name,
            );
            machine = candidates
                .where(
                  (candidate) =>
                      candidate.code.trim().toUpperCase() ==
                      machineCode.trim().toUpperCase(),
                )
                .firstOrNull;
          } catch (_) {
            machine = null;
          }
        }
        return machine;
      }
      current = node.parentId;
    }
    return null;
  }

  bool _nodeUsesMachine(
    SamplingNode node,
    SamplingScopeLevel level,
    HatcheryMachineModel machine,
  ) {
    final machineId = node.identity['${level.name}MachineId'];
    final machineCode =
        node.identity[level.name] ??
        (node.level == level ? node.identity['code'] : null);
    return machineId == machine.id ||
        (machineCode != null &&
            machineCode.trim().toUpperCase() ==
                machine.code.trim().toUpperCase());
  }

  Future<Map<String, String>?> _houseIdentityDialog(
    BuildContext context, {
    Map<String, String>? initial,
    PanelSamplingState? state,
    String? parentId,
    String? editingNodeId,
  }) async {
    final provider = context.read<AuditProvider>();
    final flockId = provider.context?.flockId;
    if (flockId == null || flockId.isEmpty) return null;
    final List<HouseModel> houses;
    try {
      houses = await _houseRepository.listHouses(flockId, activeOnly: false);
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
    final siblings = (state?.nodes ?? const <SamplingNode>[])
        .where(
          (node) =>
              node.parentId == parentId &&
              node.level == SamplingScopeLevel.house &&
              node.id != editingNodeId,
        )
        .toList();
    List<HouseModel> availableHouses() => houses.where((house) {
      if (house.id == selectedHouse?.id) return true;
      if (!house.isActive && house.id != selectedHouse?.id) return false;
      return !siblings.any(
        (node) =>
            node.identity['id'] == house.id ||
            (node.identity['id'] == null &&
                (node.identity['code'] ?? node.identity['name'])
                        ?.trim()
                        .toUpperCase() ==
                    (house.code ?? house.name).trim().toUpperCase()),
      );
    }).toList();
    final initialAvailableHouses = availableHouses();
    final choices = <String, Map<String, String>>{
      for (final house in initialAvailableHouses)
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
              if (availableHouses().isEmpty && selected == null)
                Text(
                  houses.isEmpty
                      ? context.tr(
                          'No houses are registered for this flock yet.',
                        )
                      : context.tr(
                          'All registered houses are already used in this branch.',
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
              Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final house = await _editHouse(context, flockId: flockId);
                      if (house == null || !context.mounted) return;
                      houses
                        ..removeWhere((item) => item.id == house.id)
                        ..add(house);
                      choices[house.id] = {
                        'id': house.id,
                        'code': house.code?.trim().isNotEmpty == true
                            ? house.code!.trim()
                            : house.name,
                        'name': house.name,
                      };
                      setDialogState(() => selected = house.id);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.tr('Register house')),
                  ),
                  if (selected != null &&
                      availableHouses().any((house) => house.id == selected))
                    TextButton.icon(
                      onPressed: () async {
                        final existing = houses.firstWhere(
                          (house) => house.id == selected,
                        );
                        final house = await _editHouse(
                          context,
                          flockId: flockId,
                          existing: existing,
                        );
                        if (house == null || !context.mounted) return;
                        houses
                          ..removeWhere((item) => item.id == house.id)
                          ..add(house);
                        choices[house.id] = {
                          'id': house.id,
                          'code': house.code?.trim().isNotEmpty == true
                              ? house.code!.trim()
                              : house.name,
                          'name': house.name,
                        };
                        setDialogState(() => selected = house.id);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(context.tr('Edit house')),
                    ),
                ],
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

  Future<HouseModel?> _editHouse(
    BuildContext context, {
    required String flockId,
    HouseModel? existing,
  }) async {
    var nameValue = existing?.name ?? '';
    var codeValue = existing?.code ?? '';
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<HouseModel>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.tr(existing == null ? 'Register House' : 'Edit House'),
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: nameValue,
                  onChanged: (value) => nameValue = value,
                  decoration: InputDecoration(
                    labelText: context.tr('House name'),
                  ),
                  validator: (value) => value?.trim().isNotEmpty == true
                      ? null
                      : context.tr('Enter a house name.'),
                ),
                TextFormField(
                  initialValue: codeValue,
                  onChanged: (value) => codeValue = value,
                  decoration: InputDecoration(
                    labelText: context.tr('House code'),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final editedName = nameValue.trim();
              final editedCode = codeValue.trim().isEmpty
                  ? null
                  : codeValue.trim();
              final saved = existing == null
                  ? HouseModel(
                      id: const Uuid().v4(),
                      flockId: flockId,
                      name: editedName,
                      code: editedCode,
                    )
                  : HouseModel(
                      id: existing.id,
                      flockId: existing.flockId,
                      name: editedName,
                      code: editedCode,
                      capacity: existing.capacity,
                      openingFemales: existing.openingFemales,
                      openingMales: existing.openingMales,
                      notes: existing.notes,
                      isActive: existing.isActive,
                      createdBy: existing.createdBy,
                      createdAt: existing.createdAt,
                      updatedAt: existing.updatedAt,
                      syncStatus: existing.syncStatus,
                      dirtyAt: existing.dirtyAt,
                      lastSyncedAt: existing.lastSyncedAt,
                      syncError: existing.syncError,
                    );
              try {
                await _houseRepository.saveHouse(saved);
                if (dialogContext.mounted) Navigator.pop(dialogContext, saved);
              } catch (_) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: Text(context.tr('House could not be saved.')),
                    ),
                  );
                }
              }
            },
            child: Text(context.tr('Save')),
          ),
        ],
      ),
    );
    return result;
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
    final shortSample = 'SA${path.sampleNumber}';
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fullCode == null
                ? '${context.tr('Selected sample:')} $shortSample'
                : '${context.tr('Active sample:')} $fullCode',
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
      editingNodeId: node.id,
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
