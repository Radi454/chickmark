import hashlib
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HELPER = REPO_ROOT / "scripts" / "fingerprint_pages_assets.py"


def sha256(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


class FingerprintPagesAssetsTest(unittest.TestCase):
    def test_fingerprints_bootstrap_and_main_and_updates_offline_manifest(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            build = Path(temporary_directory)
            main = b"console.log('compiled ChickMark app');\n"
            bootstrap = (
                b'_flutter.buildConfig = '
                b'{"builds":[{"mainJsPath":"main.dart.js"}]};\n'
                b'_flutter.loader.load({serviceWorkerSettings:'
                b'{serviceWorkerVersion:"old-version"}});\n'
            )
            index = (
                b'<html><body><script src="flutter_bootstrap.js" '
                b'async></script></body></html>\n'
            )
            (build / "main.dart.js").write_bytes(main)
            (build / "flutter_bootstrap.js").write_bytes(bootstrap)
            (build / "index.html").write_bytes(index)
            app_data_worker = b"// keep the SQLite IndexedDB worker unchanged\n"
            (build / "sqflite_sw.js").write_bytes(app_data_worker)

            worker = (
                "const RESOURCES = {\n"
                f'  "index.html": "{sha256(index)}",\n'
                f'  "flutter_bootstrap.js": "{sha256(bootstrap)}",\n'
                f'  "main.dart.js": "{sha256(main)}",\n'
                "};\n"
                'const CORE = ["index.html", "flutter_bootstrap.js", '
                '"main.dart.js"];\n'
                "const CACHE_NAME = 'flutter-app-cache';\n"
            ).encode()
            (build / "flutter_service_worker.js").write_bytes(worker)

            result = subprocess.run(
                [sys.executable, str(HELPER), str(build)],
                capture_output=True,
                text=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            main_name = f"main.{sha256(main)}.dart.js"
            self.assertTrue((build / main_name).exists())
            self.assertEqual((build / "main.dart.js").read_bytes(), main)
            self.assertEqual((build / "flutter_bootstrap.js").read_bytes(), bootstrap)
            self.assertEqual((build / "sqflite_sw.js").read_bytes(), app_data_worker)

            index_after = (build / "index.html").read_text()
            bootstrap_match = re.search(
                r'<script src="(flutter_bootstrap\.[a-f0-9]+\.js)"',
                index_after,
            )
            self.assertIsNotNone(bootstrap_match)
            bootstrap_name = bootstrap_match.group(1)
            bootstrap_after = (build / bootstrap_name).read_text()
            self.assertIn(f'"mainJsPath":"{main_name}"', bootstrap_after)
            self.assertNotIn('serviceWorkerVersion:"old-version"', bootstrap_after)

            service_worker = (build / "flutter_service_worker.js").read_text()
            for asset_name in (main_name, bootstrap_name):
                self.assertIn(f'"{asset_name}"', service_worker)
                asset_hash = sha256((build / asset_name).read_bytes())
                self.assertRegex(
                    service_worker,
                    rf'"{re.escape(asset_name)}"\s*:\s*"{asset_hash}"',
                )
                self.assertIn(f'"{asset_name}"', service_worker.split("const CORE =", 1)[1])
            for legacy_name in ("main.dart.js", "flutter_bootstrap.js"):
                self.assertIn(f'"{legacy_name}"', service_worker)
            self.assertIn("const CACHE_NAME = 'flutter-app-cache';", service_worker)

            rerun = subprocess.run(
                [sys.executable, str(HELPER), str(build)],
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(rerun.returncode, 0, rerun.stderr)
            self.assertEqual((build / "index.html").read_text(), index_after)
            self.assertEqual((build / "flutter_service_worker.js").read_text(), service_worker)


if __name__ == "__main__":
    unittest.main()
