import 'package:hatchaudit/localized_material.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/egg_batch_model.dart';
import '../../../data/models/egg_shipment_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../services/breeder/egg_batch_dispatch_service.dart';
import '../../../widgets/section_card.dart';
import 'egg_batch_entry_screen.dart';
import 'egg_shipment_entry_screen.dart';
import 'egg_shipment_detail_screen.dart';

/// Egg batches and hatchery-dispatch shipments for one flock
/// (breeder-flock-performance ticket 14, design doc section 8 and 12). A
/// separate workflow from the daily report and weighing sessions,
/// reachable from a flock's detail screen.
class EggBatchShipmentListScreen extends StatefulWidget {
  final FlockModel flock;
  final EggBatchDispatchService? service;

  const EggBatchShipmentListScreen({
    super.key,
    required this.flock,
    this.service,
  });

  @override
  State<EggBatchShipmentListScreen> createState() =>
      _EggBatchShipmentListScreenState();
}

class _EggBatchShipmentListScreenState
    extends State<EggBatchShipmentListScreen>
    with SingleTickerProviderStateMixin {
  late final EggBatchDispatchService _service =
      widget.service ?? EggBatchDispatchService();
  late final TabController _tabController;

  late Future<List<EggBatch>> _batchesFuture;
  late Future<List<EggShipment>> _shipmentsFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _batchesFuture = _service.listBatchesForFlock(widget.flock.id);
      _shipmentsFuture = _service.listShipmentsForFlock(widget.flock.id);
    });
  }

  Future<void> _createBatch() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EggBatchEntryScreen(flock: widget.flock, service: _service),
      ),
    );
    if (created == true && mounted) _reload();
  }

  Future<void> _createShipment() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EggShipmentEntryScreen(flock: widget.flock, service: _service),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openShipment(EggShipment shipment) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EggShipmentDetailScreen(
          flock: widget.flock,
          shipment: shipment,
          service: _service,
        ),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Egg stock — ${widget.flock.flockId}',
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: context.tr('Batches')),
            Tab(text: context.tr('Shipments')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildBatchesTab(), _buildShipmentsTab()],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('egg_batch_shipment_fab'),
        onPressed: () =>
            _tabController.index == 0 ? _createBatch() : _createShipment(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBatchesTab() {
    return FutureBuilder<List<EggBatch>>(
      future: _batchesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final batches = snapshot.data ?? const [];
        if (batches.isEmpty) {
          return _emptyState('No egg batches yet. Tap + to record one.');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSizes.cardPadding),
          itemCount: batches.length,
          itemBuilder: (context, index) {
            final batch = batches[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.cardPadding),
              child: SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    HatchDateUtils.formatDisplayDate(batch.collectionDate),
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('${batch.eggCount} eggs'),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildShipmentsTab() {
    return FutureBuilder<List<EggShipment>>(
      future: _shipmentsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final shipments = snapshot.data ?? const [];
        if (shipments.isEmpty) {
          return _emptyState('No shipments yet. Tap + to create one.');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(AppSizes.cardPadding),
          itemCount: shipments.length,
          itemBuilder: (context, index) {
            final shipment = shipments[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.cardPadding),
              child: SectionCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    HatchDateUtils.formatDisplayDate(shipment.shipmentDate),
                    style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(_statusLabel(shipment.status)),
                  onTap: () => _openShipment(shipment),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Text(
          context.tr(message),
          style: AppTextStyles.body,
          textAlign: TextAlign.center,
        ),
      ),
    );
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
