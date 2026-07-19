import 'dart:io';

Future<String?> loadLocalSupabaseEnv() async {
  final candidates = <String>[];
  final explicit = const String.fromEnvironment('SUPABASE_ENV_FILE').trim();

  void addCandidate(String path) {
    if (path.trim().isEmpty || candidates.contains(path)) return;
    candidates.add(path);
  }

  addCandidate(explicit);

  final executable = File(Platform.resolvedExecutable);
  final executableDir = executable.parent;
  final contentsDir = executableDir.parent;
  addCandidate('${contentsDir.path}/Resources/.env');

  for (final path in candidates) {
    try {
      final file = File(path);
      if (await file.exists()) {
        return file.readAsString();
      }
    } on FileSystemException {
      // Keep probing other local development locations.
    }
  }

  return null;
}
