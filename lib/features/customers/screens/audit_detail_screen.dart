import 'package:flutter/material.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/audit_model.dart';
import '../../../widgets/status_badge.dart';

class AuditDetailScreen extends StatelessWidget {
  final AuditModel audit;

  const AuditDetailScreen({super.key, required this.audit});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(title: 'Audit Details'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Audit Information'),
            _buildDetailTile('Audit Type', audit.auditType),
            _buildDetailTile(
              'Status',
              '',
              trailing: StatusBadge(status: audit.status),
            ),
            _buildDetailTile('Date', _formatDate(audit.date)),
            if (audit.notes != null) _buildDetailTile('Notes', audit.notes!),

            if (audit.setterId != null)
              _buildDetailTile('Setter ID', audit.setterId!),
            if (audit.hatcherId != null)
              _buildDetailTile('Hatcher ID', audit.hatcherId!),

            _buildSectionHeader('Chick Quality: CHA Environmental'),
            if (audit.chaGoveeConnected != null)
              _buildDetailTile(
                'Govee Connected',
                audit.chaGoveeConnected! ? 'Yes' : 'No',
              ),
            if (audit.chaCo2 != null)
              _buildDetailTile('CO2', '${audit.chaCo2} ppm'),
            if (audit.chaPm10 != null)
              _buildDetailTile('PM10', '${audit.chaPm10} µg/m³'),
            if (audit.chaPm25 != null)
              _buildDetailTile('PM2.5', '${audit.chaPm25} µg/m³'),
            if (audit.chaAirVelocitySpot1 != null)
              _buildDetailTile(
                'Air Velocity (Spot 1)',
                '${audit.chaAirVelocitySpot1} m/s',
              ),
            if (audit.chaAirVelocitySpot2 != null)
              _buildDetailTile(
                'Air Velocity (Spot 2)',
                '${audit.chaAirVelocitySpot2} m/s',
              ),
            if (audit.chaAirVelocitySpot3 != null)
              _buildDetailTile(
                'Air Velocity (Spot 3)',
                '${audit.chaAirVelocitySpot3} m/s',
              ),
            if (audit.chaAirInlet != null)
              _buildDetailTile('Air Inlet', '${audit.chaAirInlet} °C'),
            if (audit.chaAirOutlet != null)
              _buildDetailTile('Air Outlet', '${audit.chaAirOutlet} °C'),
            if (audit.chaNoiseLevel != null)
              _buildDetailTile('Noise Level', '${audit.chaNoiseLevel} dB'),

            _buildSectionHeader('Chick Quality: Pasgar'),
            if (audit.pasgarSampleSize != null)
              _buildDetailTile('Sample Size', '${audit.pasgarSampleSize}'),
            if (audit.pasgarReflexes != null)
              _buildDetailTile('Reflexes', '${audit.pasgarReflexes}'),
            if (audit.pasgarBeak != null)
              _buildDetailTile('Beak', '${audit.pasgarBeak}'),
            if (audit.pasgarNavel != null)
              _buildDetailTile('Navel', '${audit.pasgarNavel}'),
            if (audit.pasgarBelly != null)
              _buildDetailTile('Belly', '${audit.pasgarBelly}'),
            if (audit.pasgarLeg != null)
              _buildDetailTile('Leg', '${audit.pasgarLeg}'),
            if (audit.pasgarFeatherDev != null)
              _buildDetailTile('Feather Dev', '${audit.pasgarFeatherDev}'),
            if (audit.pasgarFinalScore != null)
              _buildDetailTile('Final Score', '${audit.pasgarFinalScore}'),

            _buildSectionHeader('Chick Quality: Weights'),
            if (audit.chickStorageDays != null)
              _buildDetailTile('Storage Days', '${audit.chickStorageDays}'),
            if (audit.chickSampleSize != null)
              _buildDetailTile('Sample Size', '${audit.chickSampleSize}'),
            if (audit.chickAvgWeight != null)
              _buildDetailTile('Avg Weight', '${audit.chickAvgWeight}g'),
            if (audit.chickUniformityPct != null)
              _buildDetailTile('Uniformity', '${audit.chickUniformityPct}%'),
            if (audit.chickCvPct != null)
              _buildDetailTile('CV', '${audit.chickCvPct}%'),
            if (audit.chickBmkAge != null)
              _buildDetailTile('BMK Age', '${audit.chickBmkAge} days'),
            if (audit.chickBmkWeight != null)
              _buildDetailTile('BMK Weight', '${audit.chickBmkWeight}g'),

            _buildSectionHeader('Chick Quality: YFBM'),
            if (audit.yfbmAvgPct != null)
              _buildDetailTile('Avg %', '${audit.yfbmAvgPct}%'),
            if (audit.yfbmCvPct != null)
              _buildDetailTile('CV %', '${audit.yfbmCvPct}%'),

            _buildSectionHeader('Chick Quality: CVT'),
            if (audit.cvtSampleSize != null)
              _buildDetailTile('Sample Size', '${audit.cvtSampleSize}'),
            if (audit.cvtTopTemp != null)
              _buildDetailTile('Top Temp', '${audit.cvtTopTemp}°C'),
            if (audit.cvtMiddleTemp != null)
              _buildDetailTile('Middle Temp', '${audit.cvtMiddleTemp}°C'),
            if (audit.cvtBottomTemp != null)
              _buildDetailTile('Bottom Temp', '${audit.cvtBottomTemp}°C'),
            if (audit.cvtAvg != null)
              _buildDetailTile('Average', '${audit.cvtAvg}°C'),
            if (audit.cvtCvPct != null)
              _buildDetailTile('CV %', '${audit.cvtCvPct}%'),

            _buildSectionHeader('Hatch Analysis: Hatch Results'),
            if (audit.haStorageDays != null)
              _buildDetailTile('Storage Days', '${audit.haStorageDays}'),
            if (audit.haTotalEggsSet != null)
              _buildDetailTile('Total Eggs Set', '${audit.haTotalEggsSet}'),
            if (audit.haHatched != null)
              _buildDetailTile('Hatched', '${audit.haHatched}'),
            if (audit.haCulled != null)
              _buildDetailTile('Culled', '${audit.haCulled}'),
            if (audit.haDead != null)
              _buildDetailTile('Dead', '${audit.haDead}'),
            if (audit.haHatchability != null)
              _buildDetailTile('Hatchability', '${audit.haHatchability}%'),
            if (audit.haFertility != null)
              _buildDetailTile('Fertility', '${audit.haFertility}%'),
            if (audit.haHof != null) _buildDetailTile('HOF', '${audit.haHof}%'),
            if (audit.haBmkAge != null)
              _buildDetailTile('BMK Age', '${audit.haBmkAge} days'),

            _buildSectionHeader('Hatch Analysis: Egg Breakout'),
            if (audit.ebTraySize != null)
              _buildDetailTile('Tray Size', '${audit.ebTraySize}'),
            if (audit.ebBreakoutType != null)
              _buildDetailTile('Breakout Type', audit.ebBreakoutType!),
            if (audit.ebBreakoutAgeDays != null)
              _buildDetailTile(
                'Breakout Age',
                '${audit.ebBreakoutAgeDays} days',
              ),
            if (audit.ebStorageDays != null)
              _buildDetailTile('Storage Days', '${audit.ebStorageDays}'),
            if (audit.ebBmkAge != null)
              _buildDetailTile('BMK Age', '${audit.ebBmkAge} days'),
            if (audit.ebInfertileCount != null)
              _buildDetailTile('Infertile Eggs', '${audit.ebInfertileCount}'),
            if (audit.ebEarlyDeadCount != null)
              _buildDetailTile('Early Dead Eggs', '${audit.ebEarlyDeadCount}'),
            if (audit.ebMidDeadCount != null)
              _buildDetailTile('Mid Black Eye Eggs', '${audit.ebMidDeadCount}'),
            if (audit.ebLateDeadCount != null)
              _buildDetailTile('Late Dead Eggs', '${audit.ebLateDeadCount}'),
            if (audit.ebInternalPipCount != null)
              _buildDetailTile(
                'Internal Pip Eggs',
                '${audit.ebInternalPipCount}',
              ),
            if (audit.ebExternalPipCount != null)
              _buildDetailTile(
                'External Pip Eggs',
                '${audit.ebExternalPipCount}',
              ),
            if (audit.ebCrackedCount != null)
              _buildDetailTile('Cracked Eggs', '${audit.ebCrackedCount}'),
            if (audit.ebContaminatedCount != null)
              _buildDetailTile(
                'Contaminated Eggs',
                '${audit.ebContaminatedCount}',
              ),
            if (audit.ebMalpositionCount != null)
              _buildDetailTile(
                'Malposition Eggs',
                '${audit.ebMalpositionCount}',
              ),
            if (audit.ebExposedBrainCount != null)
              _buildDetailTile(
                'Exposed Brain Eggs',
                '${audit.ebExposedBrainCount}',
              ),
            if (audit.ebCrossedBeakCount != null)
              _buildDetailTile(
                'Crossed Beak Eggs',
                '${audit.ebCrossedBeakCount}',
              ),
            if (audit.ebCulledDeadCount != null)
              _buildDetailTile(
                'Culled / Dead Eggs',
                '${audit.ebCulledDeadCount}',
              ),

            _buildSectionHeader('Setter Optimizing'),
            if (audit.soBreed != null)
              _buildDetailTile('Breed', audit.soBreed!),
            if (audit.soSetterId != null)
              _buildDetailTile('Setter ID', audit.soSetterId!),
            if (audit.soIncubationAge != null)
              _buildDetailTile(
                'Incubation Age',
                '${audit.soIncubationAge} days',
              ),
            if (audit.soGoveeConnected != null)
              _buildDetailTile(
                'Govee Connected',
                audit.soGoveeConnected! ? 'Yes' : 'No',
              ),
            if (audit.soGoveeTemp != null)
              _buildDetailTile('Govee Temp', '${audit.soGoveeTemp}°C'),
            if (audit.soGoveeHumidity != null)
              _buildDetailTile('Govee Humidity', '${audit.soGoveeHumidity}%'),
            if (audit.soCo2 != null)
              _buildDetailTile('CO2', '${audit.soCo2} ppm'),
            if (audit.soEstAvg != null)
              _buildDetailTile('EST Avg', '${audit.soEstAvg}°C'),
            if (audit.soEstCv != null)
              _buildDetailTile('EST CV', '${audit.soEstCv}%'),

            _buildSectionHeader('Hatcher Optimizing'),
            if (audit.hoBreed != null)
              _buildDetailTile('Breed', audit.hoBreed!),
            if (audit.hoHatcherId != null)
              _buildDetailTile('Hatcher ID', audit.hoHatcherId!),
            if (audit.hoIncubationAge != null)
              _buildDetailTile(
                'Incubation Age',
                '${audit.hoIncubationAge} days',
              ),
            if (audit.hoGoveeConnected != null)
              _buildDetailTile(
                'Govee Connected',
                audit.hoGoveeConnected! ? 'Yes' : 'No',
              ),
            if (audit.hoGoveeTemp != null)
              _buildDetailTile('Govee Temp', '${audit.hoGoveeTemp}°C'),
            if (audit.hoGoveeHumidity != null)
              _buildDetailTile('Govee Humidity', '${audit.hoGoveeHumidity}%'),
            if (audit.hoCo2 != null)
              _buildDetailTile('CO2', '${audit.hoCo2} ppm'),
            if (audit.hoCvtAvg != null)
              _buildDetailTile('CVT Avg', '${audit.hoCvtAvg}°C'),
            if (audit.hoCvtCv != null)
              _buildDetailTile('CVT CV', '${audit.hoCvtCv}%'),
            if (audit.hoChickPanting != null)
              _buildDetailTile(
                'Chick Panting',
                audit.hoChickPanting! ? 'Yes' : 'No',
              ),

            _buildSectionHeader('Egg Storage'),
            if (audit.esGoveeConnected != null)
              _buildDetailTile(
                'Govee Connected',
                audit.esGoveeConnected! ? 'Yes' : 'No',
              ),
            if (audit.esGoveeTemp != null)
              _buildDetailTile('Govee Temp', '${audit.esGoveeTemp}°C'),
            if (audit.esGoveeHumidity != null)
              _buildDetailTile('Govee Humidity', '${audit.esGoveeHumidity}%'),
            if (audit.esCo2 != null)
              _buildDetailTile('CO2', '${audit.esCo2} ppm'),
            if (audit.esShellTemp != null)
              _buildDetailTile('Shell Temp', '${audit.esShellTemp}°C'),
            if (audit.esTurningTimes != null)
              _buildDetailTile('Turning Times', '${audit.esTurningTimes}'),
            if (audit.esEggStorageDays != null)
              _buildDetailTile('Storage Days', '${audit.esEggStorageDays}'),
            if (audit.esEggSampleSize != null)
              _buildDetailTile('Sample Size', '${audit.esEggSampleSize}'),
            if (audit.esEggAvgWeight != null)
              _buildDetailTile('Avg Weight', '${audit.esEggAvgWeight}g'),
            if (audit.esEggUniformityPct != null)
              _buildDetailTile('Uniformity', '${audit.esEggUniformityPct}%'),
            if (audit.esEggCvPct != null)
              _buildDetailTile('CV', '${audit.esEggCvPct}%'),
            if (audit.esEggBmkAge != null)
              _buildDetailTile('BMK Age', '${audit.esEggBmkAge} days'),
            if (audit.esEggBmkWeight != null)
              _buildDetailTile('BMK Weight', '${audit.esEggBmkWeight}g'),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        title,
        style: AppTextStyles.heading.copyWith(
          fontSize: 18,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildDetailTile(String label, String value, {Widget? trailing}) {
    return Card(
      elevation: 0,
      color: AppColors.background,
      child: ListTile(
        title: Text(
          label,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w500),
        ),
        trailing: trailing ?? Text(value, style: AppTextStyles.body),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')} '
        '${_monthAbbreviation(date.month)} '
        '${date.year}';
  }

  String _monthAbbreviation(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}
