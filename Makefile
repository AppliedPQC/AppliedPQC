LATEX ?= pdflatex
BASENAME = apqc
TARGET = $(BASENAME).pdf
DOCKER_IMAGE ?= texlive/texlive:latest

ifeq ($(shell command -v $(LATEX) 2>/dev/null),)
  ifeq ($(shell command -v docker 2>/dev/null),)
    $(error pdflatex not found and docker is unavailable)
  endif
  LATEX_CMD = docker run --rm -v "$$(pwd)":/work -w /work $(DOCKER_IMAGE) pdflatex
else
  LATEX_CMD = $(LATEX)
endif

SAGE ?= sage

.PHONY: all clean kat kat-full vectors

all: $(TARGET)

BIBER ?= biber
ifeq ($(shell command -v $(BIBER) 2>/dev/null),)
  ifneq ($(shell command -v docker 2>/dev/null),)
    BIBER_CMD = docker run --rm -v "$$(pwd)":/work -w /work $(DOCKER_IMAGE) biber
  else
    BIBER_CMD = $(BIBER)
  endif
else
  BIBER_CMD = $(BIBER)
endif

# pdflatex, biber, pdflatex twice: the per-chapter reference lists are
# resolved by biber from references.bib.
$(TARGET): $(BASENAME).tex $(wildcard chapters/*.tex) references.bib
	$(LATEX_CMD) -interaction=nonstopmode -halt-on-error $(BASENAME).tex
	$(BIBER_CMD) $(BASENAME)
	$(LATEX_CMD) -interaction=nonstopmode -halt-on-error $(BASENAME).tex
	$(LATEX_CMD) -interaction=nonstopmode -halt-on-error $(BASENAME).tex

# Known-answer tests for the SageMath implementations of FIPS 203-206.
# "make kat" is the quick run; "make kat-full" checks every vector.
vectors:
	./sage/fetch_vectors.sh

kat: vectors
	cd sage && $(SAGE) test_kat.sage

kat-full: vectors
	cd sage && $(SAGE) test_kat.sage --full

clean:
	rm -f *.aux *.bbl *.blg *.bcf *.run.xml *.log *.out *.toc *.pdf *.fdb_latexmk *.fls

# Regenerate the playground's copy of the book listings.  Run after adding or
# editing a code listing in any chapter; CI checks the result is in sync.
playground:
	python3 sage/playground/extract_listings.py

.PHONY: playground
