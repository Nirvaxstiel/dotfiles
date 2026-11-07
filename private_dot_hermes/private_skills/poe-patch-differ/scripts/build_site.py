#!/usr/bin/env python3
"""Build the patch-differ SITE: one index.html SPA + a leagues/index.json manifest.

The site is a single-page app: index.html holds the shell (league selector + collapsible
contents panel) and renders any league's sections client-side by fetching its JSON. No per-league
HTML is generated — each league stays a single durable JSON file. Pure pipeline: scan -> manifest
-> render shell.

Usage:
    python build_site.py [--root .] [--out index.html]

Emits:
    <root>/leagues/index.json     manifest: [{version, league, json(rel)}, ...]
    <root>/index.html             SPA shell (fetches manifest + league json at runtime)

Relative links only — opens under file:// (where fetch of local files works in most browsers when
served) and on GitHub/Forgejo Pages.
"""
import argparse
import glob
import json
import os
import sys

TEMPLATE_REL = os.path.join("..", "templates", "patch.template.html")


def here(p):
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), p)


def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def scan_leagues(root):
    out = []
    pat = os.path.join(root, "leagues", "*", "*.json")
    for path in sorted(glob.glob(pat)):
        # skip a manifest if present
        if os.path.basename(path).lower() == "index.json":
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError) as e:
            print(f"WARN: skipping {path}: {e}", file=sys.stderr)
            continue
        meta = data.get("meta") or {}
        ver = meta.get("version") or os.path.basename(os.path.dirname(path))
        league = meta.get("league") or "(untitled)"
        rel = os.path.relpath(path, root).replace(os.sep, "/")
        out.append({"version": ver, "league": league, "json": rel})
    out.sort(key=lambda x: x["version"], reverse=True)
    return out


def render(template_path, manifest, title):
    with open(template_path, "r", encoding="utf-8") as f:
        tpl = f.read()
    tpl = tpl.replace("__TITLE__", title)
    tpl = tpl.replace("__MANIFEST__", json.dumps(manifest, ensure_ascii=False))
    return tpl


def main():
    ap = argparse.ArgumentParser(description="Build the patch-differ SPA site.")
    ap.add_argument("--root", default=".", help="repo root containing leagues/ (default: cwd)")
    ap.add_argument("--out", default="index.html", help="output path (default: index.html in root)")
    args = ap.parse_args()

    root = os.path.abspath(args.root)
    leagues = scan_leagues(root)
    if not leagues:
        die(f"no league json found under {os.path.join(root, 'leagues')}")

    # write manifest next to leagues/
    manifest_path = os.path.join(root, "leagues", "index.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(leagues, f, ensure_ascii=False, indent=2)

    title = f"Patch Differ — {leagues[0]['version']} {leagues[0]['league']}"
    html = render(here(TEMPLATE_REL), leagues, title)

    out_path = os.path.join(root, args.out)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"OK: {out_path}  ({len(leagues)} leagues; manifest -> {os.path.relpath(manifest_path, root)})")


if __name__ == "__main__":
    main()
