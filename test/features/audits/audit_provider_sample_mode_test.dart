import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/sample_mode.dart';
import 'package:hatchaudit/features/audits/providers/audit_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          if (call.method == 'check') return ['wifi'];
          return null;
        });
  });

  AuditContext context() => AuditContext(
    auditType: 'Chick Quality',
    customerId: 'customer-1',
    flockId: 'flock-1',
    date: '2026-04-27',
  );

  test('new audit sessions default to pooled sampling', () {
    final provider = AuditProvider();

    provider.initialize(context(), notify: false);

    expect(provider.sampleMode, SampleMode.pool);
    expect(provider.isCompareMode, isFalse);
    expect(provider.hatchCount, 1);
    expect(provider.activeDraft.hatchNumber, 1);
    expect(provider.activeDraft.compareGroupKey, isNull);
  });

  test('compare mode gives all hatch drafts the same compare group key', () {
    final provider = AuditProvider();
    provider.initialize(context(), notify: false);

    provider.setSampleMode(SampleMode.compare);
    provider.addHatch();

    final groupKey = provider.drafts.first.compareGroupKey;
    expect(groupKey, isNotNull);
    expect(provider.hatchCount, 2);
    expect(provider.drafts.map((draft) => draft.sampleMode), [
      SampleMode.compare,
      SampleMode.compare,
    ]);
    expect(provider.drafts.map((draft) => draft.compareGroupKey).toSet(), {
      groupKey,
    });
    expect(provider.drafts.map((draft) => draft.hatchNumber), [1, 2]);
  });

  test('switching back to pool keeps one pooled sample only', () {
    final provider = AuditProvider();
    provider.initialize(context(), notify: false);

    provider.setSampleMode(SampleMode.compare);
    provider.addHatch();
    provider.setSampleMode(SampleMode.pool);

    expect(provider.sampleMode, SampleMode.pool);
    expect(provider.isCompareMode, isFalse);
    expect(provider.hatchCount, 1);
    expect(provider.activeDraft.hatchNumber, 1);
    expect(provider.activeDraft.compareGroupKey, isNull);
  });

  test('removeActiveHatch keeps compare hatch numbers sequential', () {
    final provider = AuditProvider();
    provider.initialize(context(), notify: false);

    provider.setSampleMode(SampleMode.compare);
    provider.addHatch();
    provider.addHatch();
    provider.switchHatch(1);
    provider.removeActiveHatch();

    expect(provider.isCompareMode, isTrue);
    expect(provider.hatchCount, 2);
    expect(provider.activeHatchIndex, 1);
    expect(provider.drafts.map((draft) => draft.hatchNumber), [1, 2]);
    expect(provider.drafts.map((draft) => draft.compareGroupKey).toSet(), {
      provider.drafts.first.compareGroupKey,
    });
  });
}
