#!/usr/bin/env python3
"""
Build the whole site: landing page, playground, chapter pages, and the blog.

Everything the site needs is produced here, so the workflow is one command.
There are two kinds of page and each is built the way it should be:

* **Generated pages** -- the landing page and the 18 chapter pages -- come from
  Jinja templates in ``templates/``. Their content is structural (hero, card
  grids, one Sage cell per listing), and putting book code through a Markdown
  parser is what silently shredded a quarter of the cells before: CommonMark
  ends a raw-HTML block at the first blank line, and a quarter of the listings
  contain one.

* **Prose pages** -- the playground text and the blog posts -- are Markdown,
  rendered by pandoc, so footnotes, tables and smart quotes work normally.

Both share one definition of the chrome: ``templates/pandoc.html`` is a Jinja
template that renders *to* a pandoc template, so the topbar and footer exist
once rather than in two copies that drift.

Nothing that could go stale is typed in. Listing and chapter counts come from
``book_listings.json`` (itself generated from ``chapters/*.tex``), the page
count from the built PDF, and the posts from ``blog/``.

Usage::

    python3 .github/pages/build_site.py site/
"""

import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request

from jinja2 import Environment, FileSystemLoader, StrictUndefined

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEMPLATES = os.path.join(HERE, "templates")
STYLES = os.path.join(HERE, "styles")
LISTINGS = os.path.join(ROOT, "sage", "playground", "book_listings.json")
POSTS = os.path.join(ROOT, "blog")

GH = "https://github.com/AppliedPQC"
RAW = "https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py"
BOOT = ('import urllib.request\n'
        'exec(urllib.request.urlopen("%s").read())' % RAW)

STANDARDS = [
    dict(name="ML-KEM", fips="FIPS 203",
         blurb="21 of 21 algorithms. Key encapsulation at 512, 768 and 1024."),
    dict(name="ML-DSA", fips="FIPS 204",
         blurb="49 of 49 algorithms. Signatures at 44, 65 and 87."),
    dict(name="SLH-DSA", fips="FIPS 205",
         blurb="25 of 25 algorithms, all twelve approved parameter sets."),
    dict(name="FN-DSA", fips="FIPS 206",
         blurb="18 of 18 Falcon algorithms. Still in development at NIST, so "
               "validated against Falcon's own tests."),
]

env = Environment(loader=FileSystemLoader(TEMPLATES),
                  undefined=StrictUndefined,   # a typo'd variable fails the build
                  keep_trailing_newline=True)


def css(*names):
    return "\n".join(open(os.path.join(STYLES, n)).read() for n in names)


def pdf_pages(pdf):
    """Page count of the book, so the figure on the landing page is never typed.

    Read from the LaTeX log first: it is always present after a build and needs
    no extra tool. pdfinfo is a fallback for building the site without
    rebuilding the PDF -- it is not installed on the CI runner, and counting
    /Type /Page in the raw bytes does not work because those objects sit inside
    compressed object streams.
    """
    log = os.path.join(ROOT, "apqc.log")
    if os.path.exists(log):
        m = re.search(r"Output written on .*?\((\d+) pages",
                      open(log, errors="replace").read())
        if m:
            return int(m.group(1))
    try:
        out = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout
        m = re.search(r"^Pages:\s+(\d+)", out, re.M)
        if m:
            return int(m.group(1))
    except FileNotFoundError:
        pass
    return None


FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.S)
SOURCES = os.path.join(POSTS, "sources.json")
RAW_REPO = "https://raw.githubusercontent.com/AppliedPQC/%s/main/%s"


def fetch_sourced(build):
    """Posts whose text lives in another repository.

    The document is fetched at build time rather than copied here, so the
    original stays the single source and the two cannot drift. Its own top-level
    heading becomes the title; only the date and the index summary are held
    locally, since those are about presentation rather than content.
    """
    if not os.path.exists(SOURCES):
        return []
    out = []
    for e in json.load(open(SOURCES)):
        url = RAW_REPO % (e["repo"], e["path"])
        try:
            body = urllib.request.urlopen(url, timeout=30).read().decode()
        except Exception as exc:                       # noqa: BLE001 - reported as-is
            raise SystemExit("could not fetch %s\n%s\nThe blog sources a "
                             "document from another repository; check it is "
                             "still at that path." % (url, exc))
        m = re.search(r"^#\s+(.+)", body, re.M)
        if not m:
            raise SystemExit("%s has no top-level heading to use as a title" % url)
        title = m.group(1).strip()
        home = "https://github.com/AppliedPQC/%s" % e["repo"]
        note = ("*Originally published in [%s](%s/blob/main/%s), where it is "
                "maintained. This page renders that document.*\n\n"
                % (e["repo"], home, e["path"]))
        # Keep the heading first so the page leads with the title, then the note.
        body = body.replace(m.group(0), m.group(0) + "\n\n" + note, 1)
        path = os.path.join(build, "sourced-%s.md" % e["slug"])
        open(path, "w").write(body)
        out.append(dict(title=title, date=e["date"], summary=e.get("summary", ""),
                        slug=e["slug"], path=path, source=home))
    return out


def read_posts():
    """Posts written in this repository."""
    if not os.path.isdir(POSTS):
        return []
    out = []
    for f in sorted(os.listdir(POSTS)):
        if not f.endswith(".md") or f == "README.md":
            continue
        path = os.path.join(POSTS, f)
        m = FRONT.match(open(path).read())
        if not m:
            raise SystemExit("%s: missing the --- metadata block at the top" % path)
        meta = {}
        for line in m.group(1).split("\n"):
            if ":" in line:
                k, v = line.split(":", 1)
                meta[k.strip()] = v.strip()
        for required in ("title", "date"):
            if not meta.get(required):
                raise SystemExit("%s: metadata block has no %s" % (path, required))
        meta.setdefault("summary", "")
        meta["slug"] = f[:-3]
        meta["path"] = path
        out.append(meta)
    out.sort(key=lambda p: p["date"], reverse=True)
    return out


def pandoc(src, out, template, title):
    subprocess.run(
        ["pandoc", src, "--from=gfm+yaml_metadata_block", "--to=html5",
         "--standalone", "--template=" + template,
         "--variable=pagetitle=" + title, "--variable=lang=en",
         "--output=" + out],
        check=True)


def main():
    dest = os.path.abspath(sys.argv[1])
    build = os.path.join(dest, "_build")
    os.makedirs(build, exist_ok=True)

    data = json.load(open(LISTINGS))
    chapters = data["chapters"]
    n_listings = sum(len(c["listings"]) for c in chapters)
    posts = read_posts() + fetch_sourced(build)
    posts.sort(key=lambda p: p["date"], reverse=True)

    # The book, and the alias some published links still use.
    for name in ("apqc.pdf", "main.pdf"):
        shutil.copyfile(os.path.join(ROOT, "apqc.pdf"), os.path.join(dest, name))
    pages = pdf_pages(os.path.join(dest, "apqc.pdf"))

    base = dict(gh=GH, css=css("site.css"))

    # --- landing page -----------------------------------------------------
    open(os.path.join(dest, "index.html"), "w").write(
        env.get_template("home.html").render(
            base, title="Applied Post-Quantum Cryptography",
            css=css("site.css", "home.css"), main_class="home", here="home",
            n_listings=n_listings, pages=pages, posts=posts,
            standards=STANDARDS))

    # --- chapter pages ----------------------------------------------------
    tpl = env.get_template("chapter.html")
    for c in chapters:
        open(os.path.join(dest, "playground-%s.html" % c["stem"]), "w").write(
            tpl.render(base, title="%s — Applied Post-Quantum Cryptography" % c["title"],
                       css=css("site.css", "playground.css"), main_class="",
                       here="playground", chapter=c, boot=BOOT,
                       n_runnable=sum(1 for l in c["listings"] if l["runnable"])))
    # book-code.html was a published URL before the pages merged.
    open(os.path.join(dest, "book-code.html"), "w").write(
        env.get_template("redirect.html").render(to="playground.html"))

    # --- prose pages, via pandoc -----------------------------------------
    # One pandoc template per chrome variant, rendered from the same partials
    # the generated pages use.
    def pandoc_template(name, sagecell, extra_css, here):
        p = os.path.join(build, name)
        open(p, "w").write(env.get_template("pandoc.html").render(
            base, css=css("site.css", *extra_css), sagecell=sagecell, here=here))
        return p

    play_tpl = pandoc_template("t-playground.html", True, ("playground.css",), "playground")
    blog_tpl = pandoc_template("t-blog.html", False, (), "blog")

    # The playground is the single entry point for running code, so the
    # generated chapter table is appended to its prose.
    table = env.get_template("chapters_table.md").render(
        chapters=chapters, n_listings=n_listings)
    merged = os.path.join(build, "playground.md")
    open(merged, "w").write(open(os.path.join(HERE, "playground.md")).read() + table)
    pandoc(merged, os.path.join(dest, "playground.html"), play_tpl,
           "Playground — Applied Post-Quantum Cryptography")

    for p in posts:
        pandoc(p["path"], os.path.join(dest, "blog-%s.html" % p["slug"]), blog_tpl,
               "%s — Applied Post-Quantum Cryptography" % p["title"])
    index_md = os.path.join(build, "blog.md")
    open(index_md, "w").write(env.get_template("blog_index.md").render(posts=posts))
    pandoc(index_md, os.path.join(dest, "blog.html"), blog_tpl,
           "Blog — Applied Post-Quantum Cryptography")

    open(os.path.join(dest, ".nojekyll"), "w").close()
    shutil.rmtree(build)

    print("landing page: %d listings, %d chapters, %s"
          % (n_listings, len(chapters), "%d pages" % pages if pages else "no PDF"))
    print("chapter pages: %d" % len(chapters))
    print("blog: %d post(s)" % len(posts))


if __name__ == "__main__":
    main()
