#!/usr/bin/env python3
"""Strict, per-section coverage scan: verify a league JSON captures the forum patch notes.

WHY A STRICTER SCAN
-------------------
The first version of this script used word-overlap only. That let a *summary* row satisfy
the threshold while silently dropping a long list of numeric facts underneath it — e.g. a
single "Jewel top-tier mods: Cold 20% (was 15)..." row scored "covered" even though the
entire "Adds 30 to 42 Fire Damage to Spells (previously up to 23 to 32)" block was absent.
This script fixes that with three independent checks:

  1. PER-SECTION coverage. The forum is sliced into its real TOC sections (largest-offset
     occurrence of each title, gated on "Return to top"). A section at ~0% means the whole
     section was missed (a whole Breach section vanished once). We report a table.

  2. NUMERIC-TOKEN ENFORCEMENT. A change fact that carries >=2 distinct number tokens
     (ranges like "30 to 42", percentages, "(was 23 to 32)") is a HARD miss if NONE of
     those numbers appear anywhere in the JSON. Word overlap can't fake a missing number.
     This is what catches dropped numeric-value lists.

  3. TRUNCATION DETECTION. Any row whose `neu`/`old` contains "..." is a truncated summary
     that must be expanded. We list them so they get fixed instead of shipping.

The forum cache is produced by `web_extract` (full notes body saved to a .md even though the
tool preview is truncated). Image URLs are NOT in the cache (web_extract strips them) — this
only checks textual coverage.

USAGE
    python coverage_scan.py <forum_cache.md> <league.json> [--titles "T1|T2|..."]
    (titles optional; if omitted we auto-detect from the cache's Table of Contents block)

OUTPUT
    - truncation warnings (rows ending in "...")
    - per-section coverage table (facts / hard-misses / section %)
    - the hard-miss facts, for transcription (grep-confirm, then add)

FALSE POSITIVES: a fact already in the JSON under different wording may still be flagged by
the numeric check if its exact numbers differ (e.g. "543 to 1628" vs "543-1628"). Confirm
each miss against the JSON before adding. The per-section % is the real signal: a section
sitting at 100% with a couple of word-level flags is fine; a section at <80% needs a look.
"""
import re
import sys
import json
import argparse

# ---------------------------------------------------------------------------
# Signal words: anything that marks a before/after or a change. Broadened well
# beyond the original set after auditing the real 3.29/3.28 forums.
# ---------------------------------------------------------------------------
SIGNALS = re.compile(
    r"\b(now|previously|up to|increased|reduced|decreased|grants?|removed|added|added|"
    r"changed|no longer|instead|chance|renamed|reworked|rework|replaces?|converted|"
    r"split|doubled|halved|tripled|multiplier|more|less|from \d|per |duration|radius|"
    r"cooldown|cost|cap|limit|w|\bwas\b|\(was|deals|adds|scales|scaling|effectiveness|"
    r"qualit|implicit|modifier tier|tier rating|%)",
    re.I,
)

# words too common to count toward coverage
STOP = {
    "that", "have", "your", "with", "from", "this", "they", "been", "were", "will",
    "into", "more", "than", "also", "each", "when", "what", "which", "their", "there",
    "these", "those", "about", "after", "before", "area", "monsters", "grants",
    "increased", "reduced", "chance", "the", "and", "for", "are", "has", "had",
}

NUM = re.compile(r"\d+(?:\.\d+)?%?")  # 30, 42, 3.5, 25%


def norm(s):
    s = (s or "").lower()
    s = re.sub(r"[^a-z0-9% .]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def json_corpus(league_path):
    d = json.load(open(league_path, encoding="utf-8"))
    parts = []
    for sec in d.get("sections", []):
        for r in sec.get("rows", []):
            parts.append(r.get("k", ""))
            parts.append(r.get("neu", ""))
            parts.append(r.get("old", ""))
    text = " ".join(parts)
    return set(norm(text).split()), set(NUM.findall(text.lower()))


def detect_truncation(league_path):
    d = json.load(open(league_path, encoding="utf-8"))
    out = []
    for sec in d.get("sections", []):
        for i, r in enumerate(sec.get("rows", [])):
            for fld in ("neu", "old"):
                v = r.get(fld, "") or ""
                if "..." in v:
                    out.append((sec.get("id"), r.get("k"), fld))
    return out


# Curated master list of POE patch-note section titles (3.27–3.29 + common older ones).
# The forum TOC is a single space-joined line, so we detect titles by finding each known
# title as a contiguous substring in the Table-of-Contents region. This is far more reliable
# than regex-splitting the joined line.
KNOWN_TITLES = [
    "The Curse of the Allflame Challenge League",
    "The Mirage Challenge League",
    "New Content and Features",
    "Mercenaries of Trarthus as a Core League",
    "Keepers of the Flame as a Core League",
    "Harbinger Removed as a Core League",
    "Abyss Revamp",
    "Legion Revamp",
    "Gem Socket Changes",
    "Talisman Revamp",
    "League Changes",
    "Betrayal",
    "Breach",
    "Endgame Changes",
    "Atlas Passive Tree Changes",
    "Player Changes",
    "Ascendancy Changes",
    "Bloodline Changes",
    "Passive Skill Tree Changes",
    "Skill Gem Changes",
    "Vaal Gem Changes",
    "Support Gem Changes",
    "Unique Item Changes",
    "Item Changes",
    "Divination Card Changes",
    "Ruthless-specific Changes",
    "Monster Changes",
    "Quest Reward Changes",
    "User Interface and Quality of Life Changes",
    "Microtransaction Updates",
    "Bug Fixes",
]


def auto_titles(body):
    """Find the TOC titles as contiguous substrings in the Table-of-Contents region.
    The forum cache collapses the notes into one/two giant lines, so the TOC is a single
    space-joined line. We match each KNOWN title against the ToC substring. A regex fallback
    is deliberately avoided: with no delimiter between titles it merges adjacent ones
    (e.g. 'Betrayal Breach Endgame Changes')."""
    i = body.find("Table of Contents")
    if i < 0:
        return []
    rest = body[i + len("Table of Contents"):]
    for marker in ("Return to top", " Meet ", "Meet Valerie", "Posted by"):
        j = rest.find(marker)
        if j > 0:
            rest = rest[:j]
            break
    return [t for t in KNOWN_TITLES if t in rest]


def slice_sections(body, titles):
    offs = []
    for t in titles:
        occ = [m.start() for m in re.finditer(re.escape(t), body)]
        # real body = largest offset (TOC copy is near the top)
        offs.append((t, max(occ) if occ else -1))
    offs = [(t, o) for t, o in offs if o >= 0]
    offs.sort(key=lambda x: x[1])
    P = "Return to top"
    segs = []
    for i, (t, o) in enumerate(offs):
        e = offs[i + 1][1] if i + 1 < len(offs) else len(body)
        txt = body[o:e]
        rt = txt.rfind(P)
        if rt > 200:
            txt = txt[:rt]
        segs.append((t, txt))
    return segs


def extract_facts(text):
    sents = re.split(r"(?<=[.;])\s+", text)
    out = []
    for s in sents:
        s = s.strip()
        if len(s) < 18:
            continue
        if not SIGNALS.search(s):
            continue
        if "Return to top" in s or s.startswith("Content Update") or "Sign Up" in s:
            continue
        out.append(s)
    return out


def fact_numbers(fact):
    return set(NUM.findall(fact.lower()))


def present(fact, wordset, numset):
    """Strict: word overlap >=0.6 AND (no numbers, or at least one number matches)."""
    kt = [w for w in norm(fact).split() if len(w) > 3 and w not in STOP]
    if kt:
        hit = sum(1 for w in kt if w in wordset)
        if (hit / len(kt)) < 0.6:
            return False
    nums = fact_numbers(fact)
    if len(nums) >= 2 and not (nums & numset):
        return False
    return True


def main():
    ap = argparse.ArgumentParser(description="Strict per-section coverage scan.")
    ap.add_argument("cache")
    ap.add_argument("league")
    ap.add_argument("--titles", help="pipe-separated explicit TOC titles")
    args = ap.parse_args()

    body = open(args.cache, encoding="utf-8", errors="replace").read()
    wordset, numset = json_corpus(args.league)

    print("=== TRUNCATION WARNINGS (rows containing '...') ===")
    trunc = detect_truncation(args.league)
    if not trunc:
        print("  none")
    for sid, k, fld in trunc:
        print(f"  [{sid}] {k} ({fld})")

    titles = args.titles.split("|") if args.titles else auto_titles(body)
    titles = [t.strip() for t in titles if t.strip()]
    segs = slice_sections(body, titles)

    print(f"\n=== PER-SECTION COVERAGE ({len(segs)} sections) ===")
    print(f"{'section':42} {'facts':>6} {'miss':>5} {'cov%':>6}")
    total_facts = total_miss = 0
    hard = []
    for t, txt in segs:
        facts = extract_facts(txt)
        miss = [f for f in facts if not present(f, wordset, numset)]
        total_facts += len(facts)
        total_miss += len(miss)
        pct = 100 * (1 - len(miss) / len(facts)) if facts else 100.0
        flag = "  <-- LOW" if pct < 80 and facts else ""
        print(f"{t[:42]:42} {len(facts):>6} {len(miss):>5} {pct:>5.0f}%{flag}")
        for f in miss:
            hard.append((t, f))
    if total_facts:
        print(f"{'TOTAL':42} {total_facts:>6} {total_miss:>5} {100*(1-total_miss/total_facts):>5.0f}%")

    print("\n=== HARD MISSES (grep-confirm before adding) ===")
    if not hard:
        print("  none")
    for t, f in hard:
        print(f"  [{t}] {f[:200]}")


if __name__ == "__main__":
    main()
