# Applied Post-Quantum Cryptography

A LaTeX book that builds post-quantum cryptography from the ground up, by
Stephen Duan and Wei Li.

- Repository: https://github.com/AppliedPQC/AppliedPQC
- Live PDF: https://appliedpqc.io/apqc.pdf

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
four standards chapters are backed by complete, test-vector-verified SageMath
implementations in `sage/` (see below). The full table of contents lives in
the compiled PDF.

## Build the PDF

The simplest way is the provided Makefile:

```bash
make          # compiles apqc.tex into apqc.pdf
make clean    # remove generated files
```

The Makefile runs `pdflatex` twice, which is enough to resolve the
cross-references and the (manual) bibliography -- no BibTeX pass is needed.

### Manual build

```bash
pdflatex -interaction=nonstopmode -halt-on-error apqc.tex
pdflatex -interaction=nonstopmode -halt-on-error apqc.tex
```

The document uses TikZ, pgfplots, and the algorithm packages, so a fairly
complete TeX Live is required (the CI installs `texlive-latex-base`,
`-recommended`, `-extra`, `-fonts-recommended`, `-pictures`, and `-science`).

## GitHub Pages

Every push to `main` triggers `.github/workflows/deploy-pages.yml`, which
builds the PDF and publishes it via GitHub Actions. The site is served at:

```text
https://appliedpqc.io/          # landing page
https://appliedpqc.io/apqc.pdf  # the book
```

Pages must be enabled once, with its source set to "GitHub Actions", in the
repository settings. The site is served from the custom domain
`appliedpqc.io`, with HTTPS enforced; the old
`appliedpqc.github.io/AppliedPQC/` address redirects to it.

## SageMath implementations of FIPS 203-206

Alongside the chapters, `sage/` holds complete, byte-exact SageMath
implementations of all four NIST post-quantum standards. Every numbered
algorithm of each standard appears as its own function, named after the
standard and annotated with its algorithm number.

| File | Standard | Scheme | Algorithms | Parameter sets |
| --- | --- | --- | --- | --- |
| `sage/fips203_mlkem.sage` | FIPS 203 | ML-KEM (Kyber) | 21 of 21 | 512, 768, 1024 |
| `sage/fips204_mldsa.sage` | FIPS 204 | ML-DSA (Dilithium) | 49 of 49 | 44, 65, 87 |
| `sage/fips205_slhdsa.sage` | FIPS 205 | SLH-DSA (SPHINCS+) | 25 of 25 | all 12 |
| `sage/fips206_fndsa.sage` | FIPS 206 | FN-DSA (Falcon) | 18 of 18 | 512, 1024 |

FIPS 203, 204 and 205 are checked against NIST's ACVP test vectors and
reproduce them byte for byte. FIPS 206 is still in development at NIST -- no
public draft, no vectors -- so FN-DSA follows the round-3 Falcon submission
and is validated against Falcon's own known-answer tests instead. See
`sage/README.md` for the details.

```bash
make kat        # download the test vectors and run the quick check
make kat-full   # every available test vector
```

`make kat` needs `sage` on your PATH; override it with `make kat SAGE=/path/to/sage`.
These are teaching implementations: readable and standards-exact, but not
constant-time and not for production use.

## More from Applied PQC

- **[awesome-pqc](https://github.com/AppliedPQC/awesome-pqc)** — an
  implementation-first, link-verified list of post-quantum cryptography
  resources: standards, conformance test vectors, libraries, and deployment.
  Every link is checked on a schedule, so the list does not quietly rot.

Everything lives under [github.com/AppliedPQC](https://github.com/AppliedPQC).
