import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/est_grid_data.dart';
import 'package:hatchaudit/features/audits/models/est_guided_capture_state.dart';

void main() {
  group('EstGuidedCaptureState', () {
    test('initial starts at the first point without a reading', () {
      final state = EstGuidedCaptureState.initial(
        readings: {'front_top': 23.4},
        photos: {'front_top': '/tmp/front_top.jpg'},
      );

      expect(state.currentKey, 'front_middle');
    });

    test('initial treats reading without photo as complete', () {
      final state = EstGuidedCaptureState.initial(
        readings: {'front_top': 23.4},
        photos: const {},
      );

      expect(state.currentKey, 'front_middle');
    });

    test('initial starts at front top when all readings are complete', () {
      final state = EstGuidedCaptureState.initial(
        readings: {for (final key in EstGridData.scanKeys) key: 23.4},
        photos: {for (final key in EstGridData.scanKeys) key: '/tmp/$key.jpg'},
      );

      expect(state.currentKey, 'front_top');
      expect(state.capturedImagePath, isNull);
      expect(state.pendingValue, isNull);
    });

    test('captureResolved stages a photo without a reading', () {
      final state = EstGuidedCaptureState.initial().captureResolved(
        photoPath: '/tmp/front_top.jpg',
      );

      expect(state.currentKey, 'front_top');
      expect(state.capturedImagePath, '/tmp/front_top.jpg');
      expect(state.pendingValue, isNull);
      expect(state.readings, isEmpty);
      expect(state.photos, isEmpty);
      expect(state.errorMessage, contains('Enter the reading'));
    });

    test('valueEdited stages a typed reading for confirmation', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg')
          .valueEdited(23.4);

      expect(state.pendingValue, 23.4);
      expect(state.capturedImagePath, '/tmp/front_top.jpg');
    });

    test('confirm saves current point and advances to next key', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg')
          .valueEdited(23.4)
          .confirm();

      expect(state.currentKey, 'front_middle');
      expect(state.readings['front_top'], 23.4);
      expect(state.photos['front_top'], '/tmp/front_top.jpg');
      expect(state.capturedImagePath, isNull);
      expect(state.pendingValue, isNull);
      expect(state.lastConfirmedKey, 'front_top');
    });

    test('confirm can save a manual reading without a photo', () {
      final state = EstGuidedCaptureState.initial().valueEdited(23.4).confirm();

      expect(state.currentKey, 'front_middle');
      expect(state.readings['front_top'], 23.4);
      expect(state.photos.containsKey('front_top'), isFalse);
      expect(state.lastConfirmedKey, 'front_top');
    });

    test('skip advances without saving a reading or photo', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg')
          .skip();

      expect(state.currentKey, 'front_middle');
      expect(state.readings, isEmpty);
      expect(state.photos, isEmpty);
    });

    test('retake clears staged photo and reading without saving', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg')
          .valueEdited(23.4)
          .retake();

      expect(state.currentKey, 'front_top');
      expect(state.capturedImagePath, isNull);
      expect(state.pendingValue, isNull);
      expect(state.readings, isEmpty);
      expect(state.photos, isEmpty);
    });

    test('finish returns structured data for confirmed readings only', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg')
          .valueEdited(23.4)
          .confirm()
          .captureResolved(photoPath: '/tmp/front_middle.jpg')
          .valueEdited(23.7)
          .retake()
          .skip();

      expect(state.structuredReadings, [
        {'position': 'Front', 'level': 'Top', 'value': 23.4},
      ]);
    });
  });
}
