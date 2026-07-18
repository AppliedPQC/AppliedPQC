LATEX ?= pdflatex
BASENAME = main
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

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(BASENAME).tex $(wildcard chapters/*.tex)
	$(LATEX_CMD) -interaction=nonstopmode -halt-on-error $(BASENAME).tex
	$(LATEX_CMD) -interaction=nonstopmode -halt-on-error $(BASENAME).tex

clean:
	rm -f *.aux *.bbl *.blg *.log *.out *.toc *.pdf *.fdb_latexmk *.fls
