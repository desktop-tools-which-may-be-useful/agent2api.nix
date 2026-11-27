#!/usr/bin/env python3
"""Regenerate pkgs/plugins.nix from the upstream Agent2plugin index.

The index (index.json) lists every provider-plugin pack; each entry points at
a manifest (plugins/<id>.json) carrying the current version and the release
repo/tag/asset templates. Release zips are fetched from
Agent2Builder/agent2api-providers-releases. For each pack we record:

  hash      SRI sha256 of the release zip (fetchurl's fixed-output hash)
  zipSha256 hex sha256 of the same zip, recorded in the gateway's plugins.json

Only packs already listed in pkgs/plugins.nix are refreshed by default;
`--add-new` also appends packs newly appearing upstream. Version comparison
uses the manifest as the source of truth (index.json has no versions).

Usage:
  nix run .#update-plugins            # refresh hashes/versions in place
  nix run .#update-plugins -- --check # exit 1 if anything would change
"""

import argparse
import concurrent.futures
import hashlib
import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

INDEX_URL = "https://raw.githubusercontent.com/Agent2plugin/Agent2plugin/main/index.json"
MANIFEST_URL = "https://raw.githubusercontent.com/Agent2plugin/Agent2plugin/main/{manifest}"
TARGET_NATIVE = "x86_64-unknown-linux-gnu"
TARGET_WASM = "wasm32-unknown-unknown"

# Repo root: the script may run from a store copy (nix run), so locate the
# checkout via git instead of __file__.
REPO_ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
)
PLUGINS_NIX = REPO_ROOT / "pkgs" / "plugins.nix"


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "agent2api-nix-update"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return resp.read()


def fetch_json(url: str):
    return json.loads(fetch(url))


def nix_hash(digest: bytes) -> str:
    """SRI sha256 of the zip (fetchurl's output hash is the file itself)."""
    import base64

    return "sha256-" + base64.b64encode(digest).decode()


def existing_specs() -> dict:
    """Parse the current plugins.nix entries (id -> {version, ...})."""
    text = PLUGINS_NIX.read_text()
    specs = {}
    for block in re.finditer(r"\{([^}]*)\}", text, re.S):
        body = block.group(1)

        def field(name):
            m = re.search(rf'{name}\s*=\s*"([^"]*)"', body)
            return m.group(1) if m else None

        pid = field("id")
        if pid:
            specs[pid] = {
                "version": field("version"),
                "native": "native = true" in body,
                "url": field("url"),
                "hash": field("hash"),
                "zipSha256": field("zipSha256"),
            }
    return specs


def resolve(entry: dict) -> dict:
    manifest = fetch_json(MANIFEST_URL.format(manifest=entry["manifest"]))
    version = manifest["version"]
    rel = manifest["release"]
    platforms = manifest.get("platforms", [])
    native = TARGET_NATIVE in platforms
    target = TARGET_NATIVE if native else TARGET_WASM
    tag = rel["tag"].replace("{version}", version)
    asset = (
        rel["asset"]
        .replace("{id}", manifest["id"])
        .replace("{version}", version)
        .replace("{target}", target)
    )
    url = f"https://github.com/{rel['repo']}/releases/download/{tag}/{asset}"
    return {
        "id": manifest["id"],
        "version": version,
        "native": native,
        "url": url,
    }


def hash_spec(spec: dict) -> dict:
    data = fetch(spec["url"])
    digest = hashlib.sha256(data).digest()
    return spec | {
        "hash": nix_hash(digest),
        "zipSha256": digest.hex(),
    }


def render(specs: list) -> str:
    lines = [
        "# Generated from https://github.com/Agent2plugin/Agent2plugin index.json.",
        "# Each entry is one provider-plugin pack from Agent2Builder/agent2api-providers-releases.",
        "# Regenerate with: nix run .#update-plugins",
        "[",
    ]
    for s in specs:
        lines += [
            "  {",
            f'    id = "{s["id"]}";',
            f'    version = "{s["version"]}";',
            f'    native = {"true" if s["native"] else "false"};',
            f'    url = "{s["url"]}";',
            f'    hash = "{s["hash"]}";',
            f'    zipSha256 = "{s["zipSha256"]}";',
            "  }",
        ]
    lines += ["]", ""]
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="exit 1 if updates are available")
    ap.add_argument("--add-new", action="store_true", help="also add packs new upstream")
    args = ap.parse_args()

    old = existing_specs()
    index = fetch_json(INDEX_URL)
    entries = {e["id"]: e for e in index["plugins"]}

    wanted = list(old)
    if args.add_new:
        wanted += [i for i in entries if i not in old]

    missing = [i for i in wanted if i not in entries]
    if missing:
        print(f"warning: not in upstream index (kept as-is): {', '.join(missing)}", file=sys.stderr)

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        resolved = dict(
            zip(
                [i for i in wanted if i in entries],
                pool.map(resolve, [entries[i] for i in wanted if i in entries]),
            )
        )

    # Only re-download packs whose url changed; keep known hashes otherwise.
    todo = [
        resolved[i]
        for i in resolved
        if i not in old or old[i]["url"] != resolved[i]["url"]
    ]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        for done in pool.map(hash_spec, todo):
            resolved[done["id"]] = done
    for i in resolved:
        if "hash" not in resolved[i]:
            resolved[i] = old[i] | {"id": i}

    # Preserve current file order; append new packs at the end.
    ordered = [resolved.get(i, old[i] | {"id": i}) for i in old]
    ordered += [resolved[i] for i in wanted if i not in old and i in resolved]

    changed = [
        s["id"]
        for s in ordered
        if s["id"] not in old
        or any(old[s["id"]].get(k) != s.get(k) for k in ("version", "url", "hash", "zipSha256"))
    ]
    if not changed:
        print("plugins.nix is up to date.")
        return 0

    print("updates:", ", ".join(changed))
    if args.check:
        return 1
    PLUGINS_NIX.write_text(render(ordered))
    print(f"wrote {PLUGINS_NIX.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())