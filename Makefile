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

$(TARGET): $(BASENAME).tex $(wildcard chapters/*.tex)
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
	rm -f *.aux *.bbl *.blg *.log *.out *.toc *.pdf *.fdb_latexmk *.fls
