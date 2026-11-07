#!/usr/bin/env python3
"""Fetch Dirac.run cache-hit-rates table -> data/sources/dirac/cache_hit_rates.json.

Dirac.run renders the full table as a real HTML <table> (NOT markdown). The
"Small Model Grift" subset is a smaller <table> that also contains "cache"; the
398-row table sits AFTER the `#the-full-table` anchor. Fetch via urllib (curl to
this host trips the agent command blocklist; urllib.request is fine).

Output shape is EXACTLY what data/sources/dirac/_build.py::get_dirac_models
expects: list of {model, provider, eff_input_price, eff_output_price,
cache_hit_rate}. Do NOT rename fields.
"""
import json
import os
import re
import sys
import html
import urllib.request

URL = "https://dirac.run/posts/cache-hit-rates-agents"

# Default repo path; override via argv[1] or DIRAC_REPO env.
Path = r"~/.obsidian/Vault/KeiUniverse/IRL/Reference/"
DEFAULT_REPO = os.path.expanduser(Path + r"LLM Provider Pricing Analysis")


def _num(s: str):
    s = s.replace("$", "").replace(",", "").replace("%", "").strip()
    try:
        return float(s)
    except ValueError:
        return None


def fetch() -> list[dict]:
    req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0"})
    raw = urllib.request.urlopen(req, timeout=30).read().decode("utf-8", "replace")

    anchor = raw.find('id="the-full-table"')
    if anchor < 0:
        anchor = raw.find("the-full-table")
    after = raw[anchor:] if anchor >= 0 else raw

    tables = list(re.finditer(r"<table[^>]*>(.*?)</table>", after, re.S))
    best, best_n = [], 0
    for mt in tables:
        t = mt.group(1)
        rows = []
        for tr in re.findall(r"<tr[^>]*>(.*?)</tr>", t, re.S):
            cells = re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, re.S)
            cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip() for c in cells]
            if len(cells) != 5:
                continue
            model, provider, inp, out, rate = cells
            if model.lower() in ("model name", "model") or set(model) <= set("-: "):
                continue
            rows.append(
                {
                    "model": model,
                    "provider": provider,
                    "eff_input_price": _num(inp),
                    "eff_output_price": _num(out),
                    "cache_hit_rate": _num(rate),
                }
            )
        if len(rows) > best_n:
            best_n, best = len(rows), rows
    return best


def main() -> int:
    repo = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("DIRAC_REPO", DEFAULT_REPO)
    out_path = os.path.join(repo, "data", "sources", "dirac", "cache_hit_rates.json")
    rows = fetch()
    if not rows:
        print("ERROR: parsed 0 rows — anchor/table not found", file=sys.stderr)
        return 1
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    json.dump(rows, open(out_path, "w"), indent=2)
    print(f"wrote {len(rows)} rows -> {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
