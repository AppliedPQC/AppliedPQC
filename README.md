# Applied Post-Quantum Cryptography

A LaTeX book that builds post-quantum cryptography from the ground up, by
Stephen Duan and Wei Li.

- Repository: https://github.com/AppliedPQC/AppliedPQC
- Live PDF: https://appliedpqc.io/apqc.pdf
- X: https://x.com/AppliedPQC

<div class="callout">
<strong>Also from Applied PQC — <a href="https://github.com/AppliedPQC/awesome-pqc">awesome-pqc</a></strong><br />
A curated, link-verified list of post-quantum cryptography resources for people who have to build and ship it: standards, conformance test vectors, reference implementations, libraries, protocol deployment, and blockchain consensus. Around ninety links across a dozen sections, re-checked on a schedule so the list does not quietly rot.
</div>

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
https://appliedpqc.io/               # landing page
https://appliedpqc.io/apqc.pdf       # the book
https://appliedpqc.io/playground.html # run every listing in a browser
https://appliedpqc.io/blog.html      # notes and research
```

The landing page is assembled by `.github/pages/build_home.py` rather than
rendered from this README: a hero, card grids and section bands need more
structure than linear Markdown can express. Its figures — listing counts,
chapter counts, page count, blog posts — are read from the repository, so they
cannot drift. Chapter pages and the blog index are generated too; only the
playground prose and the blog posts themselves are hand-written.

Blog posts come from two places, both listed newest first. A post written here
is a Markdown file in `blog/` with a `title`, `date` and `summary` metadata
block. A post whose text lives in another repository is an entry in
`blog/sources.json`: the document is fetched at build time and rendered, never
copied, so the original stays the single source. See [`blog/README.md`](blog/README.md).

Pages must be enabled once, with its source set to "GitHub Actions", in the
repository settings. The site is served from the custom domain
`appliedpqc.io`, with HTTPS enforced; the old
`appliedpqc.github.io/AppliedPQC/` address redirects to it.

## Run it in your browser

Every implementation runs at **https://appliedpqc.io/playground.html** with
nothing to install, and so does **every code listing in the book** —
all 105 of them, chapter by chapter, listed at the foot of the same page. The page fetches the `.sage` sources straight from this
repository, so what runs there is exactly the code the book documents.

| Standard | In the browser |
| --- | --- |
| ML-KEM (FIPS 203) | key generation, encapsulation, decapsulation at all three parameter sets |
| ML-DSA (FIPS 204) | key generation, signing, verification at ML-DSA-44, 65, 87 |
| SLH-DSA (FIPS 205) | the `f` sets end to end; the `s` sets verified against NIST's ACVP signatures |
| FN-DSA (FIPS 206) | sampler and FFT checks, plus signing and verification from a stored key |

Execution is on the free [SageMath Cell](https://sagecell.sagemath.org/)
service, which allows 30 seconds per run. Three things do not fit in that
budget -- Falcon key generation, anything at FN-DSA-1024, and signing under
the SLH-DSA `s` parameter sets -- so the playground refuses those up front and
prints the command to run locally instead. Everything else finishes in under
twelve seconds.

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

To install SageMath, the shortest path on any platform is conda-forge:

```bash
conda create -n sage -c conda-forge sage && conda activate sage
```

That gives Sage 10.9 in about two minutes. Docker, `apt` and Homebrew all work
too, and the whole suite has been run in the official `sagemath/sagemath:10.9`
image (462 checks, 0 failures). Sage 9.5 or newer is enough, so Debian's and
Ubuntu's older package is fine. See [`sage/README.md`](sage/README.md#installing-sagemath)
for all the options and the two Docker traps that fail silently.

These are teaching implementations: readable and standards-exact, but not
constant-time and not for production use.

## More from Applied PQC

- **[awesome-pqc](https://github.com/AppliedPQC/awesome-pqc)** — the curated,
  link-verified resource list described at the top of this page.
- **[pqc-research](https://github.com/AppliedPQC/pqc-research)** —
  what a post-quantum migration means for Bitcoin layer 2s, with GOAT as a
  worked case study.

Everything lives under [github.com/AppliedPQC](https://github.com/AppliedPQC).
