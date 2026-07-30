# SageMath reference implementations of FIPS 203, 204, 205 and 206

Complete, byte-exact SageMath implementations of the four NIST
post-quantum standards, written to accompany *Applied Post-Quantum
Cryptography*. Every numbered algorithm of each standard appears as its own
function, named after the standard and annotated with its algorithm
number, so the code can be read side by side with the specification.

| File | Standard | Scheme | Algorithms | Parameter sets |
| --- | --- | --- | --- | --- |
| `fips203_mlkem.sage` | FIPS 203 | ML-KEM (Kyber) | 21 of 21 | 512, 768, 1024 |
| `fips204_mldsa.sage` | FIPS 204 | ML-DSA (Dilithium) | 49 of 49 | 44, 65, 87 |
| `fips205_slhdsa.sage` | FIPS 205 | SLH-DSA (SPHINCS+) | 25 of 25 | all 12 |
| `fips206_fndsa.sage` | FIPS 206 | FN-DSA (Falcon) | 18 of 18 | 512, 1024 |

`common.sage` holds the sponge functions shared by all four and the NIST
pre-hash OID arc used by FIPS 204 and FIPS 205.

The "Algorithms" column is not a claim, it is a test: every function is
annotated with its algorithm number, and `test_kat.sage` parses the files
and fails if any number in the standard's range is unaccounted for. That
covers 113 algorithms in total, including the ones the schemes never call
on the happy path — FIPS 204's `MontgomeryReduce` and `AddVectorNTT`, and
FIPS 203's two pseudocode-notation examples.

## Why SageMath

These are not bytes-only implementations with Sage bolted on. The
algebraic objects of each standard are genuine Sage objects, which makes
the structure visible and lets the hand-rolled transforms be checked
against the rings they claim to implement:

* **FIPS 203** carries the coefficient domain in `GF(3329)[X]/(X^256+1)`
  as a Sage quotient ring, and the NTT domain as a Sage vector over
  `GF(3329)`. `verify_ntt_is_a_ring_isomorphism()` confirms that the
  standard's butterfly network really is the Chinese-remainder map onto
  128 quadratic factors, and that `MultiplyNTTs` transports the product
  of `Rq` — using Sage's own ring multiplication as the oracle.
* **FIPS 204** does the same over `GF(8380417)`, and additionally checks
  that the NTT is evaluation at the 256 odd powers of ζ, and that
  `MontgomeryReduce` really computes `a · 2^-32 mod q`.
* **FIPS 205** has no algebra to check — it is pure hashing — so Sage
  contributes exact integer reasoning instead:
  `verify_parameter_consistency()` re-derives `len1`, `len2`, `m` and
  the key and signature sizes of Table 2 from the defining equations.
* **FIPS 206** runs the NTRU solver over Sage's exact `ZZ['x']`, so the
  trapdoor equation `f·G − g·F = q` is verified exactly rather than in
  floating point; recovers `h = g/f` in `GF(12289)[x]/(x^n+1)`; and runs
  the signing FFT over `CDF`, which *is* the IEEE 754 binary64 arithmetic
  that Falcon prescribes.

## Status of FIPS 206

NIST lists FIPS 206 as **in development**: as of this writing no initial
public draft has been published and no ACVP vectors exist. The
authoritative specification for FN-DSA is therefore still the round-3
Falcon submission (specification v1.2, 1 October 2020), and that is what
`fips206_fndsa.sage` implements, with Falcon's algorithm numbering. The
places most likely to be respecified by FIPS 206 — the key and signature
encodings, and the domain separation of the hashed message — are marked
`FIPS 206 note` in the source.

## Running the tests

```bash
./fetch_vectors.sh          # ~90 MB, once
sage test_kat.sage          # quick run over all four
sage test_kat.sage --full   # every available test vector
sage test_kat.sage 203 206  # only the named standards
```

or, from the book's `latex/` directory, `make kat` and `make kat-full`.

### What the vectors are

For FIPS 203, 204 and 205 the tests run against the NIST **ACVP**
`internalProjection.json` files, which carry both the inputs and the
expected outputs of every test case. Coverage is byte-exact:

| Standard | Vectors reproduced byte for byte |
| --- | --- |
| FIPS 203 | all 75 keyGen, all 75 encapsulation, all 30 decapsulation, all 60 key-check cases |
| FIPS 204 | all 75 keyGen, all 360 sigGen, all 180 sigVer — pure and pre-hash, external and internal interfaces, deterministic and hedged, external-μ |
| FIPS 205 | all 120 keyGen, all 504 sigVer, and at least one case from every one of the 72 sigGen groups — all 12 parameter sets, pure and pre-hash |

FIPS 206 has no NIST vectors, so FN-DSA is validated in four ways
against the Falcon round-3 submission:

1. `SamplerZ` reproduces all 16 test vectors of the Falcon
   specification's Table 3.2, exactly, byte for byte;
2. for each Falcon KAT key, the private key is decoded, `f·G − g·F = q`
   is checked exactly in `Z[x]/(x^n+1)`, and the recomputed `h = g/f`
   re-encodes to the KAT public key byte for byte;
3. every Falcon KAT signature verifies, and the same signature over a
   tampered message is rejected;
4. signatures produced by this implementation under a Falcon KAT private
   key verify under the corresponding KAT public key.

Signing itself cannot be locked to the KAT byte string: Falcon signing is
randomised, and the Falcon KATs were generated with the reference
implementation's own PRNG chain. Verification, which is deterministic, is
checked byte-exactly.

### Timing

Sage is not fast, and these are reference implementations chosen for
clarity. Rough figures on one core:

| Operation | Time |
| --- | --- |
| ML-KEM-768 keygen / encaps / decaps | ~40 ms each |
| ML-DSA-65 keygen / sign / verify | ~0.1 / ~0.5 / ~0.1 s |
| SLH-DSA-128f sign | ~1 s |
| SLH-DSA-128s sign | ~16 s |
| SLH-DSA-256s sign | ~33 s |
| SLH-DSA verify (any parameter set) | well under 1 s |
| FN-DSA-512 keygen (NTRU solver) | ~20 s |
| FN-DSA-512 sign / verify | ~0.2 s / ~0.02 s |

Signing an `s` parameter set means rebuilding whole XMSS trees, so one
case from each of the 36 `s` sigGen groups takes about 16 minutes in
total. The quick run therefore covers signature *generation* only for the
`f` sets and reports how many groups it left out; `--full` includes them.
Verification is cheap everywhere and is always checked in full.

## Namespace note

Each file mirrors one standard and so reuses that standard's own names —
`Rq`, `NTT`, `BitsToBytes`, `Compress` — which means the four cannot
share a single global namespace. Load one at a time:

```python
sage: load('fips203_mlkem.sage')
sage: kem = MLKEM('ML-KEM-768')
sage: ek, dk = kem.KeyGen()
sage: K, c = kem.Encaps(ek)
sage: kem.Decaps(dk, c) == K
True
```

To use several at once, load each into its own dictionary, as
`test_kat.sage` does:

```python
sage: import sage.all
sage: from sage.repl.load import load as sage_load
sage: ns = dict(sage.all.__dict__); sage_load('fips204_mldsa.sage', ns)
sage: dsa = ns['MLDSA']('ML-DSA-65')
```

## These are teaching implementations

They are written to be read, and they are byte-exact against the
standards' own test vectors — but they are **not** suitable for
production use. In particular they make no attempt at constant-time
behaviour: comparisons, table lookups, rejection loops and the Falcon
Gaussian sampler all branch on secret data. The book's Side-Channel
Security chapter discusses what a hardened implementation has to do
differently.

## References

* FIPS 203, *Module-Lattice-Based Key-Encapsulation Mechanism Standard*,
  NIST, August 2024.
* FIPS 204, *Module-Lattice-Based Digital Signature Standard*, NIST,
  August 2024.
* FIPS 205, *Stateless Hash-Based Digital Signature Standard*, NIST,
  August 2024.
* P.-A. Fouque et al., *Falcon: Fast-Fourier Lattice-based Compact
  Signatures over NTRU*, specification v1.2, 1 October 2020.
* NIST ACVP test vectors, <https://github.com/usnistgov/ACVP-Server>.
