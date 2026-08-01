#!/usr/bin/env python3
"""
Assert the rendered site is actually what it should be.

A broken page usually still deploys: pandoc exits 0 on mangled input, a failed
fetch can leave a stub, and a mistake in a shared partial removes the chrome
from every page at once. Each check here corresponds to something that has
genuinely gone wrong at least once.

Usage::

    python3 .github/pages/check_site.py site/
"""

import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LISTINGS = os.path.join(ROOT, "sage", "playground", "book_listings.json")
POSTS = os.path.join(ROOT, "blog")

failures = []
notes = []


def check(ok, message):
    if not ok:
        failures.append(message)


def read(path):
    return open(path, encoding="utf-8", errors="replace").read()


def main():
    site = os.path.abspath(sys.argv[1])
    p = lambda *a: os.path.join(site, *a)

    # --- the book itself --------------------------------------------------
    check(os.path.getsize(p("apqc.pdf")) > 100_000, "apqc.pdf missing or truncated")

    # --- landing page -----------------------------------------------------
    index = read(p("index.html"))
    check("<title>Applied Post-Quantum Cryptography</title>" in index,
          "landing page lost its title")
    check('href="apqc.pdf"' in index, "landing page does not link the PDF")
    check('<main class="home">' in index, "landing page is not using the home layout")
    check(len(re.findall(r'<section class="band', index)) >= 4,
          "landing page has fewer than four section bands")
    check(len(re.findall(r'<div class="card">', index)) >= 6,
          "landing page has fewer than six cards")
    check("AppliedPQC/awesome-pqc" in index, "landing page does not surface awesome-pqc")
    # The page count is read from the build, never typed in; if the source it
    # comes from moves, the hero loses it silently.
    check(re.search(r"[0-9]+ pages · by", index) is not None,
          "landing page lost the page count")
    check(index.count('name="viewport"') == 1, "landing page has a duplicate viewport tag")

    # --- playground -------------------------------------------------------
    play = read(p("playground.html"))
    check("embedded_sagecell.js" in play, "playground lost the Sage Cell embed")
    cells = play.count('type="text/x-sage"')
    check(cells >= 8, "playground rendered only %d cells" % cells)
    check(play.count("sage/playground.py") >= 8, "playground cells lost their bootstrap")
    check("playground-01_sagemath_basics.html" in play,
          "playground lost the chapter table")
    # The custom pandoc template exists to keep pandoc's own stylesheet out.
    check("max-width: 36em" not in play, "pandoc's default stylesheet leaked in")
    # book-code.html was published before the pages merged.
    check("url=playground.html" in read(p("book-code.html")),
          "the old book-code URL no longer redirects")

    # --- chapter pages ----------------------------------------------------
    chapter_pages = sorted(glob.glob(p("playground-*.html")))
    data = json.load(open(LISTINGS))
    expected = sum(1 for c in data["chapters"] for l in c["listings"] if l["runnable"])
    book_cells = sum(read(f).count('type="text/x-sage"') for f in chapter_pages)
    check(book_cells == expected,
          "%d book cells rendered, expected %d" % (book_cells, expected))
    # A shredded cell shows up as book code leaking into a paragraph.
    for f in chapter_pages:
        check(re.search(r"<p>[a-z_]+ = ", read(f)) is None,
              "%s: a listing was mangled out of its cell" % os.path.basename(f))

    # --- blog -------------------------------------------------------------
    blog = read(p("blog.html"))
    local = [f for f in glob.glob(os.path.join(POSTS, "*.md"))
             if os.path.basename(f) != "README.md"]
    sources_path = os.path.join(POSTS, "sources.json")
    sourced = json.load(open(sources_path)) if os.path.exists(sources_path) else []
    built = glob.glob(p("blog-*.html"))
    check(len(built) == len(local) + len(sourced),
          "%d blog pages built, expected %d local + %d sourced"
          % (len(built), len(local), len(sourced)))
    for f in local:
        slug = os.path.basename(f)[:-3]
        check("blog-%s.html" % slug in blog, "blog index does not link %s" % slug)
    for e in sourced:
        page = p("blog-%s.html" % e["slug"])
        check(os.path.exists(page), "sourced post %s was not built" % e["slug"])
        if os.path.exists(page):
            html = read(page)
            # A failed fetch would leave a stub rather than an error.
            check(len(html) > 8000,
                  "%s is only %d bytes; the source fetch looks empty"
                  % (os.path.basename(page), len(html)))
            check("Originally published" in html and e["repo"] in html,
                  "%s lost its link back to the source" % os.path.basename(page))
            check("blog-%s.html" % e["slug"] in blog,
                  "blog index does not link %s" % e["slug"])
            notes.append("sourced post %s: %d bytes" % (e["slug"], len(html)))

    # --- chrome, which lives in shared partials ---------------------------
    pages = [f for f in glob.glob(p("*.html")) if "book-code" not in f]
    for f in pages:
        h = read(f)
        name = os.path.basename(f)
        check("x.com/AppliedPQC" in h, "%s has no X link" % name)
        check('class="sitefooter"' in h, "%s has no footer" % name)
        check('class="button" href="apqc.pdf">Download the PDF' not in h,
              "%s: the PDF button is back in the topbar" % name)

    notes.append("landing page %d bytes, PDF %d bytes"
                 % (len(index), os.path.getsize(p("apqc.pdf"))))
    notes.append("playground %d cells; book %d chapters, %d cells"
                 % (cells, len(chapter_pages), book_cells))
    notes.append("blog %d post(s); chrome checked on %d pages" % (len(built), len(pages)))

    for n in notes:
        print(n)
    if failures:
        for f in failures:
            print("::error::%s" % f)
        return 1
    print("all site checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
