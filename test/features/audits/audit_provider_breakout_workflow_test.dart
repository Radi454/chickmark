import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
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

  AuditProvider providerFor(EggBreakoutType breakoutType) {
    final provider = AuditProvider();
    provider.initialize(
      AuditContext(
        auditType: 'Hatch Analysis & Egg Breakouts',
        customerId: 'customer-1',
        flockId: 'flock-1',
        flockAgeWeeks: 42,
        date: '2026-04-27',
      ),
      notify: false,
    );
    provider.updateHatchField(0, 'ebBreakoutType', breakoutType.storageValue);
    return provider;
  }

  test('fresh and candled breakouts do not require hatchability fields', () {
    for (final type in [
      EggBreakoutType.freshEggBreakout,
      EggBreakoutType.candledEggBreakout,
    ]) {
      final provider = providerFor(type);

      expect(provider.validateHatchBudget(0), isNull);
    }
  });

  test(
    'residue keeps hatchability validation but ignores breakout sample totals',
    () {
      final provider = providerFor(EggBreakoutType.residueHatchDay);
      provider.updateHatchField(0, 'haTotalEggsSet', 100);
      provider.updateHatchField(0, 'haHatched', 80);
      provider.updateHatchField(0, 'haCulled', 10);
      provider.updateHatchField(0, 'haDead', 10);
      provider.updateHatchField(
        0,
        'ebTrayBreakoutJson',
        jsonEncode([
          EggBreakoutSampleEntry.pool(
            id: 'pool-1',
            label: 'Pool 1',
            numberOfTrays: 3,
            traySize: 150,
            counts: {'infertile': 12},
          ).toJson(),
        ]),
      );

      expect(provider.validateHatchBudget(0), isNull);

      provider.updateHatchField(0, 'haDead', 9);

      expect(provider.validateHatchBudget(0), contains('Unallocated eggs'));
    },
  );

  test('save and reload preserves tray and pool breakout samples and type', () {
    final samples = [
      EggBreakoutSampleEntry.tray(
        id: 'tray-1',
        label: 'Tray 1',
        position: 'top',
        traySize: 150,
        breakoutType: EggBreakoutType.freshEggBreakout,
        counts: {'infertile': 5},
      ),
      EggBreakoutSampleEntry.pool(
        id: 'pool-1',
        label: 'Pool 1',
        numberOfTrays: 2,
        traySize: 150,
        breakoutType: EggBreakoutType.candledEggBreakout,
        counts: {'blackEye': 6},
      ),
    ];
    final provider = providerFor(EggBreakoutType.candledEggBreakout);
    provider.updateHatchField(
      0,
      'ebTrayBreakoutJson',
      jsonEncode(samples.map((sample) => sample.toJson()).toList()),
    );

    final reloaded = EggBreakoutSampleEntry.decodeList(
      provider.activeDraft.ebTrayBreakoutJson,
    );

    expect(provider.activeDraft.ebBreakoutType, 'candledEggBreakout');
    expect(reloaded.first.sampleMode, EggBreakoutSampleMode.tray);
    expect(reloaded.first.totalSample, 150);
    expect(reloaded.last.sampleMode, EggBreakoutSampleMode.pool);
    expect(reloaded.last.totalSample, 300);
    expect(reloaded.last.counts['blackEye'], 6);
  });
}
