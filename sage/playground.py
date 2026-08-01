"""
Bootstrap for running the Applied PQC Sage sources on sagecell.sagemath.org.

This file is deliberately plain Python -- no Sage-only syntax -- so that a
browser cell can pull it in with nothing more than::

    import urllib.request
    exec(urllib.request.urlopen(
        "https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py"
    ).read())

Everything after that point runs through :func:`apqc_load`, which fetches the
real ``.sage`` sources from the repository and hands them to the Sage
preparser.  The playground therefore has no copy of the implementations: it
always runs exactly the code the book documents.

Sage Cell imposes two limits that shape this file:

* a hard **30 second** compute budget per evaluation, and
* **one-shot kernels** -- state does not survive from one cell to the next,
  so long work cannot be split across cells.

A few operations do not fit in 30 seconds.  Rather than let a cell die
silently at the limit, :func:`apqc_require` refuses up front and says what to
run locally, and :func:`apqc_demo_key` / :func:`apqc_demo_sig` supply
precomputed inputs so the rest of the algorithm stays reachable in a browser.
"""

import json
import urllib.request

RAW = "https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/"

# The namespace to define things in.  ``exec(src)`` without an explicit
# globals dict runs in the caller's namespace, so this is the cell itself.
_NS = globals()
_SRC_CACHE = {}
_ARTIFACTS = [None]
_BOOK = [None]

MODULES = {
    "fips203": "fips203_mlkem.sage",
    "fips204": "fips204_mldsa.sage",
    "fips205": "fips205_slhdsa.sage",
    "fips206": "fips206_fndsa.sage",
    "mlkem":   "fips203_mlkem.sage",
    "mldsa":   "fips204_mldsa.sage",
    "slhdsa":  "fips205_slhdsa.sage",
    "fndsa":   "fips206_fndsa.sage",
}

# Measured on sagecell.sagemath.org (SageMath 10.8).  Times are wall clock
# for the whole cell, including the fetch and preparse of the sources.
TOO_SLOW = {
    "FN-DSA-512.Keygen": (
        "NTRUGen's rejection loop costs 3-10 s per attempt and NTRUSolve runs "
        "past the limit even after an accepted sample.",
        "sk, h = apqc_demo_key('FN-DSA-512')   # precomputed Falcon KAT key"),
    "FN-DSA-1024": (
        "At n=1024 even rebuilding the Falcon tree from a stored key exceeds "
        "the 30 s budget.",
        "sage -c \"load('fips206_fndsa.sage'); FNDSA('FN-DSA-1024').Keygen()\""),
    "SLH-DSA-s.sign": (
        "The small-signature parameter sets sign in roughly 20-60 s: the "
        "hypertree has fewer, taller layers, so signing walks many more "
        "WOTS+ chains.",
        "pk, msg, sig = apqc_demo_sig('SLH-DSA-SHAKE-128s')  # then verify it"),
    "test_kat": (
        "The full ACVP suite is 462 checks and needs the vectors/ directory "
        "on disk.",
        "git clone https://github.com/AppliedPQC/AppliedPQC && "
        "cd AppliedPQC/sage && ./fetch_vectors.sh && sage test_kat.sage"),
}


def _fetch(name):
    if name not in _SRC_CACHE:
        _SRC_CACHE[name] = urllib.request.urlopen(RAW + name, timeout=30).read().decode()
    return _SRC_CACHE[name]


def apqc_load(*names):
    """Load one or more implementation files into this cell's namespace.

    Accepts either a short key (``'fips204'``, ``'mldsa'``) or a filename
    (``'fips204_mldsa.sage'``).  ``common.sage`` is always loaded first.
    """
    from sage.repl.preparse import preparse

    wanted = ["common.sage"]
    for n in names:
        f = MODULES.get(n, n)
        if not f.endswith(".sage"):
            raise ValueError("unknown module %r; try one of %s"
                             % (n, sorted(MODULES)))
        if f not in wanted:
            wanted.append(f)

    for f in wanted:
        src = _fetch(f)
        # The sources call load("common.sage"); there is no filesystem here,
        # and we have already loaded it above.
        src = "\n".join(l for l in src.splitlines()
                        if l.strip() != 'load("common.sage")')
        exec(compile(preparse(src), f, "exec"), _NS)
    return sorted(wanted)


def apqc_require(op):
    """Refuse an operation that cannot finish inside Sage Cell's 30 s budget.

    Returns True for anything that does fit, so it is safe to call freely.
    """
    if op not in TOO_SLOW:
        return True
    why, instead = TOO_SLOW[op]
    raise RuntimeError(
        "%s does not fit in Sage Cell's 30 second budget.\n%s\n\nInstead:\n    %s"
        % (op, why, instead))


def _artifacts():
    if _ARTIFACTS[0] is None:
        _ARTIFACTS[0] = json.loads(_fetch("playground/artifacts.json"))
    return _ARTIFACTS[0]


def apqc_demo_key(param_set="FN-DSA-512"):
    """A precomputed FN-DSA key, so signing is reachable without NTRUGen.

    Returns ``(sk, h)`` exactly as ``FNDSA.Keygen`` would.  The key is the
    round-3 Falcon KAT key, so signatures made with it can be checked against
    the reference test vectors.
    """
    keys = _artifacts()["fndsa_key"]
    if param_set not in keys:
        raise ValueError("no stored key for %r (have %s)"
                         % (param_set, sorted(keys)))
    fn = _NS["FNDSA"](param_set)
    return fn.load_private_key(bytes.fromhex(keys[param_set]["sk"]))


def apqc_demo_sig(param_set="SLH-DSA-SHAKE-128s"):
    """A precomputed SLH-DSA signature for a small-signature parameter set.

    Returns ``(pk, message, signature)`` as byte strings, drawn from NIST's
    ACVP vectors.  Verification of these takes well under a second, so the
    ``s`` parameter sets stay demonstrable even though signing them does not
    fit in a browser.
    """
    cases = _artifacts()["slhdsa_sigver"]
    if param_set not in cases:
        raise ValueError("no stored signature for %r (have %s)"
                         % (param_set, sorted(cases)))
    c = cases[param_set]
    return (bytes.fromhex(c["pk"]), bytes.fromhex(c["message"]),
            bytes.fromhex(c["signature"]))


def _book():
    if _BOOK[0] is None:
        _BOOK[0] = json.loads(_fetch("playground/book_listings.json"))
    return _BOOK[0]


def apqc_chapters():
    """List the book chapters that contain runnable code."""
    for c in _book()["chapters"]:
        print("  %-24s %2d listings   %s"
              % (c["stem"], len(c["listings"]), c["title"]))


def apqc_book(chapter, upto=None):
    """Run a chapter's earlier listings, so a later one has its context.

    The book's snippets build on each other down a chapter, the way cells in a
    notebook do, but a Sage Cell kernel runs exactly one cell and keeps no
    state afterwards.  Each playground cell therefore replays what came before
    it::

        apqc_book('13_toy_mlkem', upto=8)   # listings 1-7 as setup
        ...                                 # then listing 8 itself

    With ``upto`` omitted, every listing in the chapter runs.
    """
    from sage.repl.preparse import preparse

    for c in _book()["chapters"]:
        if c["stem"] == chapter:
            break
    else:
        raise ValueError("no chapter %r; try apqc_chapters()" % chapter)

    numbers = [l["n"] for l in c["listings"]]
    if upto is not None and int(upto) not in numbers:
        # The page and this data file disagree about how the chapter is
        # numbered.  Without this check the cell would quietly replay nothing
        # and then fail on an undefined name from the setup it never ran.
        raise RuntimeError(
            "listing %s is not in chapter %r, which has listings %s.\n"
            "The playground data is out of step with the page -- most likely a "
            "cached copy just after a deploy. Re-run in a minute; if it "
            "persists, regenerate with: make playground"
            % (upto, chapter, numbers))

    wanted = [l for l in c["listings"] if upto is None or l["n"] <= upto]
    needs = sorted({m for l in wanted for m in l["requires"]})
    if needs:
        apqc_load(*needs)

    ran = 0
    for l in wanted:
        if l["n"] == upto or not l["runnable"]:
            continue                       # the target itself is the cell's own body
        exec(compile(preparse(l["code"]), "%s#%d" % (chapter, l["n"]), "exec"), _NS)
        ran += 1
    return ran


def apqc_help():
    print(__doc__)
    print("Modules:  " + ", ".join(sorted(set(MODULES.values()))))
    print("Helpers:  apqc_load, apqc_require, apqc_demo_key, apqc_demo_sig,")
    print("          apqc_book, apqc_chapters")
    print("Does not fit in 30 s:  " + ", ".join(sorted(TOO_SLOW)))
