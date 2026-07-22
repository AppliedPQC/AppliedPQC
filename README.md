# Post-Quantum Cryptography 101

A LaTeX book that builds post-quantum cryptography from the ground up, by
Stephen Duan, Lin Zhong, and Wei Li.

- Repository: https://github.com/eigmax/PQC-101
- Live PDF: https://eigmax.github.io/PQC-101/main.pdf

## About the book

The book develops the subject as a single arc, from first principles to
deployment. It starts with the quantum threat (why Shor breaks today's
public-key cryptography while Grover only weakens symmetric primitives) and
the mathematical foundations (finite fields, linear algebra, polynomial
rings). It then builds the lattice world -- lattices and hard problems, the
Learning-With-Errors family, and the machinery (NTT, CBD, seed expansion)
that leads to the ML-KEM standard (FIPS 203). From there it treats digital
signatures grouped by their hard problem: lattice-based (ML-DSA / FIPS 204
and FN-DSA / FIPS 206) and hash-based (built up from one-time and Merkle-tree
signatures to SLH-DSA / FIPS 205). It closes with code-based cryptography
(Classic McEliece, HQC), implementation and side-channel security, and a
final part on deploying post-quantum cryptography in real systems (hybrid
TLS 1.3, certificates, and on-chain verification).

Every chapter follows the same style: worked SageMath experiments, TikZ
figures, formal definitions and algorithm blocks, and a reference list. The
full table of contents lives in the compiled PDF.

## Build the PDF

The simplest way is the provided Makefile:

```bash
cd /data/stephen/pqc/latex
make          # compiles main.tex into main.pdf
make clean    # remove generated files
```

The Makefile runs `pdflatex` twice, which is enough to resolve the
cross-references and the (manual) bibliography -- no BibTeX pass is needed.

### Manual build

```bash
cd /data/stephen/pqc/latex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

The document uses TikZ, pgfplots, and the algorithm packages, so a fairly
complete TeX Live is required (the CI installs `texlive-latex-base`,
`-recommended`, `-extra`, `-fonts-recommended`, `-pictures`, and `-science`).

## GitHub Pages

Every push to `main` triggers `.github/workflows/deploy-pages.yml`, which
builds the PDF and publishes it via GitHub Actions. The site is served at:

```text
https://eigmax.github.io/PQC-101/          # landing page
https://eigmax.github.io/PQC-101/main.pdf  # the book
```

Pages must be enabled once, with its source set to "GitHub Actions", in the
repository settings.

## Local SageMath environment (optional)

The code experiments are written for SageMath. To run them locally:

```bash
cd /data/stephen/pqc/latex
python3 -m venv .venv-sage
source .venv-sage/bin/activate
sage
```

If `sage` is not on your PATH, invoke the executable directly from its
install location.
