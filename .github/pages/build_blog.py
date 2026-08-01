#!/usr/bin/env python3
"""
Build the blog index from the posts in ``blog/``.

Adding a post means adding one Markdown file to ``blog/`` with a YAML metadata
block; nothing else needs editing. The file name becomes the URL:
``blog/2026-07-31-my-post.md`` is published as ``blog-2026-07-31-my-post.html``.

    ---
    title: What the post is called
    date: 2026-07-31
    summary: One or two sentences for the index.
    ---

    The body, in Markdown.

``title`` and ``date`` are required; a post missing either is an error rather
than a silently mis-rendered page. Posts are listed newest first.

This script writes only the index. The posts themselves are rendered by pandoc
in the workflow, so they get the same template and styling as the rest of the
site, and prose features (footnotes, tables, smart quotes) work normally.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
POSTS = os.path.join(ROOT, "blog")

FRONT = re.compile(r"\A---\n(.*?)\n---\n", re.S)


def read_post(path):
    src = open(path).read()
    m = FRONT.match(src)
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
    meta["slug"] = os.path.basename(path)[:-3]
    return meta


def main():
    dest = sys.argv[1]
    if not os.path.isdir(POSTS):
        raise SystemExit("no blog/ directory at %s" % POSTS)
    posts = [read_post(os.path.join(POSTS, f))
             for f in sorted(os.listdir(POSTS)) if f.endswith(".md")]
    posts.sort(key=lambda p: p["date"], reverse=True)

    out = ["# Blog\n",
           "Notes and research from the Applied PQC project.\n"]
    for p in posts:
        out.append("## [%s](blog-%s.html)\n" % (p["title"], p["slug"]))
        out.append("%s\n" % p["date"])
        if p.get("summary"):
            out.append("%s\n" % p["summary"])
    if not posts:
        out.append("No posts yet.\n")

    os.makedirs(dest, exist_ok=True)
    open(os.path.join(dest, "blog.md"), "w").write("\n".join(out))
    print("%d post(s) -> blog index" % len(posts))
    for p in posts:
        print("   %s  %s" % (p["date"], p["slug"]))


if __name__ == "__main__":
    main()
