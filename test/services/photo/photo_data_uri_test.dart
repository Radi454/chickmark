import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/photo/photo_data_uri.dart';

void main() {
  test('round trips durable compressed image bytes', () {
    final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xd9]);
    final encoded = encodePhotoDataUri(bytes);

    expect(isDurablePhotoDataUri(encoded), isTrue);
    expect(parseDurablePhotoDataUri(encoded), bytes);
  });

  test('rejects empty, malformed, and non-JPEG image paths', () {
    expect(parseDurablePhotoDataUri(null), isNull);
    expect(parseDurablePhotoDataUri('data:image/jpeg;base64,'), isNull);
    expect(parseDurablePhotoDataUri('data:image/jpeg;base64,%%%'), isNull);
    expect(parseDurablePhotoDataUri('data:image/png;base64,AA=='), isNull);
  });

  test('strips inline image paths from nested panel payload values', () {
    const image = 'data:image/jpeg;base64,ZmFrZQ==';
    final row = <String, dynamic>{
      'id': 'row-1',
      'evidencePhoto': image,
      'cvTPhotosJson': '[{"path":"$image","note":"keep"}]',
      'samplesJson':
          '[{"estPhotoPath":"$image","operatorNote":"keep data:image/ text"}]',
      'notes':
          'Literal note mentioning data:image/jpeg;base64, but not a photo path',
      'readings': [
        {'photoPath': image, 'value': 42},
      ],
    };

    final stripped = stripInlinePhotoDataUris(row);

    expect(stripped['id'], 'row-1');
    expect(stripped['evidencePhoto'], isNull);
    expect(stripped['notes'], row['notes']);
    expect(stripped['cvTPhotosJson'], '[{"path":null,"note":"keep"}]');
    expect(
      stripped['samplesJson'],
      '[{"estPhotoPath":null,"operatorNote":"keep data:image/ text"}]',
    );
    expect(stripped['readings'], [
      {'photoPath': null, 'value': 42},
    ]);
    expect(stripped['evidencePhoto'], isNull);
    expect(stripped['cvTPhotosJson'], isNot(contains('data:image/')));
  });
}
