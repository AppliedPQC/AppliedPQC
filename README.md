# LaTeX book scaffold

This folder contains a minimal LaTeX project for a post-quantum cryptography book.

## Build the PDF

Run:

```bash
cd /data/stephen/pqc/latex
pdflatex -interaction=nonstopmode main.tex
bibtex main
pdflatex -interaction=nonstopmode main.tex
pdflatex -interaction=nonstopmode main.tex
```

If you want a more modern workflow, you can use `latexmk`:

```bash
latexmk -pdf main.tex
```

## Suggested next steps

- Add chapters as `\chapter{...}` sections.
- Add figures and tables with `\includegraphics` and `tabular`.
- Split content into separate files such as `chapters/introduction.tex`.
