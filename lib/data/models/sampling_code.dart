import 'sampling_scope.dart';

String? normalizeThreeLetterCode(String raw) {
  final normalized = raw.trim().toUpperCase();
  return RegExp(r'^[A-Z]{3}$').hasMatch(normalized) ? normalized : null;
}

class SamplingCode {
  const SamplingCode._();

  static String? build({
    required String? customerCode,
    required String? hatcheryCode,
    required String? flockCode,
    required String? breedAbbreviation,
    required SamplingScopePath path,
  }) {
    final customer = _requiredThreeLetter(customerCode);
    final hatchery = _requiredThreeLetter(hatcheryCode);
    final flock = _requiredThreeLetter(flockCode);
    final breed = breedAbbreviation?.trim().toUpperCase();
    if (customer == null ||
        hatchery == null ||
        flock == null ||
        breed == null ||
        breed.isEmpty ||
        path.sampleNumber < 1 ||
        path.unknownLevels.isNotEmpty) {
      return null;
    }

    final segments = <String>[customer, hatchery, flock, breed];
    for (final level in const <SamplingScopeLevel>[
      SamplingScopeLevel.house,
      SamplingScopeLevel.setter,
      SamplingScopeLevel.hatcher,
      SamplingScopeLevel.trolley,
      SamplingScopeLevel.tray,
    ]) {
      final value = path.identityFor(level);
      if (value == null || value.trim().isEmpty) continue;
      segments.add(samplingScopeSegment(level, value));
    }
    segments.add('SA${path.sampleNumber}');
    return segments.join('-');
  }

  static String? _requiredThreeLetter(String? raw) =>
      raw == null ? null : normalizeThreeLetterCode(raw);
}

bool sameScopeIdentity(SamplingNode a, SamplingNode b) {
  if (a.sessionId != b.sessionId ||
      a.panelKey != b.panelKey ||
      a.parentId != b.parentId ||
      a.level != b.level) {
    return false;
  }
  return _canonicalIdentity(a) == _canonicalIdentity(b);
}

String _canonicalIdentity(SamplingNode node) {
  final identity = node.identity.isEmpty
      ? {'code': node.identityKey?.trim().toUpperCase() ?? ''}
      : node.identity;
  return canonicalScopeIdentity(identity, node.level);
}
