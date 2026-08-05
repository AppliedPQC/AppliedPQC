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
``title``
    The nearest section heading above the listing, so a playground page can
    say what a cell is about instead of just numbering it.
``intro``
    The prose paragraphs the book places directly before the listing --
    between the heading (or the previous listing) and the code -- reduced to
    plain text.  Displayed math, figures and tables are dropped; inline math
    is kept in a readable ASCII/Unicode form.
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
HEADING = re.compile(r"\\(?:section|subsection|subsubsection|paragraph)\{")

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


def _balanced(src, start):
    """Content of a {...} group starting at ``start`` (just past the brace)."""
    i, depth = start, 1
    while i < len(src) and depth:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
        i += 1
    return src[start:i - 1], i


def _chapter_title(src):
    """Read \\chapter{...} with balanced braces -- titles contain \\textsuperscript{+}."""
    m = CHAPTER_TITLE.search(src)
    if not m:
        return None
    return _balanced(src, m.end())[0]


def tex_to_text(s):
    """Strip the few LaTeX commands that appear in chapter and section titles."""
    s = s.replace("\\{", "\x01").replace("\\}", "\x02")   # literal braces
    s = re.sub(r"\$([^$]*)\$", lambda m: math_to_text(m.group(1)), s)
    s = re.sub(r"\\textsuperscript\{(.*?)\}", r"\1", s)
    s = re.sub(r"\\texttt\{(.*?)\}", r"\1", s)
    s = re.sub(r"\\emph\{(.*?)\}", r"\1", s)
    s = s.replace("---", "\u2014").replace("--", "\u2013")
    s = re.sub(r"\\[a-zA-Z]+\s*", "", s)
    s = s.replace("{", "").replace("}", "").replace("\\", "").strip()
    return s.replace("\x01", "{").replace("\x02", "}")


# Symbols that occur in the inline math of pre-listing prose.  Anything not
# listed degrades to its bare command name being dropped, which reads worse
# than these but never breaks anything.
MATH_SYMBOLS = {
    "Lambda": "\u039b", "lambda": "\u03bb", "omega": "\u03c9", "rho": "\u03c1",
    "mu": "\u03bc", "sigma": "\u03c3", "epsilon": "\u03b5", "eta": "\u03b7",
    "times": "\u00d7", "cdot": "\u00b7", "pm": "\u00b1", "star": "\u22c6",
    "to": "\u2192", "in": " \u2208 ", "det": "det", "prod": "\u220f",
    "sum": "\u2211", "lfloor": "\u230a", "rfloor": "\u230b",
    "lceil": "\u2308", "rceil": "\u2309", "lVert": "\u2016", "rVert": "\u2016",
    "equiv": "\u2261", "le": "\u2264", "ge": "\u2265", "ne": "\u2260",
    "colon": ":", "mid": "|", "infty": "\u221e", "ldots": "...",
    "dots": "...", "dsts": "...",
}
SUBSCRIPT = str.maketrans("0123456789", "\u2080\u2081\u2082\u2083\u2084\u2085\u2086\u2087\u2088\u2089")
SUPERSCRIPT = str.maketrans("0123456789", "\u2070\u00b9\u00b2\u00b3\u2074\u2075\u2076\u2077\u2078\u2079")


# The number sets, which appear in headings and prose as \mathbb letters.
BLACKBOARD = {"Z": "\u2124", "Q": "\u211a", "R": "\u211d", "C": "\u2102",
              "F": "\U0001d53d", "N": "\u2115"}


def math_to_text(s):
    """Inline $...$ content, reduced to something readable in running text."""
    s = s.replace("\\{", "\x01").replace("\\}", "\x02")   # literal set braces
    s = re.sub(r"\\mathbb\{([A-Z])\}", lambda m: BLACKBOARD.get(m.group(1), m.group(1)), s)
    for cmd in ("mathbf", "mathbb", "mathrm", "mathcal", "boldsymbol",
                "operatorname", "text", "texttt"):
        s = re.sub(r"\\%s\{([^{}]*)\}" % cmd, r"\1", s)
    s = re.sub(r"\\frac\{([^{}]*)\}\{([^{}]*)\}", r"\1/\2", s)
    s = re.sub(r"\\pmod\{([^{}]*)\}", r"mod \1", s)
    s = re.sub(r"\\([a-zA-Z]+)",
               lambda m: MATH_SYMBOLS.get(m.group(1), ""), s)
    s = re.sub(r"_\{(\d+)\}", lambda m: m.group(1).translate(SUBSCRIPT), s)
    s = re.sub(r"\^\{(\d+)\}", lambda m: m.group(1).translate(SUPERSCRIPT), s)
    s = re.sub(r"_\{([^{}]*)\}", lambda m: "_" + m.group(1), s)
    s = re.sub(r"\^\{([^{}]*)\}", lambda m: "^" + m.group(1), s)
    s = re.sub(r"_([0-9])", lambda m: m.group(1).translate(SUBSCRIPT), s)
    s = re.sub(r"\^([0-9])", lambda m: m.group(1).translate(SUPERSCRIPT), s)
    s = s.replace("{", "").replace("}", "").replace("~", " ")
    # literal-brace sentinels stay for the caller, which strips braces itself
    return re.sub(r"\s+", " ", s).strip()


# Environments whose content cannot survive as plain text: dropped whole.
DROP_ENVS = ("figure", "table", "tabular", "tikzpicture", "center",
             "equation", "align", "algorithm", "algorithmic")
# Environments that are just structured prose: unwrapped, items bulleted.
UNWRAP_ENVS = ("itemize", "enumerate", "definition", "quote")


def tex_to_prose(region, chapter_titles):
    """The prose between a heading (or listing) and the next listing,
    reduced to plain-text paragraphs."""
    s = re.sub(r"(?m)^%.*\n?", "", region)
    s = s.replace("\\{", "\x01").replace("\\}", "\x02")   # literal braces
    for env in DROP_ENVS:
        s = re.sub(r"\\begin\{%s\*?\}.*?\\end\{%s\*?\}" % (env, env), "", s, flags=re.S)
    s = re.sub(r"\\\[.*?\\\]", "", s, flags=re.S)
    for env in UNWRAP_ENVS:
        s = re.sub(r"\\(?:begin|end)\{%s\*?\}" % env, "\n\n", s)
    s = s.replace("\\item", "\n\n\u2022 ")
    # The playground box tells the reader to come here; on this page it would
    # be circular.  \sagefile renders as the repository path of the file.
    s = re.sub(r"\\playground\{([^{}]*)\}", "", s)
    s = re.sub(r"\\sagefile\{([^{}]*)\}", lambda m: "sage/" + m.group(1).replace("\\_", "_"), s)
    # "Chapter~\ref{ch:lll}" names a chapter this JSON knows the title of;
    # other \ref targets (figures, algorithms) only exist in the book.
    s = re.sub(r"Chapters?~\\ref\{ch:([a-zA-Z0-9_-]+)\}",
               lambda m: "the \u201c%s\u201d chapter" % chapter_titles[m.group(1)]
               if m.group(1) in chapter_titles else "the corresponding chapter", s)
    s = re.sub(r"[A-Za-z]+~\\ref\{[^{}]*\}",
               lambda m: "the " + m.group(0).split("~")[0].lower() + " in the book", s)
    s = re.sub(r"~?\\cite\{[^{}]*\}", "", s)
    s = re.sub(r"\\(?:label|index|vspace|noindent|centering)\*?\{[^{}]*\}", "", s)
    s = re.sub(r"\\footnote\{[^{}]*\}", "", s)
    s = re.sub(r"\$([^$]*)\$", lambda m: math_to_text(m.group(1)), s)
    s = re.sub(r"\\href\{[^{}]*\}\{([^{}]*)\}", r"\1", s)
    for cmd in ("texttt", "emph", "textbf", "textit", "textsc", "text",
                "textsuperscript"):
        # twice, for one level of nesting (\emph{\texttt{x}})
        for _ in range(2):
            s = re.sub(r"\\%s\{([^{}]*)\}" % cmd, r"\1", s)
    s = re.sub(r"\\paragraph\{([^{}]*)\}", r"\n\n\1.", s)
    s = s.replace("---", "\u2014").replace("--", "\u2013")
    s = s.replace("``", "\u201c").replace("''", "\u201d")
    s = re.sub(r"\\[a-zA-Z]+\s*", "", s)
    s = s.replace("\\_", "_").replace("\\&", "&").replace("\\%", "%")
    s = s.replace("{", "").replace("}", "").replace("~", " ")
    s = s.replace("\x01", "{").replace("\x02", "}")
    paras = [re.sub(r"\s+", " ", p).strip() for p in re.split(r"\n\s*\n", s)]
    return [p for p in paras if p]


def main():
    sources = []
    chapter_titles = {}          # ch:* label -> plain-text title, for \ref
    for name in sorted(os.listdir(CHAPTERS)):
        if not name.endswith(".tex"):
            continue
        src = open(os.path.join(CHAPTERS, name)).read()
        title = _chapter_title(src)
        title = tex_to_text(title) if title else name[:-4]
        sources.append((name[:-4], src, title))
        lab = re.search(r"\\label\{ch:([^}]*)\}", src)
        if lab:
            chapter_titles[lab.group(1)] = title

    chapters = []
    for stem, src, title in sources:
        listings = []
        n = 0
        spans = [m.span() for m in LISTING.finditer(src)]   # every language
        for m in LISTING.finditer(src):
            opts = m.group(1) or ""
            lang = ("python" if "language=Python" in opts else
                    "bash" if "language=bash" in opts else
                    "c" if "language=C" in opts else "none")
            if lang != "python":
                continue        # only Sage listings are runnable, and only
            n += 1              # those are numbered -- shell and C listings
            key = "%s#%d" % (stem, n)   # must not shift the numbering

            # The nearest heading names the listing; the prose after it (or
            # after the previous listing, whichever is closer) introduces it.
            heading, intro_start = "", 0
            for h in HEADING.finditer(src, 0, m.start()):
                heading, intro_start = _balanced(src, h.end())
            prev_end = max([e for s_, e in spans if e <= m.start()], default=0)
            intro = tex_to_prose(src[max(intro_start, prev_end):m.start()],
                                 chapter_titles)
            listings.append({
                "n": n,
                "code": m.group(2).rstrip("\n"),
                "runnable": key not in NOT_RUNNABLE,
                "note": NOT_RUNNABLE.get(key, ""),
                "requires": REQUIRES.get(key, []),
                "title": tex_to_text(heading),
                "intro": intro,
            })
        if listings:
            chapters.append({
                "stem": stem,
                "title": title,
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
