#!/usr/bin/env python3
"""Give each Pages app entrypoint a content-addressed filename."""

from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path, PurePosixPath


def sha256(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def _replace_js_property(source: str, name: str, value: str) -> tuple[str, int]:
    pattern = re.compile(
        rf'(?P<key>["\']?{re.escape(name)}["\']?\s*:\s*)'
        rf'(?P<quote>["\'])[^"\']*(?P=quote)'
    )
    return pattern.subn(lambda match: f'{match.group("key")}{match.group("quote")}{value}{match.group("quote")}', source)


def _asset_path(build_dir: Path, name: str) -> Path | None:
    relative = PurePosixPath(name)
    if relative.is_absolute() or ".." in relative.parts:
        return None
    path = (build_dir / Path(*relative.parts)).resolve()
    try:
        path.relative_to(build_dir.resolve())
    except ValueError:
        return None
    return path if path.is_file() else None


def _update_resources(worker: str, entries: dict[str, str]) -> tuple[str, bool]:
    match = re.search(
        r"(?P<prefix>\bconst\s+RESOURCES\s*=\s*\{)(?P<body>.*?)(?P<suffix>\}\s*;)",
        worker,
        flags=re.DOTALL,
    )
    if match is None:
        return worker, False

    body = match.group("body")
    additions: list[str] = []
    for name, digest in entries.items():
        property_pattern = re.compile(
            rf'(?P<indent>^[ \t]*)(?P<keyquote>["\']){re.escape(name)}'
            rf'(?P=keyquote)(?P<sep>\s*:\s*)(?P<valuequote>["\'])'
            rf'[^"\']*(?P=valuequote)',
            flags=re.MULTILINE,
        )
        prop = property_pattern.search(body)
        if prop is not None:
            body = property_pattern.sub(
                lambda item: (
                    f'{item.group("indent")}{item.group("keyquote")}{name}'
                    f'{item.group("keyquote")}{item.group("sep")}'
                    f'{item.group("valuequote")}{digest}{item.group("valuequote")}'
                ),
                body,
                count=1,
            )
        else:
            additions.append(f'  "{name}": "{digest}",')

    if additions:
        content = body.rstrip()
        if content and not content.endswith(","):
            content += ","
        body = f"{content}\n{chr(10).join(additions)}\n"

    return (
        worker[: match.start()]
        + match.group("prefix")
        + body
        + match.group("suffix")
        + worker[match.end() :],
        True,
    )


def _update_core(worker: str, asset_names: list[str]) -> str:
    match = re.search(
        r"(?P<prefix>\bconst\s+CORE\s*=\s*\[)(?P<body>.*?)(?P<suffix>\]\s*;)",
        worker,
        flags=re.DOTALL,
    )
    if match is None:
        return worker

    body = match.group("body")
    existing = set(re.findall(r'["\']([^"\']+)["\']', body))
    additions = [name for name in asset_names if name not in existing]
    if additions:
        content = body.rstrip()
        if content and not content.endswith(","):
            content += ","
        formatted_additions = [f"  {json.dumps(name)}," for name in additions]
        body = content + "\n" + "\n".join(formatted_additions) + "\n"
    return (
        worker[: match.start()]
        + match.group("prefix")
        + body
        + match.group("suffix")
        + worker[match.end() :]
    )


def fingerprint(build_dir: Path) -> tuple[str, str]:
    build_dir = build_dir.resolve()
    index_path = build_dir / "index.html"
    bootstrap_path = build_dir / "flutter_bootstrap.js"
    main_path = build_dir / "main.dart.js"
    service_worker_path = build_dir / "flutter_service_worker.js"
    for required in (index_path, bootstrap_path, main_path):
        if not required.is_file():
            raise FileNotFoundError(f"Flutter web output is missing {required}")

    index_original = index_path.read_text()
    bootstrap_original = bootstrap_path.read_text()
    main_bytes = main_path.read_bytes()

    main_name = f"main.{sha256(main_bytes)}.dart.js"
    (build_dir / main_name).write_bytes(main_bytes)

    worker_original = service_worker_path.read_text() if service_worker_path.is_file() else ""
    resource_match = re.search(
        r"\bconst\s+RESOURCES\s*=\s*\{(?P<body>.*?)\}\s*;",
        worker_original,
        flags=re.DOTALL,
    )
    has_resource_manifest = resource_match is not None
    if has_resource_manifest:
        # This stable build token changes when the app or a Flutter-managed
        # asset changes, making the worker URL update without relying on ?v.
        resource_pairs = sorted(
            re.findall(
                r'["\']([^"\']+)["\']\s*:\s*["\']([^"\']+)["\']',
                resource_match.group("body"),
            )
        )
        resource_pairs = [
            pair
            for pair in resource_pairs
            if pair[0] not in {"index.html", "flutter_bootstrap.js"}
            and not re.fullmatch(r"main\.[a-f0-9]+\.dart\.js", pair[0])
            and not re.fullmatch(r"flutter_bootstrap\.[a-f0-9]+\.js", pair[0])
        ]
        seed = main_bytes + bootstrap_original.encode() + repr(resource_pairs).encode()
        worker_version = sha256(seed)[:16]
    else:
        worker_version = None

    bootstrap_updated, main_replacements = _replace_js_property(
        bootstrap_original, "mainJsPath", main_name
    )
    if main_replacements == 0:
        raise ValueError("Flutter bootstrap has no mainJsPath setting to fingerprint")
    if worker_version is not None:
        bootstrap_updated, _ = _replace_js_property(
            bootstrap_updated, "serviceWorkerVersion", worker_version
        )

    bootstrap_bytes = bootstrap_updated.encode()
    bootstrap_name = f"flutter_bootstrap.{sha256(bootstrap_bytes)}.js"
    (build_dir / bootstrap_name).write_bytes(bootstrap_bytes)

    index_updated, script_replacements = re.subn(
        r'(?P<prefix><script\b[^>]*\bsrc=["\'])'
        r'flutter_bootstrap(?:\.[a-f0-9]+)?\.js'
        r'(?P<suffix>["\'])',
        lambda match: f'{match.group("prefix")}{bootstrap_name}{match.group("suffix")}',
        index_original,
    )
    if script_replacements != 1:
        raise ValueError(
            "Expected one flutter_bootstrap.js script reference in index.html"
        )
    index_path.write_text(index_updated)

    if has_resource_manifest:
        worker_updated = worker_original
        # Keep legacy filenames available and update their hashes if the
        # HTML or bootstrap was rewritten. New names are added alongside them.
        resource_hashes: dict[str, str] = {}
        for name in ("index.html", "flutter_bootstrap.js", "main.dart.js", main_name, bootstrap_name):
            path = _asset_path(build_dir, name)
            if path is not None:
                resource_hashes[name] = sha256(path.read_bytes())
        worker_updated, resources_changed = _update_resources(
            worker_updated, resource_hashes
        )
        if resources_changed:
            worker_updated = _update_core(worker_updated, [main_name, bootstrap_name])
            service_worker_path.write_text(worker_updated)

    return bootstrap_name, main_name


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"Usage: {Path(argv[0]).name} BUILD_WEB_DIR", file=sys.stderr)
        return 2
    bootstrap_name, main_name = fingerprint(Path(argv[1]))
    print(f"Fingerprinted Pages entrypoints: {bootstrap_name}, {main_name}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except (FileNotFoundError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
