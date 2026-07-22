# PQC-101 Book Project

This directory contains a LaTeX-based book project for a post-quantum cryptography book.

## Repository

- GitHub repository: https://github.com/eigmax/PQC-101
- Local working directory: /data/stephen/pqc/latex

## Build the PDF

The simplest way is to use the provided Makefile:

```bash
cd /data/stephen/pqc/latex
make
```

This will compile the main LaTeX document into `main.pdf`.

If you want to clean generated files:

```bash
make clean
```

## Manual LaTeX build

If you prefer to compile by hand:

```bash
cd /data/stephen/pqc/latex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
pdflatex -interaction=nonstopmode -halt-on-error main.tex
```

## Chapter structure

The book source is split into chapter files under the `chapters/` directory, grouped into parts:

**Part I -- Foundations**
- `chapters/00_quantum_threat.tex` (why post-quantum: Shor and Grover)
- `chapters/01_sagemath_basics.tex`
- `chapters/02_linear_algebra.tex`
- `chapters/03_polynomial_ring.tex`

**Part II -- Lattices and Hard Problems**
- `chapters/04_lattice.tex`
- `chapters/05_lll.tex`
- `chapters/06_svp.tex`

**Part III -- Learning With Errors and Its Variants**
- `chapters/07_probability_error.tex`
- `chapters/08_lwe.tex`
- `chapters/09_rlwe.tex`
- `chapters/10_module_lwe.tex`

**Part IV -- From Algebra to a Working Scheme**
- `chapters/11_circulant_convolution.tex`
- `chapters/12_ntt.tex`
- `chapters/13_toy_mlkem.tex`
- `chapters/14_cbd.tex`
- `chapters/15_seed_expansion.tex`

**Part V -- Digital Signature Standards**
- `chapters/16_ml_dsa.tex` (ML-DSA, FIPS 204)
- `chapters/17_slh_dsa.tex` (SLH-DSA, FIPS 205)
- `chapters/18_fn_dsa.tex` (FN-DSA, FIPS 206)

**Part VI -- Code-Based Cryptography** (roadmap)
- `chapters/19_mceliece.tex`
- `chapters/20_hqc.tex`

**Part VII -- Implementation Security** (roadmap)
- `chapters/21_side_channel.tex`

## Publish to GitHub Pages

This repository is now configured to publish the compiled PDF as a GitHub Pages site.

### Steps

1. Push the repository to GitHub.
2. In GitHub, open the repository settings and go to Pages.
3. Set the source to "GitHub Actions".
4. The workflow in `.github/workflows/deploy-pages.yml` will build the book and publish it automatically on every push to the `main` branch.

After the workflow succeeds, the site will be available at:

```text
https://<your-username>.github.io/PQC-101/
```

The PDF itself will be served at:

```text
https://<your-username>.github.io/PQC-101/main.pdf
```

### Local preview

You can also preview the generated site locally by opening the generated `site/index.html` file after a workflow run, or by serving the folder with a simple static server.

## Local Sage Math environment

If you want to use Sage Math locally for mathematical examples, create a local virtual environment and activate it:

```bash
cd /data/stephen/pqc/latex
python3 -m venv .venv-sage
source .venv-sage/bin/activate
```

Then start Sage with:

```bash
sage
```

If `sage` is not on your PATH, you may need to invoke the executable directly if it was installed in a custom location.

## Next steps

- Add more chapters and sections in the `chapters/` files.
- Expand the book outline from foundations to FIPS standards and applications.
- Keep the repository synced with GitHub after edits.
