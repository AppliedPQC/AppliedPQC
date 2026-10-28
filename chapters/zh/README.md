# Chinese edition

`chapters/zh/<name>.tex` is the Simplified Chinese translation of
`chapters/<name>.tex`. The site renders it at `https://appliedpqc.io/zh-book.html`
alongside the English pages; the PDF is built from the English only.

The Chinese file is paired with the English one structurally, so it keeps every
piece of machinery byte-for-byte and translates only the prose:

- unchanged: `tikzpicture`, `protocol`, `lstlisting` and `verbatim` blocks (the
  figures are shared with the English pages), all math, `\label`, `\ref`, `\cite`,
  `\sagefile`, URLs, and the sequence of environments, chapters, sections and
  subsections;
- translated: titles, prose, captions, theorem titles, table cells, algorithm
  comments and the text of `\playground{}`.

The site build fails if a translation's drawings or labels differ from the
English, or if its sections do not match the English table of contents.

`parts.tex` holds the part and subpart titles, in the order `apqc.tex` gives them.

## Keeping a translation current

The first line of each translation records the English it was made from:

```
% source: <git hash-object chapters/<name>.tex>
```

When the English chapter changes, its hash no longer matches and the Chinese page
shows a note pointing readers to the English. Update the translation, then set the
line to the new output of `git hash-object chapters/<name>.tex`.
