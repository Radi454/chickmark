import 'dart:convert';
import 'dart:typed_data';

const _photoDataUriPrefix = 'data:image/jpeg;base64,';

String encodePhotoDataUri(Uint8List bytes) =>
    '$_photoDataUriPrefix${base64Encode(bytes)}';

Uint8List? parseDurablePhotoDataUri(String? value) {
  if (value == null || !value.startsWith(_photoDataUriPrefix)) return null;
  try {
    final bytes = base64Decode(value.substring(_photoDataUriPrefix.length));
    return bytes.isEmpty ? null : Uint8List.fromList(bytes);
  } on FormatException {
    return null;
  }
}

bool isDurablePhotoDataUri(String? value) =>
    parseDurablePhotoDataUri(value) != null;

Map<String, dynamic> stripInlinePhotoDataUris(Map<String, dynamic> row) =>
    row.map(
      (key, value) => MapEntry(
        key,
        _stripInlinePhotoDataUris(value, photoField: _isPhotoField(key)),
      ),
    );

dynamic _stripInlinePhotoDataUris(dynamic value, {bool photoField = false}) {
  if (value is String) {
    if (photoField && value.startsWith('data:image/')) return null;
    if (value.contains('data:image/')) {
      try {
        final decoded = jsonDecode(value);
        final stripped = _stripInlinePhotoDataUris(
          decoded,
          photoField: photoField,
        );
        return jsonEncode(stripped);
      } on FormatException {
        return value;
      }
    }
    return value;
  }
  if (value is List) {
    return value
        .map((item) => _stripInlinePhotoDataUris(item, photoField: photoField))
        .toList();
  }
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(
        key,
        _stripInlinePhotoDataUris(
          nested,
          photoField: photoField || _isPhotoField(key.toString()),
        ),
      ),
    );
  }
  return value;
}

bool _isPhotoField(String key) {
  final normalized = key.toLowerCase();
  return normalized.contains('photo') ||
      normalized.contains('image') ||
      normalized.endsWith('path');
}
