#!/usr/bin/env python3
"""
Extract every code listing from the book into ``book_listings.json``.

The playground runs the book's code by fetching this file, so it is generated
from ``chapters/*.tex`` rather than maintained by hand: a listing added to the
book becomes a runnable cell with no separate step, and the two cannot drift.

Run ``make playground`` (or this script) after changing a listing; CI checks
that the committed file matches the sources.

Each listing records:

``runnable``
    False for excerpts that are not standalone code -- a quoted method body,
    for instance.  Those are shown in the playground but not executed.
``requires``
    Companion ``.sage`` modules the listing needs, e.g. a listing that uses
    ``BitRev7`` needs ``fips203``.
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))          # repository root
CHAPTERS = os.path.join(ROOT, "chapters")
OUT = os.path.join(HERE, "book_listings.json")

LISTING = re.compile(r"\\begin\{lstlisting\}(\[[^\]]*\])?\n(.*?)\\end\{lstlisting\}", re.S)
CHAPTER_TITLE = re.compile(r"\\chapter\{", re.S)

# Listings that are excerpts rather than standalone programs, with the reason
# shown to the reader.  Keyed by "<chapter file stem>#<listing number>".
NOT_RUNNABLE = {
    "16_ml_dsa#2": "the body of Sign_internal, quoted from the companion file "
                   "-- it refers to self and returns, so it only runs as a method",
}

# Listings that need a companion module loaded first.
REQUIRES = {
    "15_seed_expansion#5": ["fips203"],   # uses BitRev7
}


def _chapter_title(src):
    """Read \\chapter{...} with balanced braces -- titles contain \\textsuperscript{+}."""
    m = CHAPTER_TITLE.search(src)
    if not m:
        return None
    i, depth = m.end(), 1
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[m.end():i - 1]


def tex_to_text(s):
    """Strip the few LaTeX commands that appear in chapter titles."""
    s = re.sub(r"\\textsuperscript\{(.*?)\}", r"\1", s)
    s = re.sub(r"\\texttt\{(.*?)\}", r"\1", s)
    s = re.sub(r"\\emph\{(.*?)\}", r"\1", s)
    s = re.sub(r"\\[a-zA-Z]+\s*", "", s)
    return s.replace("{", "").replace("}", "").replace("\\", "").strip()


def main():
    chapters = []
    for name in sorted(os.listdir(CHAPTERS)):
        if not name.endswith(".tex"):
            continue
        stem = name[:-4]
        src = open(os.path.join(CHAPTERS, name)).read()
        title = _chapter_title(src)
        listings = []
        n = 0
        for m in LISTING.finditer(src):
            opts = m.group(1) or ""
            lang = ("python" if "language=Python" in opts else
                    "bash" if "language=bash" in opts else
                    "c" if "language=C" in opts else "none")
            if lang != "python":
                continue        # only Sage listings are runnable, and only
            n += 1              # those are numbered -- shell and C listings
            key = "%s#%d" % (stem, n)   # must not shift the numbering
            listings.append({
                "n": n,
                "code": m.group(2).rstrip("\n"),
                "runnable": key not in NOT_RUNNABLE,
                "note": NOT_RUNNABLE.get(key, ""),
                "requires": REQUIRES.get(key, []),
            })
        if listings:
            chapters.append({
                "stem": stem,
                "title": tex_to_text(title) if title else stem,
                "listings": listings,
            })

    data = {"_generated_by": "sage/playground/extract_listings.py",
            "chapters": chapters}
    text = json.dumps(data, indent=1, sort_keys=True) + "\n"

    if "--check" in sys.argv:
        current = open(OUT).read() if os.path.exists(OUT) else ""
        if current != text:
            print("book_listings.json is stale; run: make playground", file=sys.stderr)
            return 1
        print("book_listings.json is up to date")
        return 0

    open(OUT, "w").write(text)
    total = sum(len(c["listings"]) for c in chapters)
    runnable = sum(1 for c in chapters for l in c["listings"] if l["runnable"])
    print("%d listings across %d chapters (%d runnable) -> %s"
          % (total, len(chapters), runnable, os.path.relpath(OUT, ROOT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
