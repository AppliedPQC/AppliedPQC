# Playground

Every algorithm in *Applied Post-Quantum Cryptography* has a SageMath
implementation, and the cells below run them **in your browser** — no install,
nothing to download. Edit any cell and press **Run**.

The code is not copied into this page. Each cell fetches the `.sage` sources
straight from [the repository](https://github.com/AppliedPQC/AppliedPQC/tree/main/sage),
so what runs here is exactly the code the book documents.

This page covers the four standards. Every other code listing in the book —
the lattices, LWE, NTT and toy-Kyber experiments the chapters build up from —
is runnable too: see **[code from the book](book-code.html)**.

Execution happens on the free [SageMath Cell](https://sagecell.sagemath.org/)
service, which allows **30 seconds per run**. Nearly everything fits; the few
operations that do not are noted below, with the command to run them locally.

## ML-KEM (FIPS 203)

Key generation, encapsulation and decapsulation at all three parameter sets.
The encapsulation and decapsulation keys agree on the shared secret, and the
sizes are the ones in FIPS 203 Table 3.

<div class="sage"><script type="text/x-sage">import urllib.request
exec(urllib.request.urlopen("https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py").read())
apqc_load('fips203')
for ps in ['ML-KEM-512', 'ML-KEM-768', 'ML-KEM-1024']:
    kem = MLKEM(ps)
    ek, dk = kem.KeyGen()          # Algorithm 16
    K, c = kem.Encaps(ek)          # Algorithm 17
    K2 = kem.Decaps(dk, c)         # Algorithm 18
    print("%-12s shared secret agrees: %s   ek %d B, ct %d B"
          % (ps, K2 == K, len(ek), len(c)))
</script></div>

The number-theoretic transform is a *ring isomorphism*, not merely a fast
multiplication trick. This check confirms all three parts of that claim using
Sage's own arithmetic as the oracle — it is the check discussed in the ML-KEM
chapter.

<div class="sage"><script type="text/x-sage">import urllib.request
exec(urllib.request.urlopen("https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py").read())
apqc_load('fips203')
print("NTT is a ring isomorphism:", verify_ntt_is_a_ring_isomorphism())
</script></div>

## ML-DSA (FIPS 204)

Signing uses Fiat–Shamir with aborts, so the number of rejection-loop
iterations varies from run to run. Public key and signature sizes match
FIPS 204 Table 2.

<div class="sage"><script type="text/x-sage">import urllib.request
exec(urllib.request.urlopen("https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py").read())
apqc_load('fips204')
for ps in ['ML-DSA-44', 'ML-DSA-65', 'ML-DSA-87']:
    dsa = MLDSA(ps)
    pk, sk = dsa.KeyGen()                        # Algorithm 1
    sig = dsa.Sign(sk, b"attack at dawn", b"")   # Algorithm 2
    ok = dsa.Verify(pk, b"attack at dawn", sig, b"")
    print("%-11s verifies: %s   pk %d B, sig %d B" % (ps, ok, len(pk), len(sig)))
</script></div>

## SLH-DSA (FIPS 205)

The `f` ("fast") parameter sets sign quickly enough to run here end to end.

<div class="sage"><script type="text/x-sage">import urllib.request
exec(urllib.request.urlopen("https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py").read())
apqc_load('fips205')
slh = SLHDSA('SLH-DSA-SHAKE-128f')
SK, PK = slh.slh_keygen()
sig = slh.slh_sign(b"hash-based signatures", b"", SK)
print("verifies:", slh.slh_verify(b"hash-based signatures", sig, b"", PK))
print("signature: %d bytes" % len(sig))
</script></div>

The `s` ("small") sets trade signing time for signature size, and signing them
takes far longer than 30 seconds. Verification, though, is the fast direction —
well under a second — so `apqc_demo_sig` supplies a signature from NIST's ACVP
vectors and the verifier does the rest. Note how much smaller these are than
the `f` signature above.

<div class="sage"><script type="text/x-sage">import urllib.request
exec(urllib.request.urlopen("https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py").read())
apqc_load('fips205')
for ps in ['SLH-DSA-SHAKE-128s', 'SLH-DSA-SHAKE-192s', 'SLH-DSA-SHAKE-256s']:
    pk, msg, sig = apqc_demo_sig(ps)
    ok = SLHDSA(ps).slh_verify_internal(msg, sig, pk)
    print("%-20s verifies: %s   signature %d B" % (ps, bool(ok), len(sig)))
</script></div>

## FN-DSA (FIPS 206, Falcon)

FIPS 206 is still in development, so this follows the round-3 Falcon
submission. Two checks run in well under a second: the Gaussian sampler
against Falcon's published test vectors, and the floating-point FFT against
exact arithmetic in the polynomial ring.

<div class="sage"><script type="text/x-sage">import urllib.request
exec(urllib.request.urlopen("https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py").read())
apqc_load('fips206')
print("SamplerZ matches Falcon's KAT:", verify_samplerz_kat())
print("FFT agrees with the exact ring:", verify_fft_against_exact_ring())
</script></div>

Falcon key generation runs the NTRU tower solver, which needs minutes rather
than seconds, so `apqc_demo_key` loads the round-3 KAT key instead. Signing and
verification with it are fast.

<div class="sage"><script type="text/x-sage">import urllib.request
exec(urllib.request.urlopen("https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py").read())
apqc_load('fips206')
sk, h = apqc_demo_key('FN-DSA-512')
fn = FNDSA('FN-DSA-512')
sig = fn.Sign(b"lattice signatures over NTRU", sk)
print("verifies:", fn.Verify(b"lattice signatures over NTRU", sig, h))
print("NTRU equation f*G - g*F = q holds:",
      verify_ntru_equation(sk['f'], sk['g'], sk['F'], sk['G']))
</script></div>

## What does not fit in a browser

Three things exceed the 30-second budget. `apqc_require` names them and says
what to run instead, rather than letting a cell die silently at the limit.

<div class="sage"><script type="text/x-sage">import urllib.request
exec(urllib.request.urlopen("https://raw.githubusercontent.com/AppliedPQC/AppliedPQC/main/sage/playground.py").read())
for op in ['FN-DSA-512.Keygen', 'FN-DSA-1024', 'SLH-DSA-s.sign', 'test_kat']:
    try:
        apqc_require(op)
    except RuntimeError as e:
        print(e); print()
</script></div>

To run everything without limits, including the full 462-check test suite
against NIST's ACVP vectors:

```sh
git clone https://github.com/AppliedPQC/AppliedPQC
cd AppliedPQC/sage
./fetch_vectors.sh
sage test_kat.sage
```
