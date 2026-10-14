import json, os
from pathlib import Path

from ..._canonical import x_name_to_canonical  # adjust dot-depth to package location


def get_x_models(base: Path) -> dict[str, dict]:
    """Merge vision/transcribed source into dict of canonical_id -> model record.

    Returns records shaped as {benchmarks: {x: {...}}, meta: {...}}. Fill nulls only.
    """
    path = os.path.join(base, "data", "sources", "x", "x_models.json")
    if not os.path.exists(path):
        return {}

    with open(path) as f:
        raw = json.load(f)

    out: dict[str, dict] = {}
    for display_name, rec in raw.items():
        if display_name == "_meta":
            continue
        cid = x_name_to_canonical(display_name)
        if not cid:
            continue
        b = out.setdefault(cid, {}).setdefault("benchmarks", {}).setdefault("x", {})
        for k in ("metric_a", "metric_b"):  # list the actual scalar keys
            if rec.get(k) is not None:
                b.setdefault(k, rec[k])
        meta = out[cid].setdefault("meta", {})
        if rec.get("extra_b") is not None:
            meta.setdefault("extra_b", rec["extra_b"])

    return out
