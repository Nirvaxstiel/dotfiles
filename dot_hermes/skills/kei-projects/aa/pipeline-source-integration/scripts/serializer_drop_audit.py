"""Silent-drop audit for the RegistryModel typed serializer.

Run from the repo root AFTER any change to data/_domain/_entities.py
(RegistryModel / RegistryModelMeta) or the registry build:

    python -m data._build_registry
    python skills/kei-projects/aa/pipeline-source-integration/scripts/serializer_drop_audit.py

Why: once RegistryModel.from_flat is the registry writer, RegistryModelMeta.to_dict()
emits ONLY declared fields. Any meta key the pipeline sets but RegistryModelMeta lacks
is silently dropped for ALL models (the context_window regression: 104->0, no error).
This script catches that before it ships.

Exit code 1 + printed dropped keys  => fix RegistryModelMeta (add field + capture in
from_flat). Exit code 0 + "OK" => no silent drops.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve()
# Walk up to the repo root that contains data/model_registry.json
while not (REPO / "data" / "model_registry.json").exists():
    if REPO.parent == REPO:
        break
    REPO = REPO.parent

sys.path.insert(0, str(REPO / "data"))

from _domain._entities import RegistryModel  # noqa: E402


def main() -> int:
    reg_path = REPO / "data" / "model_registry.json"
    if not reg_path.exists():
        print(f"ERROR: {reg_path} not found — run `python -m data._build_registry` first")
        return 2
    reg = json.loads(reg_path.read_text(encoding="utf-8"))
    models = reg.get("models", [])
    if not models:
        print("ERROR: no models in registry")
        return 2

    dropped: set[str] = set()
    for m in models:
        src_meta = m.get("meta") or {}
        try:
            out_meta = RegistryModel.from_flat(m).to_dict().get("meta") or {}
        except Exception as e:  # surface real construction errors loudly
            print(f"CONSTRUCT FAIL for {m.get('id')}: {e}")
            return 1
        for k in src_meta:
            if k not in out_meta:
                dropped.add(k)

    if dropped:
        print(f"FAIL: {len(dropped)} meta key(s) silently dropped by RegistryModel:")
        for k in sorted(dropped):
            print(f"  - {k}")
        print("FIX: add each key to RegistryModelMeta AND capture it in from_flat.")
        return 1

    print(f"OK: round-trip preserved all meta keys across {len(models)} models.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
