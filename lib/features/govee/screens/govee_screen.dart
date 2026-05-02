import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../data/models/hatchery_model.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../data/repositories/govee_capture_repository.dart';
import '../../../features/dashboard/models/govee_capture_summary.dart';
import '../../../features/dashboard/widgets/govee_capture_chart.dart';
import '../../../providers/customers_provider.dart';
import '../utils/govee_place_flow.dart';

class GoveeScreen extends StatefulWidget {
  final GoveeCaptureRepository? repository;

  const GoveeScreen({super.key, this.repository});

  @override
  State<GoveeScreen> createState() => _GoveeScreenState();
}

class _GoveeScreenState extends State<GoveeScreen> {
  late final GoveeCaptureRepository _repository =
      widget.repository ?? GoveeCaptureRepository();

  String? _customerId;
  String? _hatcheryId;
  String? _captureDate;
  TemperaturePlace? _place;
  bool _isLoading = false;
  List<GoveeCaptureSummary> _summaries = const [];

  @override
  void initState() {
    super.initState();
    _captureDate = _formatDate(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSummaries();
    });
  }

  @override
  Widget build(BuildContext context) {
    final customers = context.watch<CustomersProvider>();
    final selectedCustomer = _customerId == null
        ? null
        : customers.customerById(_customerId!);
    final hatcheries = selectedCustomer == null
        ? const <HatcheryModel>[]
        : customers.hatcheries;

    return Scaffold(
      appBar: const GradientAppBar(title: 'Govee'),
      body: RefreshIndicator(
        onRefresh: _loadSummaries,
        child: ListView(
          padding: const EdgeInsets.all(AppSizes.cardPadding),
          children: [
            Text(
              'Saved Govee captures',
              style: AppTextStyles.heading.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 4),
            Text(
              'Browse saved H5051 history-sync captures by scope.',
              style: AppTextStyles.caption,
            ),
            const SizedBox(height: 14),
            _filters(customers, hatcheries),
            const SizedBox(height: 14),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_summaries.isEmpty)
              const _EmptyGoveeHistory()
            else
              ..._summaries.map(
                (summary) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GoveeCaptureChart(summary: summary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _filters(CustomersProvider customers, List<HatcheryModel> hatcheries) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        side: const BorderSide(color: AppColors.borderDefault),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('govee-history-customer-filter'),
              initialValue: _customerId ?? '',
              decoration: const InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(value: '', child: Text('All customers')),
                ...customers.allCustomers.map(
                  (customer) => DropdownMenuItem(
                    value: customer.id,
                    child: Text(customer.name),
                  ),
                ),
              ],
              onChanged: (value) async {
                final next = value == null || value.isEmpty ? null : value;
                setState(() {
                  _customerId = next;
                  _hatcheryId = null;
                });
                final customer = next == null
                    ? null
                    : customers.customerById(next);
                if (customer != null) {
                  await customers.selectCustomer(customer);
                }
                if (!mounted) return;
                await _loadSummaries();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('govee-history-hatchery-filter'),
              initialValue: _hatcheryId ?? '',
              decoration: const InputDecoration(
                labelText: 'Hatchery',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('All hatcheries'),
                ),
                ...hatcheries.map(
                  (hatchery) => DropdownMenuItem<String>(
                    value: hatchery.id,
                    child: Text(hatchery.name),
                  ),
                ),
              ],
              onChanged: (value) async {
                setState(() {
                  _hatcheryId = value == null || value.isEmpty ? null : value;
                });
                await _loadSummaries();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('govee-history-date-filter'),
                    onPressed: () async {
                      final current =
                          DateTime.tryParse(_captureDate ?? '') ??
                          DateTime.now();
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: current,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (selected == null || !mounted) return;
                      setState(() => _captureDate = _formatDate(selected));
                      await _loadSummaries();
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_captureDate ?? 'All dates'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<TemperaturePlace?>(
                    key: const ValueKey('govee-history-place-filter'),
                    initialValue: _place,
                    decoration: const InputDecoration(
                      labelText: 'Place',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<TemperaturePlace?>(
                        value: null,
                        child: Text('All places'),
                      ),
                      ...goveePlaceFlow.map(
                        (place) => DropdownMenuItem<TemperaturePlace?>(
                          value: place,
                          child: Text(place.label),
                        ),
                      ),
                    ],
                    onChanged: (place) async {
                      setState(() => _place = place);
                      await _loadSummaries();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadSummaries() async {
    setState(() => _isLoading = true);
    try {
      final summaries = await _repository.getCaptureSummaries(
        customerId: _customerId,
        hatcheryId: _hatcheryId,
        captureDate: _captureDate,
        place: _place,
      );
      if (!mounted) return;
      setState(() => _summaries = summaries);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _EmptyGoveeHistory extends StatelessWidget {
  const _EmptyGoveeHistory();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.device_thermostat_outlined,
            color: AppColors.primary,
            size: 34,
          ),
          const SizedBox(height: 10),
          Text(
            'No saved Govee captures',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Use the floating Govee button during audits to record a place.',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}
