import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/govee/govee_service.dart';

void main() {
  group('GoveeService history sync helpers', () {
    test('builds 0x3301 history request payloads with checksum', () {
      expect(
        GoveeService.buildGoveeHistoryRequestForTesting(
          startMinutesBack: 21,
          endMinutesBack: 2,
        ),
        const [
          0x33,
          0x01,
          0x00,
          0x15,
          0x00,
          0x02,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x25,
        ],
      );

      expect(
        GoveeService.buildGoveeHistoryRequestForTesting(
          startMinutesBack: 28800,
          endMinutesBack: 1,
        ),
        const [
          0x33,
          0x01,
          0x70,
          0x80,
          0x00,
          0x01,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0xc3,
        ],
      );
    });

    test('parses history data packets into minute timestamps', () {
      final baseMinute = DateTime.parse('2026-05-02T10:30:00');
      final readings =
          GoveeService.parseGoveeHistoryDataPacketForTesting(const [
            0x00,
            0x15,
            0x03,
            0x71,
            0xe7,
            0x03,
            0x75,
            0xcf,
            0x03,
            0x71,
            0xe7,
            0x03,
            0x75,
            0xcf,
            0x03,
            0x71,
            0xe6,
            0x03,
            0x75,
            0xce,
          ], syncBaseMinute: baseMinute);

      expect(readings, hasLength(6));
      expect(readings.first.timestamp, DateTime.parse('2026-05-02T10:09:00'));
      expect(readings.last.timestamp, DateTime.parse('2026-05-02T10:14:00'));
      expect(readings.first.temperatureFahrenheit, closeTo(72.5, 0.1));
      expect(readings.first.humidity, closeTo(76.7, 0.1));
    });

    test('skips padded history records', () {
      final readings =
          GoveeService.parseGoveeHistoryDataPacketForTesting(const [
            0x00,
            0x03,
            0x03,
            0x75,
            0xcf,
            0x03,
            0x75,
            0xcf,
            0x03,
            0x75,
            0xce,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
            0xff,
          ], syncBaseMinute: DateTime.parse('2026-05-02T10:30:00'));

      expect(readings, hasLength(3));
    });

    test('parses history completion message count', () {
      expect(
        GoveeService.parseGoveeHistoryCompletionCountForTesting(const [
          0xee,
          0x01,
          0x00,
          0x04,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0xeb,
        ]),
        4,
      );
    });
  });

  group('GoveeService command response parser', () {
    test('ignores empty 0x0A command echoes', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xa0,
      ]);

      expect(reading, isNull);
    });

    test('parses temperature and humidity from 0x0A response', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0xfd,
        0x09,
        0x08,
        0x17,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x4b,
      ]);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, closeTo(78.026, 0.001));
      expect(reading.humidity, closeTo(58.96, 0.001));
    });

    test('parses live H5051 0x0A response from diagnostic log', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0xa3,
        0x09,
        0xd3,
        0x17,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xce,
      ]);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, closeTo(76.406, 0.001));
      expect(reading.humidity, closeTo(60.99, 0.001));
    });

    test(
      'parses battery-only 0x08 responses without changing temp or humidity',
      () {
        final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
          0xaa,
          0x08,
          0x63,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0x00,
          0xc1,
        ]);

        expect(reading, isNotNull);
        expect(reading!.batteryPercent, 99);
        expect(reading.temperatureFahrenheit, isNull);
        expect(reading.humidity, isNull);
      },
    );

    test('rejects invalid checksum for command responses', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0xfd,
        0x09,
        0x08,
        0x17,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0xff,
      ]);

      expect(reading, isNull);
    });

    test('rejects command responses shorter than 3 bytes', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
      ]);

      expect(reading, isNull);
    });

    test('rejects battery responses with value over 100', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x08,
        0x80,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x22,
      ]);

      expect(reading, isNull);
    });

    test('rejects responses with non-AA prefix', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xbb,
        0x0a,
        0xfd,
        0x09,
        0x08,
        0x17,
      ]);

      expect(reading, isNull);
    });

    test('rejects command responses with all-zero payload', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x01,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects invalid temperature range from command responses', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(const [
        0xaa,
        0x0a,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x2a,
      ]);

      expect(reading, isNull);
    });

    test('handles empty byte list gracefully', () {
      final reading = GoveeService.parseGoveeCommandResponseForTesting(
        const [],
      );

      expect(reading, isNull);
    });
  });

  group('H5051 advertisement parser (via testing wrapper)', () {
    test('parses valid H5051 9-byte advertisement', () {
      final reading = GoveeService.parseH5051ForTesting(const [
        0x00,
        0xa3,
        0x09,
        0xd3,
        0x17,
        0x63,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, isNotNull);
      expect(reading.humidity, isNotNull);
      expect(reading.batteryPercent, 99);
    });

    test('rejects H5051 advertisement with wrong length', () {
      final reading = GoveeService.parseH5051ForTesting(const [
        0x00,
        0xa3,
        0x09,
        0xd3,
        0x17,
        0x63,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects H5051 with invalid temperature', () {
      final reading = GoveeService.parseH5051ForTesting(const [
        0x00,
        0x00,
        0xff,
        0xff,
        0x7f,
        0x63,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects H5051 with invalid humidity', () {
      final reading = GoveeService.parseH5051ForTesting(const [
        0x00,
        0xa3,
        0x09,
        0x00,
        0xff,
        0x63,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });
  });

  group('H5051 short advertisement parser (via testing wrapper)', () {
    test('parses valid H5051 7-byte short advertisement', () {
      final reading = GoveeService.parseH5051ShortAdvertForTesting(const [
        0x10,
        0x05,
        0x86,
        0x1c,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, isNotNull);
      expect(reading.humidity, isNull);
    });

    test('rejects short advert with wrong prefix', () {
      final reading = GoveeService.parseH5051ShortAdvertForTesting(const [
        0x00,
        0x05,
        0x86,
        0x1c,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects short advert with wrong length', () {
      final reading = GoveeService.parseH5051ShortAdvertForTesting(const [
        0x10,
        0x05,
        0x86,
        0x1c,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });

    test('rejects short advert with out-of-range temp', () {
      final reading = GoveeService.parseH5051ShortAdvertForTesting(const [
        0x10,
        0x05,
        0x00,
        0x80,
        0x00,
        0x00,
        0x00,
      ]);

      expect(reading, isNull);
    });
  });

  group('Govee combined advertisement parser (via testing wrapper)', () {
    test('parses valid Govee combined 6-byte advert', () {
      final reading = GoveeService.parseGoveeCombinedAdvertForTesting(const [
        0x00,
        0x03,
        0x84,
        0x66,
        0x63,
        0x00,
      ], manufacturerId: 0xEC88);

      expect(reading, isNotNull);
      expect(reading!.temperatureFahrenheit, isNotNull);
      expect(reading.humidity, isNotNull);
      expect(reading.batteryPercent, 99);
    });

    test('rejects combined advert with invalid length', () {
      final reading = GoveeService.parseGoveeCombinedAdvertForTesting(const [
        0x00,
        0x4c,
        0xc8,
        0xaf,
        0x63,
      ], manufacturerId: 0xEC88);

      expect(reading, isNull);
    });

    test('rejects combined advert with non-Govee manufacturer id', () {
      final reading = GoveeService.parseGoveeCombinedAdvertForTesting(const [
        0x00,
        0x4c,
        0xc8,
        0xaf,
        0x63,
        0x00,
      ], manufacturerId: 0x0001);

      expect(reading, isNull);
    });
  });
}
