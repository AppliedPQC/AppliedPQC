# =====================================================================
#  test_kat.sage -- known-answer tests for the FIPS 203/204/205/206
#                   SageMath implementations.
#
#  Usage (from this directory):
#
#      sage test_kat.sage                 quick run over all four
#      sage test_kat.sage --full          every available test vector
#      sage test_kat.sage 203 206         only the named standards
#
#  Test vectors are not stored in the repository; run ./fetch_vectors.sh
#  once to download them into vectors/.
#
#  Sources:
#    * FIPS 203/204/205 -- the NIST ACVP "internalProjection" files from
#      github.com/usnistgov/ACVP-Server, which carry both the inputs and
#      the expected outputs of every test case.
#    * FIPS 206 -- NIST has published no draft and no vectors, so FN-DSA
#      is checked against the round-3 Falcon submission's own KAT files
#      plus the SamplerZ test vectors of the Falcon specification.
# =====================================================================

import json
import os
import sys
import time

import sage.all
from sage.repl.load import load as _sage_load

# Sage runs a preparsed copy of this file from a temporary directory, so
# __file__ is useless here; sys.argv[0] still holds the original path.
HERE = os.path.dirname(os.path.abspath(sys.argv[0]))
VECTORS = os.path.join(HERE, 'vectors')


def load_scheme(filename):
    r"""
    Load one of the scheme files into its own namespace.

    Each file mirrors a single standard and therefore reuses the natural
    names of that standard (`Rq`, `NTT`, `BitsToBytes`, ...), so the four
    cannot share one global namespace.  Loading each into a private dict
    keeps them side by side without collisions.
    """
    ns = dict(sage.all.__dict__)
    _sage_load(os.path.join(HERE, filename), ns)
    return ns


def vectors(name):
    path = os.path.join(VECTORS, name)
    if not os.path.exists(path):
        raise SystemExit(
            "missing test vectors: %s\nRun ./fetch_vectors.sh first." % path)
    return path


def algorithm_coverage(filename, total):
    r"""
    Confirm that every numbered algorithm of a standard has a function.

    Each implementation annotates its functions with the standard's own
    algorithm numbers ("Algorithm 13.  K-PKE.KeyGen(d) ..."), so the
    claim that nothing is missing can be checked mechanically rather
    than asserted.  Returns (found, missing).
    """
    import re
    text = open(os.path.join(HERE, filename)).read()
    found = set(int(m) for m in re.findall(r'Algorithm (\d+)[.\s]', text))
    wanted = set(range(1, int(total) + 1))
    return sorted(found & wanted), sorted(wanted - found)


class Report(object):
    r"""Accumulates pass/fail counts and prints a per-group progress line."""

    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.t0 = time.time()

    def group(self, label, ok, total, elapsed):
        self.passed += ok
        self.failed += total - ok
        flag = "ok  " if ok == total else "FAIL"
        print("    %s %-42s %4d/%-4d  %6.1fs" % (flag, label, ok, total, elapsed))
        sys.stdout.flush()

    def check(self, label, condition):
        if condition:
            self.passed += 1
            print("    ok   %s" % label)
        else:
            self.failed += 1
            print("    FAIL %s" % label)
        sys.stdout.flush()


# ---------------------------------------------------------------------
# FIPS 203 -- ML-KEM
# ---------------------------------------------------------------------

def test_fips203(rep, full):
    print("FIPS 203  ML-KEM")
    found, missing = algorithm_coverage('fips203_mlkem.sage', 21)
    rep.check("all 21 numbered algorithms implemented (missing: %s)"
              % (missing or "none"), not missing)
    M = load_scheme('fips203_mlkem.sage')
    MLKEM = M['MLKEM']

    rep.check("NTT is a ring isomorphism Rq -> Tq (checked with Sage)",
              M['verify_ntt_is_a_ring_isomorphism'](trials=3))

    V = json.load(open(vectors('ML-KEM-keyGen-FIPS203.json')))
    for g in V['testGroups']:
        kem = MLKEM(g['parameterSet'])
        tests = g['tests'] if full else g['tests'][:5]
        t0, ok = time.time(), 0
        for tc in tests:
            ek, dk = kem.KeyGen_internal(bytes.fromhex(tc['d']), bytes.fromhex(tc['z']))
            if (ek.hex().upper() == tc['ek'].upper()
                    and dk.hex().upper() == tc['dk'].upper()):
                ok += 1
        rep.group("%s keyGen" % g['parameterSet'], ok, len(tests), time.time() - t0)

    V = json.load(open(vectors('ML-KEM-encapDecap-FIPS203.json')))
    for g in V['testGroups']:
        kem = MLKEM(g['parameterSet'])
        fn = g['function']
        tests = g['tests'] if full else g['tests'][:5]
        t0, ok = time.time(), 0
        for tc in tests:
            if fn == 'encapsulation':
                K, c = kem.Encaps_internal(bytes.fromhex(tc['ek']),
                                           bytes.fromhex(tc['m']))
                ok += int(c.hex().upper() == tc['c'].upper()
                          and K.hex().upper() == tc['k'].upper())
            elif fn == 'decapsulation':
                K = kem.Decaps_internal(bytes.fromhex(tc['dk']),
                                        bytes.fromhex(tc['c']))
                ok += int(K.hex().upper() == tc['k'].upper())
            elif fn == 'encapsulationKeyCheck':
                try:
                    kem.check_encapsulation_key(bytes.fromhex(tc['ek']))
                    got = True
                except ValueError:
                    got = False
                ok += int(got == tc['testPassed'])
            elif fn == 'decapsulationKeyCheck':
                try:
                    kem.check_decapsulation_key(bytes.fromhex(tc['dk']))
                    got = True
                except ValueError:
                    got = False
                ok += int(got == tc['testPassed'])
        rep.group("%s %s" % (g['parameterSet'], fn), ok, len(tests), time.time() - t0)

    kem = MLKEM('ML-KEM-768')
    ek, dk = kem.KeyGen()
    K, c = kem.Encaps(ek)
    rep.check("ML-KEM-768 KeyGen/Encaps/Decaps round trip", kem.Decaps(dk, c) == K)


# ---------------------------------------------------------------------
# FIPS 204 -- ML-DSA
# ---------------------------------------------------------------------

def _mldsa_message(M, g, tc):
    r"""Build M' for a test group: pure, pre-hash, or already internal."""
    IntegerToBytes = M['IntegerToBytes']
    ctx = bytes.fromhex(tc.get('context', '') or '')
    msg = bytes.fromhex(tc.get('message', '') or '')
    if g.get('signatureInterface') == 'internal':
        return msg
    if g.get('preHash') == 'preHash':
        oid, ph = M['MLDSA_PREHASH'][tc['hashAlg']]
        return (IntegerToBytes(1, 1) + IntegerToBytes(len(ctx), 1)
                + ctx + oid + ph(msg))
    return IntegerToBytes(0, 1) + IntegerToBytes(len(ctx), 1) + ctx + msg


def test_fips204(rep, full):
    print("FIPS 204  ML-DSA")
    found, missing = algorithm_coverage('fips204_mldsa.sage', 49)
    rep.check("all 49 numbered algorithms implemented (missing: %s)"
              % (missing or "none"), not missing)
    M = load_scheme('fips204_mldsa.sage')
    MLDSA = M['MLDSA']

    rep.check("NTT is evaluation at the odd powers of zeta; MontgomeryReduce",
              M['verify_ntt_is_a_ring_isomorphism'](trials=2))

    V = json.load(open(vectors('ML-DSA-keyGen-FIPS204.json')))
    for g in V['testGroups']:
        d = MLDSA(g['parameterSet'])
        tests = g['tests'] if full else g['tests'][:5]
        t0, ok = time.time(), 0
        for tc in tests:
            pk, sk = d.KeyGen_internal(bytes.fromhex(tc['seed']))
            ok += int(pk.hex().upper() == tc['pk'].upper()
                      and sk.hex().upper() == tc['sk'].upper())
        rep.group("%s keyGen" % g['parameterSet'], ok, len(tests), time.time() - t0)

    V = json.load(open(vectors('ML-DSA-sigGen-FIPS204.json')))
    for g in V['testGroups']:
        d = MLDSA(g['parameterSet'])
        tests = g['tests'] if full else g['tests'][:2]
        t0, ok = time.time(), 0
        for tc in tests:
            rnd = bytes(32) if g['deterministic'] else bytes.fromhex(tc['rnd'])
            mu = bytes.fromhex(tc['mu']) if g.get('externalMu') else None
            sig = d.Sign_internal(bytes.fromhex(tc['sk']),
                                  _mldsa_message(M, g, tc), rnd, mu=mu)
            ok += int(sig.hex().upper() == tc['signature'].upper())
        rep.group("%s sigGen %s/%s%s" % (g['parameterSet'], g['signatureInterface'],
                                         g['preHash'],
                                         " extMu" if g.get('externalMu') else ""),
                  ok, len(tests), time.time() - t0)

    V = json.load(open(vectors('ML-DSA-sigVer-FIPS204.json')))
    for g in V['testGroups']:
        d = MLDSA(g['parameterSet'])
        tests = g['tests'] if full else g['tests'][:5]
        t0, ok = time.time(), 0
        for tc in tests:
            mu = bytes.fromhex(tc['mu']) if g.get('externalMu') else None
            got = d.Verify_internal(bytes.fromhex(tc['pk']),
                                    _mldsa_message(M, g, tc),
                                    bytes.fromhex(tc['signature']), mu=mu)
            ok += int(bool(got) == bool(tc['testPassed']))
        rep.group("%s sigVer %s/%s%s" % (g['parameterSet'], g['signatureInterface'],
                                         g['preHash'],
                                         " extMu" if g.get('externalMu') else ""),
                  ok, len(tests), time.time() - t0)

    d = MLDSA('ML-DSA-44')
    pk, sk = d.KeyGen()
    rep.check("ML-DSA-44 KeyGen/Sign/Verify round trip",
              d.Verify(pk, b"round trip", d.Sign(sk, b"round trip", b"ctx"), b"ctx"))


# ---------------------------------------------------------------------
# FIPS 205 -- SLH-DSA
# ---------------------------------------------------------------------

def _slhdsa_message(M, g, tc):
    toByte = M['toByte']
    ctx = bytes.fromhex(tc.get('context', '') or '')
    msg = bytes.fromhex(tc.get('message', '') or '')
    if g.get('signatureInterface') == 'internal':
        return msg
    if g.get('preHash') == 'preHash':
        oid, ph = M['SLHDSA_PREHASH'][tc['hashAlg']]
        return toByte(1, 1) + toByte(len(ctx), 1) + ctx + oid + ph(msg)
    return toByte(0, 1) + toByte(len(ctx), 1) + ctx + msg


def test_fips205(rep, full):
    print("FIPS 205  SLH-DSA")
    found, missing = algorithm_coverage('fips205_slhdsa.sage', 25)
    rep.check("all 25 numbered algorithms implemented (missing: %s)"
              % (missing or "none"), not missing)
    M = load_scheme('fips205_slhdsa.sage')
    SLHDSA = M['SLHDSA']

    rep.check("Table 2 parameter sets re-derived from the defining equations",
              M['verify_parameter_consistency']())

    V = json.load(open(vectors('SLH-DSA-keyGen-FIPS205.json')))
    for g in V['testGroups']:
        s = SLHDSA(g['parameterSet'])
        tests = g['tests'] if full else g['tests'][:1]
        t0, ok = time.time(), 0
        for tc in tests:
            SK, PK = s.slh_keygen_internal(bytes.fromhex(tc['skSeed']),
                                           bytes.fromhex(tc['skPrf']),
                                           bytes.fromhex(tc['pkSeed']))
            ok += int(SK.hex().upper() == tc['sk'].upper()
                      and PK.hex().upper() == tc['pk'].upper())
        rep.group("%s keyGen" % g['parameterSet'], ok, len(tests), time.time() - t0)

    # Signing the "s" (small-signature) parameter sets means rebuilding
    # whole XMSS trees and takes minutes per signature in Sage, so the
    # quick run covers only the "f" sets.  Nothing is silently skipped:
    # the omitted groups are reported below.
    V = json.load(open(vectors('SLH-DSA-sigGen-FIPS205.json')))
    skipped = 0
    for g in V['testGroups']:
        if not full and not g['parameterSet'].endswith('f'):
            skipped += 1
            continue
        s = SLHDSA(g['parameterSet'])
        tests = g['tests'] if full else g['tests'][:1]
        t0, ok = time.time(), 0
        for tc in tests:
            addrnd = (None if g['deterministic']
                      else bytes.fromhex(tc['additionalRandomness']))
            sig = s.slh_sign_internal(_slhdsa_message(M, g, tc),
                                      bytes.fromhex(tc['sk']), addrnd)
            ok += int(sig.hex().upper() == tc['signature'].upper())
        rep.group("%s sigGen %s/%s" % (g['parameterSet'], g['signatureInterface'],
                                       g['preHash']),
                  ok, len(tests), time.time() - t0)
    if skipped:
        print("    note %d sigGen groups for the slow 's' parameter sets were "
              "skipped; use --full to include them." % skipped)

    V = json.load(open(vectors('SLH-DSA-sigVer-FIPS205.json')))
    for g in V['testGroups']:
        s = SLHDSA(g['parameterSet'])
        tests = g['tests'] if full else g['tests'][:5]
        t0, ok = time.time(), 0
        for tc in tests:
            got = s.slh_verify_internal(_slhdsa_message(M, g, tc),
                                        bytes.fromhex(tc['signature']),
                                        bytes.fromhex(tc['pk']))
            ok += int(bool(got) == bool(tc['testPassed']))
        rep.group("%s sigVer %s/%s" % (g['parameterSet'], g['signatureInterface'],
                                       g['preHash']),
                  ok, len(tests), time.time() - t0)

    s = SLHDSA('SLH-DSA-SHAKE-128f')
    SK, PK = s.slh_keygen()
    rep.check("SLH-DSA-SHAKE-128f keygen/sign/verify round trip",
              s.slh_verify(b"round trip", s.slh_sign(b"round trip", b"", SK), b"", PK))


# ---------------------------------------------------------------------
# FIPS 206 -- FN-DSA
# ---------------------------------------------------------------------

def _parse_falcon_kat(path, limit=None):
    recs, cur = [], {}
    for line in open(path):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        k, _, v = line.partition(' = ')
        cur[k] = v
        if k == 'sm':
            recs.append(cur)
            cur = {}
            if limit and len(recs) >= limit:
                break
    return recs


def test_fips206(rep, full):
    print("FIPS 206  FN-DSA  (no NIST draft yet: checked against Falcon round 3)")
    found, missing = algorithm_coverage('fips206_fndsa.sage', 18)
    rep.check("all 18 numbered Falcon algorithms implemented (missing: %s)"
              % (missing or "none"), not missing)
    M = load_scheme('fips206_fndsa.sage')
    FNDSA = M['FNDSA']

    rep.check("FFT over CDF agrees with exact arithmetic in Z[x]/(x^n+1)",
              M['verify_fft_against_exact_ring'](n=128, trials=3))
    rep.check("SamplerZ matches the 16 test vectors of Falcon Table 3.2",
              M['verify_samplerz_kat']())

    for name, katfile in [('FN-DSA-512', 'falcon512-KAT.rsp'),
                          ('FN-DSA-1024', 'falcon1024-KAT.rsp')]:
        fn = FNDSA(name)
        recs = _parse_falcon_kat(vectors(katfile), limit=None if full else 3)

        t0, ok = time.time(), 0
        for r in recs:
            pk = bytes.fromhex(r['pk'])
            f, g, F, G = fn.decode_private_key(bytes.fromhex(r['sk']))
            good = M['verify_ntru_equation'](f, g, F, G)
            h = fn.public_from_fg(f, g)
            ok += int(good and fn.encode_public_key(h) == pk
                      and fn.decode_public_key(pk) == h)
        rep.group("%s KAT keys: f*G-g*F=q and h=g/f match pk" % name,
                  ok, len(recs), time.time() - t0)

        t0, ok = time.time(), 0
        for r in recs:
            h = fn.decode_public_key(bytes.fromhex(r['pk']))
            sm = bytes.fromhex(r['sm'])
            mlen = int(r['mlen'])
            siglen = int.from_bytes(sm[0:2], 'big')
            salt, msg, sigval = sm[2:42], sm[42:42 + mlen], sm[42 + mlen:]
            if len(sigval) != siglen or sigval[0] != 0x20 + fn.logn:
                continue
            s = sigval[1:].ljust(fn.slen // 8, b'\x00')   # KAT sigs are unpadded
            ok += int(fn.Verify(msg, (salt, s), h)
                      and not fn.Verify(msg + b'!', (salt, s), h))
        rep.group("%s KAT signatures verify (tampered rejected)" % name,
                  ok, len(recs), time.time() - t0)

        # The NIST aggregate format of Section 3.11.6, which is what the
        # KAT "sm" field holds.  Reference signatures are unpadded, so
        # this also exercises the pad-tolerant path in open_nist.
        t0, ok = time.time(), 0
        for r in recs:
            h = fn.decode_public_key(bytes.fromhex(r['pk']))
            sm = bytes.fromhex(r['sm'])
            good = fn.open_nist(sm, h) == bytes.fromhex(r['msg'])
            bad_sig = bytearray(sm)
            bad_sig[-40] = int(bad_sig[-40]) ^^ 0x40
            bad_msg = bytearray(sm)
            bad_msg[45] = int(bad_msg[45]) ^^ 0x01
            ok += int(good
                      and fn.open_nist(bytes(bad_sig), h) is None
                      and fn.open_nist(bytes(bad_msg), h) is None)
        rep.group("%s KAT aggregate format (open_nist, tampering rejected)" % name,
                  ok, len(recs), time.time() - t0)

        t0, ok = time.time(), 0
        n_own = len(recs) if full else 2
        for r in recs[:n_own]:
            h = fn.decode_public_key(bytes.fromhex(r['pk']))
            f, g, F, G = fn.decode_private_key(bytes.fromhex(r['sk']))
            sk, h2 = fn._complete_key(f, g, F, G)
            msg = b"signed with a Falcon KAT private key"
            ok += int(h2 == h and fn.Verify(msg, fn.Sign(msg, sk), h))
        rep.group("%s signing with KAT keys verifies under KAT pk" % name,
                  ok, n_own, time.time() - t0)

    fn = FNDSA('FN-DSA-512')
    sk, h = fn.Keygen()
    rep.check("FN-DSA-512 Keygen: f*G - g*F = q holds exactly",
              M['verify_ntru_equation'](sk['f'], sk['g'], sk['F'], sk['G']))
    rep.check("FN-DSA-512 Keygen/Sign/Verify round trip",
              fn.Verify(b"round trip", fn.Sign(b"round trip", sk), h))


# ---------------------------------------------------------------------

TESTS = {'203': test_fips203, '204': test_fips204,
         '205': test_fips205, '206': test_fips206}


def main(argv):
    full = '--full' in argv
    wanted = [a for a in argv if a in TESTS] or sorted(TESTS)
    rep = Report()
    print("=" * 74)
    print("FIPS 203/204/205/206 known-answer tests  (%s run)"
          % ("full" if full else "quick"))
    print("=" * 74)
    for key in wanted:
        TESTS[key](rep, full)
        print("")
    print("=" * 74)
    print("passed %d, failed %d, elapsed %.0fs"
          % (rep.passed, rep.failed, time.time() - rep.t0))
    print("=" * 74)
    return 1 if rep.failed else 0


sys.exit(main(sys.argv[1:]))
