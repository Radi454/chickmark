import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/est_grid_data.dart';
import 'package:hatchaudit/features/audits/models/est_guided_capture_state.dart';

void main() {
  group('EstGuidedCaptureState', () {
    test('auto scan is off by default', () {
      final state = EstGuidedCaptureState.initial();

      expect(state.isAutoScanning, isFalse);
      expect(state.isOcrProcessing, isFalse);
      expect(state.isAutoScanReview, isFalse);
    });

    test('initial starts at the first unconfirmed scan point', () {
      final state = EstGuidedCaptureState.initial(
        readings: {'front_top': 23.4},
        photos: {'front_top': '/tmp/front_top.jpg'},
      );

      expect(state.currentKey, 'front_middle');
    });

    test(
      'initial treats reading without photo as complete for auto capture',
      () {
        final state = EstGuidedCaptureState.initial(
          readings: {'front_top': 23.4},
          photos: const {},
        );

        expect(state.currentKey, 'front_middle');
      },
    );

    test('initial starts at front top when all readings are complete', () {
      final state = EstGuidedCaptureState.initial(
        readings: {for (final key in EstGridData.scanKeys) key: 23.4},
        photos: {for (final key in EstGridData.scanKeys) key: '/tmp/$key.jpg'},
      );

      expect(state.currentKey, 'front_top');
      expect(state.isAutoScanning, isFalse);
      expect(state.capturedImagePath, isNull);
      expect(state.ocrValue, isNull);
    });

    test('confirm saves current point and advances to next scan key', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg', ocrValue: 23.4)
          .confirm();

      expect(state.currentKey, 'front_middle');
      expect(state.readings['front_top'], 23.4);
      expect(state.photos['front_top'], '/tmp/front_top.jpg');
      expect(state.capturedImagePath, isNull);
      expect(state.ocrValue, isNull);
      expect(state.isAutoScanning, isFalse);
      expect(state.isOcrProcessing, isFalse);
      expect(state.isAutoScanReview, isFalse);
      expect(state.lastConfirmedKey, 'front_top');
    });

    test('skip advances without saving a reading or photo', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg', ocrValue: 23.4)
          .skip();

      expect(state.currentKey, 'front_middle');
      expect(state.readings, isEmpty);
      expect(state.photos, isEmpty);
    });

    test('retake clears captured image and value without saving', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg', ocrValue: 23.4)
          .retake();

      expect(state.currentKey, 'front_top');
      expect(state.capturedImagePath, isNull);
      expect(state.ocrValue, isNull);
      expect(state.readings, isEmpty);
      expect(state.photos, isEmpty);
    });

    test('auto scan start is idempotent and enables OCR attempts', () {
      final state = EstGuidedCaptureState.initial()
          .startAutoScan()
          .startAutoScan();

      expect(state.isAutoScanning, isTrue);
      expect(state.isOcrProcessing, isFalse);
      expect(state.canStartOcrAttempt, isTrue);
      expect(state.errorMessage, contains('Looking for reading'));
    });

    test('auto scan does not start on a confirmed point until retake', () {
      final filledReadings = {
        for (final key in EstGridData.scanKeys) key: 23.4,
      };
      final filledPhotos = {
        for (final key in EstGridData.scanKeys) key: '/tmp/$key.jpg',
      };

      final blocked = EstGuidedCaptureState.initial(
        readings: filledReadings,
        photos: filledPhotos,
      ).startAutoScan();

      expect(blocked.currentKey, 'front_top');
      expect(blocked.isAutoScanning, isFalse);
      expect(blocked.errorMessage, contains('already saved'));

      final retaken = blocked.retake().startAutoScan();
      expect(retaken.isAutoScanning, isTrue);
      expect(retaken.canStartOcrAttempt, isTrue);
    });

    test('OCR attempt in progress blocks another OCR attempt', () {
      final state = EstGuidedCaptureState.initial()
          .startAutoScan()
          .autoScanAttemptStarted()
          .autoScanAttemptStarted();

      expect(state.isAutoScanning, isTrue);
      expect(state.isOcrProcessing, isTrue);
      expect(state.canStartOcrAttempt, isFalse);
    });

    test('auto scan no-reading attempt keeps scanning without saving', () {
      final state = EstGuidedCaptureState.initial()
          .startAutoScan()
          .autoScanAttemptStarted()
          .autoScanAttemptResolved(
            photoPath: '/tmp/front_top.jpg',
            ocrValue: null,
          );

      expect(state.currentKey, 'front_top');
      expect(state.isAutoScanning, isTrue);
      expect(state.isOcrProcessing, isFalse);
      expect(state.capturedImagePath, isNull);
      expect(state.ocrValue, isNull);
      expect(state.readings, isEmpty);
      expect(state.photos, isEmpty);
    });

    test('auto scan detected reading enters review state', () {
      final state = EstGuidedCaptureState.initial()
          .startAutoScan()
          .autoScanAttemptStarted()
          .autoScanAttemptResolved(
            photoPath: '/tmp/front_top_tmp.jpg',
            ocrValue: 23.4,
          );

      expect(state.isAutoScanning, isFalse);
      expect(state.isOcrProcessing, isFalse);
      expect(state.isAutoScanReview, isTrue);
      expect(state.capturedImagePath, '/tmp/front_top_tmp.jpg');
      expect(state.ocrValue, 23.4);
      expect(state.errorMessage, contains('Confirm'));
    });

    test('wrong auto scan reading clears value and resumes scanning', () {
      final state = EstGuidedCaptureState.initial()
          .startAutoScan()
          .autoScanAttemptStarted()
          .autoScanAttemptResolved(
            photoPath: '/tmp/front_top_tmp.jpg',
            ocrValue: 23.4,
          )
          .rejectAutoScanReading();

      expect(state.currentKey, 'front_top');
      expect(state.isAutoScanning, isTrue);
      expect(state.capturedImagePath, isNull);
      expect(state.ocrValue, isNull);
      expect(state.readings, isEmpty);
      expect(state.photos, isEmpty);
    });

    test('right auto scan reading can save the persisted evidence path', () {
      final state = EstGuidedCaptureState.initial()
          .startAutoScan()
          .autoScanAttemptStarted()
          .autoScanAttemptResolved(
            photoPath: '/tmp/front_top_tmp.jpg',
            ocrValue: 23.4,
          )
          .confirm(photoPath: '/documents/front_top_saved.jpg');

      expect(state.currentKey, 'front_middle');
      expect(state.readings['front_top'], 23.4);
      expect(state.photos['front_top'], '/documents/front_top_saved.jpg');
      expect(state.isAutoScanReview, isFalse);
    });

    test(
      'capture without a detected reading refreshes camera without saving',
      () {
        final state = EstGuidedCaptureState.initial()
            .captureStarted()
            .captureResolved(photoPath: '/tmp/front_top.jpg', ocrValue: null);

        expect(state.currentKey, 'front_top');
        expect(state.capturedImagePath, isNull);
        expect(state.ocrValue, isNull);
        expect(state.isProcessing, isFalse);
        expect(state.readings, isEmpty);
        expect(state.photos, isEmpty);
        expect(state.errorMessage, contains('No reading found'));
      },
    );

    test('finish returns structured data for confirmed readings only', () {
      final state = EstGuidedCaptureState.initial()
          .captureResolved(photoPath: '/tmp/front_top.jpg', ocrValue: 23.4)
          .confirm()
          .captureResolved(photoPath: '/tmp/front_middle.jpg', ocrValue: 23.7)
          .retake()
          .skip();

      expect(state.structuredReadings, [
        {'position': 'Front', 'level': 'Top', 'value': 23.4},
      ]);
    });
  });
}
