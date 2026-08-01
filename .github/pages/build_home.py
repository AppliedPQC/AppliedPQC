#!/usr/bin/env python3
"""
Build the landing page.

The landing page used to be the rendered README, which kept the two from
drifting but limited the page to whatever linear Markdown could express. A
hero, card grids and full-width section bands need real structure, so the page
is assembled here instead. The README remains the repository's README.

Everything on the page that could go stale is read from the repository rather
than typed in: the blog posts come from ``blog/``, the listing and chapter
counts from ``book_listings.json``, and the page count from the built PDF.
"""

import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LISTINGS = os.path.join(ROOT, "sage", "playground", "book_listings.json")
POSTS = os.path.join(ROOT, "blog")
FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.S)

GH = "https://github.com/AppliedPQC"


def _inc(name):
    return open(os.path.join(HERE, name)).read()


def pdf_pages():
    """Page count of the built PDF, so the figure on the page is never guessed."""
    pdf = os.path.join(ROOT, "apqc.pdf")
    if not os.path.exists(pdf):
        return None
    try:
        out = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout
        m = re.search(r"^Pages:\s+(\d+)", out, re.M)
        if m:
            return int(m.group(1))
    except FileNotFoundError:
        pass
    n = len(re.findall(rb"/Type\s*/Page\b", open(pdf, "rb").read()))
    return n or None


def posts():
    if not os.path.isdir(POSTS):
        return []
    out = []
    for f in sorted(os.listdir(POSTS)):
        if not f.endswith(".md"):
            continue
        m = FRONT.match(open(os.path.join(POSTS, f)).read())
        if not m:
            continue
        meta = {}
        for line in m.group(1).split("\n"):
            if ":" in line:
                k, v = line.split(":", 1)
                meta[k.strip()] = v.strip()
        meta["slug"] = f[:-3]
        out.append(meta)
    out.sort(key=lambda p: p.get("date", ""), reverse=True)
    return out


def band(inner, cls=""):
    return '<section class="band %s"><div class="band-inner">\n%s\n</div></section>' % (cls, inner)


def main():
    dest = sys.argv[1]
    data = json.load(open(LISTINGS))
    n_listings = sum(len(c["listings"]) for c in data["chapters"])
    n_chapters = len(data["chapters"])
    pages = pdf_pages()
    ps = posts()

    hero = """<h1>Applied Post-Quantum Cryptography</h1>
<p class="lede">A book that builds post-quantum cryptography from the ground up —
from lattices and Learning With Errors to complete, byte-exact implementations
of all four NIST standards.</p>
<div class="cta">
<a class="button" href="apqc.pdf">Read the book (PDF)</a>
<a class="button ghost" href="playground.html">Run the code</a>
</div>
<p class="byline">%sby Stephen Duan and Wei Li · free and open source</p>""" % (
        "%d pages · " % pages if pages else "")

    cards = """<h2>Start here</h2>
<p class="sub">Three ways in, depending on what you need.</p>
<div class="cards">
<div class="card"><h3>The book</h3><p>The full arc, from finite fields and
lattices through ML-KEM, ML-DSA, SLH-DSA and FN-DSA, to side channels and
deployment.</p><a class="more" href="apqc.pdf">Download the PDF →</a></div>
<div class="card"><h3>Runnable code</h3><p>All %d code listings and the four
reference implementations run in your browser, with nothing to install.</p>
<a class="more" href="playground.html">Open the playground →</a></div>
<div class="card"><h3>awesome-pqc</h3><p>A curated, link-verified list of
post-quantum resources for people who have to build and ship it — standards,
test vectors, libraries, deployment.</p>
<a class="more" href="%s/awesome-pqc">Browse the list →</a></div>
</div>""" % (n_listings, GH)

    impls = """<h2>The four standards, implemented</h2>
<p class="sub">Every numbered algorithm of each standard, as its own function,
checked against NIST's test vectors.</p>
<div class="cards">
<div class="card"><h3>ML-KEM · FIPS 203</h3><p>21 of 21 algorithms. Key
encapsulation at 512, 768 and 1024.</p></div>
<div class="card"><h3>ML-DSA · FIPS 204</h3><p>49 of 49 algorithms. Signatures
at 44, 65 and 87.</p></div>
<div class="card"><h3>SLH-DSA · FIPS 205</h3><p>25 of 25 algorithms, all twelve
approved parameter sets.</p></div>
<div class="card"><h3>FN-DSA · FIPS 206</h3><p>18 of 18 Falcon algorithms.
Still in development at NIST, so validated against Falcon's own tests.</p></div>
</div>
<p style="margin-top:1.5rem"><a href="%s/AppliedPQC/tree/main/sage">The
implementations on GitHub →</a> · 462 checks, 0 failures against ACVP.</p>""" % GH

    if ps:
        items = "\n".join(
            '<li><span class="date">%s</span><br /><a href="blog-%s.html">%s</a>%s</li>'
            % (p.get("date", ""), p["slug"], p.get("title", p["slug"]),
               "<p>%s</p>" % p["summary"] if p.get("summary") else "")
            for p in ps[:4])
        blog = ('<h2>From the blog</h2>\n<p class="sub">Notes and research from the '
                'project.</p>\n<ul class="posts">\n%s\n</ul>\n'
                '<p style="margin-top:1.4rem"><a href="blog.html">All posts →</a></p>'
                % items)
    else:
        blog = '<h2>From the blog</h2>\n<p class="sub">No posts yet.</p>'

    body = "\n".join([
        band(hero, "hero"),
        band(cards),
        band(impls, "tint"),
        band(blog),
    ])

    footer = _inc("footer.html")

    html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Applied Post-Quantum Cryptography</title>
%s%s</head>
<body>
%s<main class="home">
%s
</main>
%s
</body>
</html>
""" % (_inc("head.html"), _inc("home-head.html"), _inc("before-body.html"),
       body, footer)

    os.makedirs(dest, exist_ok=True)
    open(os.path.join(dest, "index.html"), "w").write(html)
    print("landing page: %d listings, %d chapters, %s, %d post(s)"
          % (n_listings, n_chapters, "%d pages" % pages if pages else "no PDF", len(ps)))


if __name__ == "__main__":
    main()
