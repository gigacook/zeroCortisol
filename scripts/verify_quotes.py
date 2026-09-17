#!/usr/bin/env python3
"""Verify data/quotes.json against the source texts.

Checks:
  * every quote is a verbatim substring of its source_file after normalisation
    (whitespace collapsed; curly/straight quotes and dashes folded; '_' emphasis
    markers and numeric footnote markers like [12] removed -- applied identically
    to both sides)
  * at least MIN_QUOTES quotes, unique well-formed ids, required fields present
  * themes come from the fixed vocabulary
  * every in-scope source work is represented (>= MIN_PER_WORK quotes)
  * no personal markers
  * data/corpus_meta.json quote counts agree with quotes.json (if present)

Stdlib only. Run from anywhere:  python3 scripts/verify_quotes.py
Exit status is non-zero on any failure.
"""
import collections
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
QUOTES = os.path.join(ROOT, "data", "quotes.json")
META = os.path.join(ROOT, "data", "corpus_meta.json")

MIN_QUOTES = 366
MIN_PER_WORK = 5
REQUIRED = ("id", "quote", "author", "work", "source_file", "themes", "relevance")
THEMES = {"agency", "will", "courage", "fear", "attention", "judgment", "detachment",
          "indifference", "presence", "action", "self-mastery", "freedom", "suffering", "fate"}
IN_SCOPE = [
    "source/01b_Ecclesiastes_KJV.md",
    "source/02_Epictetus_Discourses.md",
    "source/03_MarcusAurelius_Meditations.md",
    "source/04_Plato_Republic.md",
    "source/05_Plato_Apology.md",
    "source/06_Plato_Crito.md",
    "source/07_Plato_Phaedo.md",
    "source/08_Plato_Symposium.md",
    "source/09_Dostoevsky_NotesFromUnderground.md",
    "source/10_Dostoevsky_BrothersKaramazov.md",
    "source/11_Dostoevsky_CrimeAndPunishment.md",
    "source/12_Dostoevsky_WhiteNights.md",
    "source/14_Tolstoy_AnnaKarenina.md",
    "source/15_Tolstoy_WarAndPeace.md",
    "source/16_Kierkegaard_Selections.md",
    "source/17_Kafka_Metamorphosis.md",
    "source/18_Kafka_Trial.md",
    "source/19_Machiavelli_Prince.md",
    "source/20_Machiavelli_DiscoursesLivy.md",
    "source/21_Nietzsche_Zarathustra.md",
    "source/22_Nietzsche_BeyondGoodAndEvil.md",
    "source/23_Nietzsche_GenealogyOfMorals.md",
]
# Markers that must never appear anywhere in an entry. The list is private: it is
# read from private/personal_markers.txt (gitignored, one word per line, '#' comments).
# If that file is absent the check is skipped with a notice.
MARKERS_FILE = os.path.join(ROOT, "private", "personal_markers.txt")


def load_personal_markers():
    try:
        with open(MARKERS_FILE, encoding="utf-8") as fh:
            words = [ln.strip() for ln in fh if ln.strip() and not ln.lstrip().startswith("#")]
    except OSError:
        return None
    if not words:
        return None
    return re.compile(r"\b(?:" + "|".join(re.escape(w) for w in words) + r")\b", re.I)


PERSONAL_ANYWHERE = load_personal_markers()
# Markers that must not appear in the generic relevance note (quotes may legitimately
# contain words like "her" or "subject").
PERSONAL_RELEVANCE = re.compile(r"subject|\bshe\b|\bher\b", re.I)

FOOTNOTE = re.compile(r"\[\d{1,3}\]")
FOLD = str.maketrans({
    "‘": "'", "’": "'", "‚": "'", "‛": "'",
    "“": '"', "”": '"', "„": '"', "‟": '"',
    "—": "-", "–": "-", "‒": "-", "―": "-",
    " ": " ",
})


def normalize(text):
    text = FOOTNOTE.sub("", text).replace("_", "").translate(FOLD)
    return " ".join(text.split())


def main():
    failures = []
    if PERSONAL_ANYWHERE is None:
        print("NOTICE: private/personal_markers.txt not found; personal-marker check skipped.")

    def fail(msg):
        failures.append(msg)

    try:
        with open(QUOTES, encoding="utf-8") as fh:
            quotes = json.load(fh)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: cannot load {QUOTES}: {exc}")
        return 1
    if not isinstance(quotes, list):
        print("FAIL: quotes.json must be a JSON array")
        return 1

    sources = {}
    ids = collections.Counter()
    per_file = collections.Counter()
    per_work = collections.Counter()
    for idx, entry in enumerate(quotes):
        label = entry.get("id", f"#{idx}") if isinstance(entry, dict) else f"#{idx}"
        if not isinstance(entry, dict):
            fail(f"{label}: entry is not an object")
            continue
        missing = [k for k in REQUIRED if k not in entry or entry[k] in ("", None, [])]
        if missing:
            fail(f"{label}: missing/empty fields {missing}")
            continue
        ids[entry["id"]] += 1
        if not re.fullmatch(r"q\d{4}", entry["id"]):
            fail(f"{label}: malformed id")
        for key in ("quote", "author", "work", "source_file", "relevance"):
            if not isinstance(entry[key], str):
                fail(f"{label}: {key} must be a string")
        if not isinstance(entry["themes"], list) or not all(isinstance(t, str) for t in entry["themes"]):
            fail(f"{label}: themes must be a list of strings")
        else:
            bad = [t for t in entry["themes"] if t not in THEMES]
            if bad:
                fail(f"{label}: themes outside vocabulary {bad}")

        blob = json.dumps(entry, ensure_ascii=False)
        if PERSONAL_ANYWHERE is not None and PERSONAL_ANYWHERE.search(blob):
            fail(f"{label}: personal marker found: {PERSONAL_ANYWHERE.search(blob).group(0)!r}")
        if PERSONAL_RELEVANCE.search(entry["relevance"]):
            fail(f"{label}: personal marker in relevance: {PERSONAL_RELEVANCE.search(entry['relevance']).group(0)!r}")

        sf = entry["source_file"]
        if sf not in IN_SCOPE:
            fail(f"{label}: source_file not in scope: {sf}")
        path = os.path.join(ROOT, sf)
        if sf not in sources:
            try:
                with open(path, encoding="utf-8") as fh:
                    sources[sf] = normalize(fh.read())
            except OSError as exc:
                fail(f"{label}: cannot read {sf}: {exc}")
                sources[sf] = None
        if sources[sf] is not None:
            needle = normalize(entry["quote"])
            if not needle or needle not in sources[sf]:
                fail(f"{label}: quote not found verbatim in {sf}: {entry['quote'][:80]!r}")
        per_file[sf] += 1
        per_work[(entry["author"], entry["work"], sf)] += 1

    dupes = [i for i, n in ids.items() if n > 1]
    if dupes:
        fail(f"duplicate ids: {dupes}")
    if len(quotes) < MIN_QUOTES:
        fail(f"only {len(quotes)} quotes (< {MIN_QUOTES})")
    for sf in IN_SCOPE:
        if per_file[sf] < MIN_PER_WORK:
            fail(f"in-scope work under-represented: {sf} has {per_file[sf]} (< {MIN_PER_WORK})")

    if os.path.exists(META):
        try:
            with open(META, encoding="utf-8") as fh:
                meta = json.load(fh)
            listed = {}
            for author in meta["authors"]:
                for work in author["works"]:
                    listed[(author["name"], work["title"], work["source_file"])] = work["quote_count"]
            for key, n in per_work.items():
                if listed.get(key) != n:
                    fail(f"corpus_meta mismatch for {key}: meta={listed.get(key)} actual={n}")
            for key, n in listed.items():
                if n and key not in per_work:
                    fail(f"corpus_meta lists quotes for {key} but none exist")
            meta_files = {k[2] for k in listed}
            for sf in IN_SCOPE:
                if sf not in meta_files:
                    fail(f"corpus_meta missing in-scope source {sf}")
        except Exception as exc:  # noqa: BLE001
            fail(f"cannot validate corpus_meta.json: {exc}")

    print(f"quotes: {len(quotes)}   unique ids: {len(ids)}   sources: {len(per_file)}/{len(IN_SCOPE)}")
    for sf in IN_SCOPE:
        print(f"  {per_file[sf]:4d}  {sf}")
    if failures:
        print(f"\nFAILED ({len(failures)} problem(s)):")
        for msg in failures:
            print("  - " + msg)
        return 1
    print("\nOK: all quotes verified verbatim; counts, ids, fields, themes, coverage and privacy checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
