#!/usr/bin/env python3
"""
Generate the per-chapter playground pages from ``book_listings.json``.

Writes complete HTML into the directory given as the first argument: one page
per chapter, plus an index.

These pages are written directly rather than through pandoc, deliberately.
A quarter of the book's listings contain a blank line, and CommonMark ends a
raw HTML block at the first blank line -- routing generated code through a
Markdown parser silently shredded those cells into paragraph tags. Emitting
the HTML here removes that whole class of failure.

Because the listings come from the generated JSON, which itself comes from
``chapters/*.tex``, a code change in the book flows through to a runnable cell
with no hand-editing anywhere in the chain.
"""

import html
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.join(ROOT, "sage", "playground", "book_listings.json")

BOOT = ('import urllib.request\n'
        'exec(urllib.request.urlopen("https://raw.githubusercontent.com/'
        'AppliedPQC/AppliedPQC/main/sage/playground.py").read())\n')


def _inc(name):
    return open(os.path.join(HERE, name)).read()


def page(title, body):
    return """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>%s</title>
%s%s</head>
<body>
%s<main>
%s</main>
%s
</body>
</html>
""" % (html.escape(title), _inc("head.html"), _inc("playground-head.html"),
       _inc("playground-before-body.html"), body, _inc("footer.html"))


def cell(code):
    # Script content is raw: the only sequence that could close it early is a
    # literal "</script", which Python source does not contain.  Guard anyway.
    assert "</script" not in code
    return '<div class="sage"><script type="text/x-sage">%s</script></div>\n' % code


def chapter_page(c):
    n_run = sum(1 for l in c["listings"] if l["runnable"])
    b = ["<h1>%s</h1>" % html.escape(c["title"]),
         "<p>Every code listing from this chapter of <em>Applied Post-Quantum "
         "Cryptography</em> — %d in total, %d runnable here. Edit any cell and "
         "press <strong>Run</strong>.</p>" % (len(c["listings"]), n_run),
         "<p>The book's snippets build on each other down the chapter, but a "
         "Sage Cell kernel runs one cell and keeps no state afterwards, so each "
         "cell replays the earlier listings with <code>apqc_book</code>. That "
         "call is the only thing added to the book's own code.</p>",
         '<p><a href="playground.html">← the playground</a></p>']

    for l in c["listings"]:
        b.append('<h2 id="listing-%d">Listing %d</h2>' % (l["n"], l["n"]))
        if not l["runnable"]:
            b.append("<p>Not runnable on its own: %s.</p>" % html.escape(l["note"]))
            b.append("<pre><code>%s</code></pre>" % html.escape(l["code"]))
            continue
        pre = BOOT
        if l["n"] > 1:
            pre += "apqc_book('%s', upto=%d)\n" % (c["stem"], l["n"])
        elif l["requires"]:
            pre += "apqc_load(%s)\n" % ", ".join(repr(m) for m in l["requires"])
        b.append(cell(pre + l["code"]))
    return page("%s — Applied Post-Quantum Cryptography" % c["title"], "\n".join(b))


def chapters_fragment(chapters):
    """The chapter table, as Markdown appended to the playground page.

    The playground is the single entry point for running code, so the list of
    chapters lives there rather than on a page of its own.
    """
    total = sum(len(c["listings"]) for c in chapters)
    out = ["", "## Every listing in the book", "",
           "All %d code listings from the chapters, runnable the same way. "
           "Each cell replays its chapter's earlier listings first, so any "
           "snippet can be tried on its own." % total, "",
           "| Chapter | Listings | |", "| --- | --- | --- |"]
    for c in chapters:
        out.append("| %s | %d | [run](playground-%s.html) |"
                   % (c["title"].replace("|", "\\|"), len(c["listings"]), c["stem"]))
    return "\n".join(out) + "\n"


def redirect(to):
    """book-code.html was a published URL before the pages merged."""
    return ('<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8" />\n'
            '<meta http-equiv="refresh" content="0; url=%s" />\n'
            '<link rel="canonical" href="%s" />\n'
            '<title>Moved</title></head>\n'
            '<body><p>This page is now part of the '
            '<a href="%s">playground</a>.</p></body></html>\n' % (to, to, to))


def main():
    dest = sys.argv[1]
    os.makedirs(dest, exist_ok=True)
    chapters = json.load(open(DATA))["chapters"]
    for c in chapters:
        open(os.path.join(dest, "playground-%s.html" % c["stem"]), "w").write(chapter_page(c))
    open(os.path.join(dest, "book-code.html"), "w").write(redirect("playground.html"))
    open(os.path.join(dest, "_chapters.md"), "w").write(chapters_fragment(chapters))
    cells = sum(1 for c in chapters for l in c["listings"] if l["runnable"])
    print("%d chapter pages + index, %d runnable cells -> %s"
          % (len(chapters), cells, dest))


if __name__ == "__main__":
    main()
