import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/supabase_config.dart';

void main() {
  group('SupabaseConfig credential resolution', () {
    test(
      'uses complete compile-time credentials without loading asset',
      () async {
        var loadedAsset = false;

        final result = await SupabaseConfig.resolveForTesting(
          compileTimeUrl: 'https://compile.example.test',
          compileTimeAnonKey: 'compile_key',
          loadLocalEnv: () async => '''
SUPABASE_URL=https://local.example.test
SUPABASE_ANON_KEY=local_key
''',
          loadAsset: () async {
            loadedAsset = true;
            return '''
{
  "SUPABASE_URL": "https://asset.example.test",
  "SUPABASE_ANON_KEY": "asset_key"
}
''';
          },
        );

        expect(result.url, 'https://compile.example.test');
        expect(result.anonKey, 'compile_key');
        expect(loadedAsset, isFalse);
      },
    );

    test(
      'uses asset credentials when compile-time credentials are empty',
      () async {
        final result = await SupabaseConfig.resolveForTesting(
          compileTimeUrl: '',
          compileTimeAnonKey: '',
          loadAsset: () async => '''
{
  "SUPABASE_URL": "https://asset.example.test",
  "SUPABASE_ANON_KEY": "asset_key"
}
''',
        );

        expect(result.url, 'https://asset.example.test');
        expect(result.anonKey, 'asset_key');
      },
    );

    test(
      'uses local dotenv credentials before bundled placeholder asset',
      () async {
        var loadedAsset = false;

        final result = await SupabaseConfig.resolveForTesting(
          compileTimeUrl: '',
          compileTimeAnonKey: '',
          loadLocalEnv: () async => '''
SUPABASE_URL=https://local.example.test
SUPABASE_ANON_KEY="local_key"
''',
          loadAsset: () async {
            loadedAsset = true;
            return '''
{
  "SUPABASE_URL": "YOUR_SUPABASE_URL",
  "SUPABASE_ANON_KEY": "YOUR_SUPABASE_ANON_KEY"
}
''';
          },
        );

        expect(result.url, 'https://local.example.test');
        expect(result.anonKey, 'local_key');
        expect(loadedAsset, isFalse);
      },
    );

    test(
      'falls through to asset when local dotenv is missing credentials',
      () async {
        final result = await SupabaseConfig.resolveForTesting(
          compileTimeUrl: '',
          compileTimeAnonKey: '',
          loadLocalEnv: () async => 'SUPABASE_URL=YOUR_SUPABASE_URL',
          loadAsset: () async => '''
{
  "SUPABASE_URL": "https://asset.example.test",
  "SUPABASE_ANON_KEY": "asset_key"
}
''',
        );

        expect(result.url, 'https://asset.example.test');
        expect(result.anonKey, 'asset_key');
      },
    );

    test(
      'does not mix partial compile-time credentials with asset credentials',
      () async {
        var loadedAsset = false;

        final result = await SupabaseConfig.resolveForTesting(
          compileTimeUrl: 'https://compile.example.test',
          compileTimeAnonKey: '',
          loadLocalEnv: () async => '''
SUPABASE_URL=https://local.example.test
SUPABASE_ANON_KEY=local_key
''',
          loadAsset: () async {
            loadedAsset = true;
            return '''
{
  "SUPABASE_URL": "https://asset.example.test",
  "SUPABASE_ANON_KEY": "asset_key"
}
''';
          },
        );

        expect(result.url, isEmpty);
        expect(result.anonKey, isEmpty);
        expect(loadedAsset, isFalse);
      },
    );

    test(
      'treats placeholder compile-time credentials as asset fallback',
      () async {
        final result = await SupabaseConfig.resolveForTesting(
          compileTimeUrl: 'YOUR_SUPABASE_URL',
          compileTimeAnonKey: 'YOUR_SUPABASE_ANON_KEY',
          loadAsset: () async => '''
{
  "SUPABASE_URL": "https://asset.example.test",
  "SUPABASE_ANON_KEY": "asset_key"
}
''',
        );

        expect(result.url, 'https://asset.example.test');
        expect(result.anonKey, 'asset_key');
      },
    );
  });
}
