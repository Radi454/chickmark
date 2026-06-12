part of 'govee_live_reading_card.dart';

class _GoveeSettingsSheet extends StatelessWidget {
  const _GoveeSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoveeCaptureProvider>();
    final devices = provider.availableDevices;
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Govee settings', style: AppTextStyles.sectionTitle),
            const SizedBox(height: 14),
            _SettingsSection(
              title: 'Connection details',
              children: [
                _DetailRow(
                  label: 'Status',
                  value: _goveeConnectionStatus(provider).label,
                ),
                _DetailRow(
                  label: 'Device name',
                  value: _goveeDeviceName(provider.deviceName),
                ),
                _DetailRow(
                  label: 'Device ID',
                  value: provider.deviceId ?? '--',
                ),
                _DetailRow(
                  label: 'RSSI',
                  value: provider.signalStrength?.toString() ?? '--',
                ),
                _DetailRow(
                  label: 'Battery',
                  value: provider.batteryPercent == null
                      ? '--'
                      : '${provider.batteryPercent}%',
                ),
                _DetailRow(
                  label: 'Last update',
                  value: provider.liveUpdatedAt == null
                      ? '--'
                      : _formatDateTime(provider.liveUpdatedAt!),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: provider.isGattConnecting
                      ? null
                      : () => unawaited(provider.connectSensor()),
                  icon: Icon(
                    provider.isScanning
                        ? Icons.refresh
                        : Icons.bluetooth_searching,
                    size: 18,
                  ),
                  label: Text(provider.isScanning ? 'Restart scan' : 'Scan'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      provider.isSensorConnected || provider.isGattConnected
                      ? () => unawaited(provider.disconnectSensor())
                      : null,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Disconnect'),
                ),
                TextButton.icon(
                  onPressed:
                      provider.isSensorConnected || provider.isGattConnected
                      ? () => unawaited(provider.requestSensorReading())
                      : null,
                  icon: const Icon(Icons.sensors, size: 18),
                  label: const Text('Read now'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Available devices', style: AppTextStyles.sectionTitle),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              _EmptyDevicesNotice(isScanning: provider.isScanning)
            else
              ...devices.map((device) => _AvailableDeviceTile(device: device)),
            if (provider.bleDiagnostics.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Diagnostics', style: AppTextStyles.sectionTitle),
              const SizedBox(height: 8),
              ...provider.bleDiagnostics
                  .take(6)
                  .map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _DiagnosticLine(entry),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    return HatchDateUtils.formatDisplayDateTime(dateTime);
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticLine extends StatelessWidget {
  final String value;

  const _DiagnosticLine(this.value);

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      softWrap: true,
      style: AppTextStyles.caption,
    );
  }
}

class _EmptyDevicesNotice extends StatelessWidget {
  final bool isScanning;

  const _EmptyDevicesNotice({required this.isScanning});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isScanning
            ? 'Scanning for nearby Govee sensors...'
            : 'No available devices yet. Start a scan to discover sensors nearby.',
        style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _AvailableDeviceTile extends StatelessWidget {
  final GoveeAvailableDevice device;

  const _AvailableDeviceTile({required this.device});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: device.selected ? AppColors.statusActiveBg : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: device.selected ? AppColors.primary : AppColors.borderDefault,
        ),
      ),
      child: ListTile(
        dense: true,
        title: Text(
          device.name,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w900),
        ),
        subtitle: Text(
          '${device.remoteId} | RSSI ${device.rssi?.toString() ?? '--'}',
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption,
        ),
        trailing: device.selected
            ? const Icon(Icons.check_circle, color: AppColors.primary)
            : TextButton(
                onPressed: () => unawaited(
                  context.read<GoveeCaptureProvider>().selectSensorDevice(
                    device.remoteId,
                  ),
                ),
                child: const Text('Use'),
              ),
      ),
    );
  }
}
