import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/egg_batch_model.dart';
import '../../../data/models/egg_shipment_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../services/breeder/egg_batch_dispatch_service.dart';
import '../../../widgets/section_card.dart';
import '../../auth/providers/auth_provider.dart';

/// A shipment's batches, approval, cancellation, and receipt/variance
/// recording (breeder-flock-performance ticket 14, design doc section 8
/// and 12). While Draft, batches can be added/removed freely. Once
/// Approved, lines are permanent — cancellation reverses the whole dispatch
/// via a documented reversing ledger movement rather than editing a line
/// (design section 8: no destructive editing after approval).
class EggShipmentDetailScreen extends StatefulWidget {
  final FlockModel flock;
  final EggShipment shipment;
  final EggBatchDispatchService? service;
  final String? actorUserIdOverride;

  const EggShipmentDetailScreen({
    super.key,
    required this.flock,
    required this.shipment,
    this.service,
    this.actorUserIdOverride,
  });

  @override
  State<EggShipmentDetailScreen> createState() =>
      _EggShipmentDetailScreenState();
}

class _EggShipmentDetailScreenState extends State<EggShipmentDetailScreen> {
  late final EggBatchDispatchService _service =
      widget.service ?? EggBatchDispatchService();

  late EggShipment _shipment;
  List<EggShipmentBatch> _lines = [];
  Map<String, EggBatch> _batchesById = {};
  Map<String, int> _receivedByLine = {};
  Map<String, int> _varianceByLine = {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String? get _actorUserId =>
      widget.actorUserIdOverride ?? context.read<AuthProvider>().user?.id;

  @override
  void initState() {
    super.initState();
    _shipment = widget.shipment;
    _load();
  }

  Future<void> _load() async {
    final lines = await _service.linesForShipment(_shipment.id);
    final batches = <String, EggBatch>{};
    for (final line in lines) {
      final batch = batches[line.batchId] ??
          await _service.batchRepository.getById(line.batchId);
      if (batch != null) batches[line.batchId] = batch;
    }
    final received = <String, int>{};
    final variance = <String, int>{};
    if (_shipment.isApproved || _shipment.isCancelled) {
      for (final line in lines) {
        final receipt = await _service.receiptForShipmentLine(line.id);
        if (receipt != null) {
          received[line.id] = receipt.receivedQuantity;
          variance[line.id] = receipt.variance;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _batchesById = batches;
      _receivedByLine = received;
      _varianceByLine = variance;
      _loading = false;
    });
  }

  Future<void> _addBatch() async {
    final batches = await _service.listBatchesForFlock(_shipment.flockId);
    final eligible = <EggBatch>[];
    for (final batch in batches) {
      if (batch.gradeId != _shipment.gradeId) continue;
      final remaining = await _service.remainingForBatch(batch);
      if (remaining > 0) eligible.add(batch);
    }
    if (!mounted) return;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('No eligible batches with this grade and remaining stock'))),
      );
      return;
    }
    final result = await showDialog<(String, int)>(
      context: context,
      builder: (dialogContext) => _AddBatchDialog(
        service: _service,
        batches: eligible,
      ),
    );
    if (result == null) return;
    setState(() => _busy = true);
    try {
      await _service.addBatchToShipment(
        shipmentId: _shipment.id,
        batchId: result.$1,
        quantity: result.$2,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLine(EggShipmentBatch line) async {
    setState(() => _busy = true);
    try {
      await _service.removeShipmentLine(line.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final confirmed = await _confirm(
      title: 'Approve dispatch',
      message: 'This will record one inventory movement for this shipment. Continue?',
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final updated = await _service.approveShipment(
        shipmentId: _shipment.id,
        actorUserId: _actorUserId ?? 'unknown',
      );
      if (!mounted) return;
      setState(() => _shipment = updated);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = await _promptText(
      title: 'Cancel shipment',
      label: 'Reason',
    );
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final updated = await _service.cancelShipment(
        shipmentId: _shipment.id,
        reason: reason.trim(),
        actorUserId: _actorUserId ?? 'unknown',
      );
      if (!mounted) return;
      setState(() => _shipment = updated);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordReceipt(EggShipmentBatch line) async {
    final text = await _promptText(
      title: 'Record receipt',
      label: 'Eggs received',
      keyboardType: TextInputType.number,
    );
    if (text == null) return;
    final receivedQuantity = int.tryParse(text.trim());
    if (receivedQuantity == null || receivedQuantity < 0) {
      if (!mounted) return;
      setState(() => _error = 'Enter a non-negative received quantity');
      return;
    }
    setState(() => _busy = true);
    try {
      await _service.recordReceipt(
        shipmentBatchId: line.id,
        receivedQuantity: receivedQuantity,
        recordedBy: _actorUserId ?? 'unknown',
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(title)),
        content: Text(context.tr(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('Confirm')),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr(title)),
        content: TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(labelText: context.tr(label)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(context.tr('Save')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Shipment — ${HatchDateUtils.formatDisplayDate(_shipment.shipmentDate)}',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: AppSizes.cardPadding),
                  _buildLinesCard(),
                  const SizedBox(height: AppSizes.cardPadding),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: AppColors.statusError)),
                    const SizedBox(height: AppSizes.cardPadding),
                  ],
                  _buildActions(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${context.tr('Status')}: ${_statusLabel(_shipment.status)}',
            style: AppTextStyles.sectionTitle,
          ),
          if (_shipment.isCancelled && _shipment.cancelReason != null) ...[
            const SizedBox(height: 4),
            Text('${context.tr('Reason')}: ${_shipment.cancelReason}'),
          ],
        ],
      ),
    );
  }

  Widget _buildLinesCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.tr('Batches'), style: AppTextStyles.sectionTitle),
              ),
              if (_shipment.isDraft)
                IconButton(
                  key: const Key('egg_shipment_add_batch_button'),
                  icon: const Icon(Icons.add),
                  onPressed: _busy ? null : _addBatch,
                ),
            ],
          ),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(context.tr('No batches attached yet.')),
            ),
          for (final line in _lines) _buildLineRow(line),
        ],
      ),
    );
  }

  Widget _buildLineRow(EggShipmentBatch line) {
    final batch = _batchesById[line.batchId];
    final received = _receivedByLine[line.id];
    final variance = _varianceByLine[line.id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batch != null
                      ? HatchDateUtils.formatDisplayDate(batch.collectionDate)
                      : line.batchId,
                ),
                Text(
                  '${context.tr('Dispatched')}: ${line.quantity}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                if (received != null)
                  Text(
                    '${context.tr('Received')}: $received '
                    '(${context.tr('variance')} ${variance != null && variance >= 0 ? '+' : ''}${variance ?? 0})',
                    style: TextStyle(
                      fontSize: 12,
                      color: (variance ?? 0) == 0
                          ? Colors.grey
                          : AppColors.statusError,
                    ),
                  ),
              ],
            ),
          ),
          if (_shipment.isDraft)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: _busy ? null : () => _removeLine(line),
            )
          else if (_shipment.isApproved && received == null)
            TextButton(
              key: Key('egg_shipment_receipt_button_${line.id}'),
              onPressed: _busy ? null : () => _recordReceipt(line),
              child: Text(context.tr('Record receipt')),
            ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    if (_shipment.isDraft) {
      return ElevatedButton(
        key: const Key('egg_shipment_approve_button'),
        onPressed: _busy || _lines.isEmpty ? null : _approve,
        child: Text(context.tr('Approve dispatch')),
      );
    }
    if (_shipment.isApproved) {
      return OutlinedButton(
        key: const Key('egg_shipment_cancel_button'),
        onPressed: _busy ? null : _cancel,
        child: Text(context.tr('Cancel shipment')),
      );
    }
    return const SizedBox.shrink();
  }

  String _statusLabel(String status) {
    switch (status) {
      case EggShipmentStatus.approved:
        return context.tr('Approved');
      case EggShipmentStatus.cancelled:
        return context.tr('Cancelled');
      default:
        return context.tr('Draft');
    }
  }
}

class _AddBatchDialog extends StatefulWidget {
  final EggBatchDispatchService service;
  final List<EggBatch> batches;

  const _AddBatchDialog({required this.service, required this.batches});

  @override
  State<_AddBatchDialog> createState() => _AddBatchDialogState();
}

class _AddBatchDialogState extends State<_AddBatchDialog> {
  String? _batchId;
  final _quantityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _batchId = widget.batches.isNotEmpty ? widget.batches.first.id : null;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Add batch')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: const Key('egg_shipment_batch_dropdown'),
            initialValue: _batchId,
            decoration: InputDecoration(labelText: context.tr('Batch')),
            items: widget.batches
                .map(
                  (b) => DropdownMenuItem(
                    value: b.id,
                    child: Text(
                      '${HatchDateUtils.formatDisplayDate(b.collectionDate)} '
                      '(${b.eggCount})',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _batchId = value),
          ),
          TextField(
            key: const Key('egg_shipment_batch_quantity_field'),
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('Quantity')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        TextButton(
          onPressed: () {
            final batchId = _batchId;
            final quantity = int.tryParse(_quantityController.text.trim());
            if (batchId == null || quantity == null || quantity < 0) return;
            Navigator.pop(context, (batchId, quantity));
          },
          child: Text(context.tr('Add')),
        ),
      ],
    );
  }
}
