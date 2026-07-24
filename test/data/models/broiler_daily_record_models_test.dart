import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/broiler_daily_record_models.dart';

void main() {
  BroilerDailyRecordDraft validDraft({
    VerificationStatus status = VerificationStatus.entered,
    String? correctionReason,
    String? verifiedBy,
    DateTime? verifiedAt,
  }) {
    return BroilerDailyRecordDraft(
      placementId: 'placement-1',
      recordDate: DateTime.utc(2026, 7, 24),
      verificationStatus: status,
      dataSourceType: DailyDataSourceType.manual,
      reportedBy: 'Farm clerk',
      enteredBy: 'auditor-1',
      enteredAt: DateTime.utc(2026, 7, 24, 18),
      correctionReason: correctionReason,
      verifiedBy: verifiedBy,
      verifiedAt: verifiedAt,
      openingBirdCount: 10000,
      dailyMortality: 10,
      dailyCulls: 2,
      transfersIn: 0,
      transfersOut: 0,
      partialDepletion: 0,
      otherPopulationAdjustment: 0,
      closingLiveBirdCount: 9988,
      mortalityCauses: const {'sudden_death': 6, 'unknown': 4},
      dailyFeedConsumedKg: 1020,
      waterConsumedLiters: 1836,
      averageBodyWeightG: 1250,
      birdsWeighed: 100,
      uniformityPct: 82,
      cvPct: 9.5,
      individualWeightsG: const [1200, 1250, 1300],
      minTemperatureC: 21,
      maxTemperatureC: 28,
      relativeHumidityPct: 61,
      co2Ppm: 1750,
    );
  }

  test(
    'valid population, production, and environment facts pass validation',
    () {
      expect(() => validDraft().validate(), returnsNormally);
      expect(validDraft().mortalityCauses['sudden_death'], 6);
      expect(validDraft().individualWeightsG, hasLength(3));
    },
  );

  test('population arithmetic and non-negative facts are enforced', () {
    expect(
      () => validDraft().copyWith(closingLiveBirdCount: 9990).validate(),
      throwsA(isA<DailyRecordValidationException>()),
    );
    expect(
      () => validDraft().copyWith(dailyFeedConsumedKg: -1).validate(),
      throwsA(isA<DailyRecordValidationException>()),
    );
  });

  test('corrected and verified revisions require their provenance', () {
    expect(
      () => validDraft(status: VerificationStatus.corrected).validate(),
      throwsA(isA<DailyRecordValidationException>()),
    );
    expect(
      () => validDraft(
        status: VerificationStatus.corrected,
        correctionReason: 'Checked the signed mortality sheet',
      ).validate(),
      returnsNormally,
    );
    expect(
      () => validDraft(status: VerificationStatus.verified).validate(),
      throwsA(isA<DailyRecordValidationException>()),
    );
    expect(
      () => validDraft(
        status: VerificationStatus.verified,
        verifiedBy: 'supervisor-1',
        verifiedAt: DateTime.utc(2026, 7, 25),
      ).validate(),
      returnsNormally,
    );
  });

  test(
    'typed source and event drafts round-trip their operational metadata',
    () {
      const source = DailyRecordSourceDraft(
        sourceKind: DailyRecordSourceKind.spreadsheet,
        localPath: '/documents/farm-day-24.xlsx',
        originalFilename: 'farm-day-24.xlsx',
        checksum: 'sha256:test',
      );
      final event = BroilerDailyEventDraft(
        eventType: BroilerDailyEventType.waterFailure,
        eventAt: DateTime.utc(2026, 7, 24, 10),
        isAllDay: false,
        eventState: DailyEventState.resolved,
        description: 'Header tank valve blocked',
        equipment: 'Header tank valve',
      );

      expect(source.toMap()['sourceKind'], 'spreadsheet');
      expect(
        DailyRecordSourceDraft.fromMap(source.toMap()).originalFilename,
        'farm-day-24.xlsx',
      );
      expect(event.toMap()['eventType'], 'water_failure');
      expect(
        BroilerDailyEventDraft.fromMap(event.toMap()).eventState,
        DailyEventState.resolved,
      );
    },
  );
}
