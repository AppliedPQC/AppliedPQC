# =====================================================================
#  FIPS 205 -- SLH-DSA
#  Stateless Hash-Based Digital Signature Standard
#
#  A complete, byte-exact SageMath implementation.  Every one of the 25
#  numbered algorithms of FIPS 205 appears below as its own function,
#  named after the standard and annotated with its algorithm number, and
#  all 12 approved parameter sets are supported (SHA2 and SHAKE, at
#  security levels 128/192/256, in the "s" and "f" variants).
#
#  SLH-DSA has no algebraic structure to speak of -- it is built purely
#  from hash functions -- so unlike FIPS 203/204 there are no rings here.
#  What Sage contributes instead is exact integer reasoning about the
#  combinatorics: `verify_parameter_consistency()` at the end of this
#  file re-derives len1, len2, m, and the public-key and signature sizes
#  of Table 2 from the defining equations and checks them against the
#  published values.
#
#  Reference: FIPS 205, Stateless Hash-Based Digital Signature Standard,
#  NIST, August 2024.
# =====================================================================

load("common.sage")

import hmac as _hmac


# ---------------------------------------------------------------------
# Section 4.1.  Type constants for the address word.
# ---------------------------------------------------------------------

WOTS_HASH = 0
WOTS_PK = 1
TREE = 2
FORS_TREE = 3
FORS_ROOTS = 4
WOTS_PRF = 5
FORS_PRF = 6


# ---------------------------------------------------------------------
# Section 4.4.  Conversions between byte strings and integers.
# ---------------------------------------------------------------------

def toInt(X, n):
    r"""Algorithm 2.  Big-endian byte string to integer."""
    total = 0
    for i in range(int(n)):
        total = 256 * total + X[i]
    return total


def toByte(x, n):
    r"""Algorithm 3.  Integer to big-endian byte string of length n."""
    total = int(x)
    S = bytearray(int(n))
    for i in range(int(n)):
        S[int(n) - 1 - i] = total % 256
        total >>= 8
    return bytes(S)


def base_2b(X, b, out_len):
    r"""Algorithm 4.  The base-2^b representation of the first out_len*b bits."""
    b, out_len = int(b), int(out_len)
    inn = 0
    bits = 0
    total = 0
    baseb = [0] * out_len
    for out in range(out_len):
        while bits < b:
            total = (total << 8) + X[inn]
            inn += 1
            bits += 8
        bits -= b
        baseb[out] = (total >> bits) % (1 << b)
    return baseb


# ---------------------------------------------------------------------
# Section 4.2 / 4.3.  Addresses.
# ---------------------------------------------------------------------

class ADRS(object):
    r"""
    A 32-byte SLH-DSA address (Figure 2), with the member functions of
    Table 1.  Each setter returns `self` so that they chain, and `copy()`
    provides the "skADRS <- ADRS" copies the pseudocode calls for.

    `compressed()` produces the 22-byte ADRS_c of Figure 18, used by the
    SHA2 parameter sets:  ADRS[3] || ADRS[8:16] || ADRS[19] || ADRS[20:32].
    """

    def __init__(self, raw=None):
        self.a = bytearray(raw if raw is not None else toByte(0, 32))

    def copy(self):
        return ADRS(bytes(self.a))

    def bytes(self):
        return bytes(self.a)

    def compressed(self):
        return bytes(self.a[3:4] + self.a[8:16] + self.a[19:20] + self.a[20:32])

    def setLayerAddress(self, l):
        self.a[0:4] = toByte(l, 4)
        return self

    def setTreeAddress(self, t):
        self.a[4:16] = toByte(t, 12)
        return self

    def setTypeAndClear(self, Y):
        self.a[16:20] = toByte(Y, 4)
        self.a[20:32] = toByte(0, 12)
        return self

    def setKeyPairAddress(self, i):
        self.a[20:24] = toByte(i, 4)
        return self

    def setChainAddress(self, i):
        self.a[24:28] = toByte(i, 4)
        return self

    def setTreeHeight(self, i):
        self.a[24:28] = toByte(i, 4)
        return self

    def setHashAddress(self, i):
        self.a[28:32] = toByte(i, 4)
        return self

    def setTreeIndex(self, i):
        self.a[28:32] = toByte(i, 4)
        return self

    def getKeyPairAddress(self):
        return toInt(self.a[20:24], 4)

    def getTreeIndex(self):
        return toInt(self.a[28:32], 4)


# ---------------------------------------------------------------------
# Section 11.  Hash-function instantiations.
# ---------------------------------------------------------------------

def MGF1(hashfn, hlen, mgfSeed, maskLen):
    r"""
    MGF1 from RFC 8017 Appendix B.2.1, with `hashfn` as the hash.
    Used by H_msg in the SHA2 parameter sets (Sections 11.2.1, 11.2.2).
    """
    T = b""
    counter = 0
    while len(T) < maskLen:
        T += hashfn(bytes(mgfSeed) + toByte(counter, 4))
        counter += 1
    return T[:maskLen]


class ShakeHashSuite(object):
    r"""Section 11.1.  The SHAKE instantiation of H_msg, PRF, F, H, T_l."""

    def __init__(self, n, m):
        self.n, self.m = n, m

    def Hmsg(self, R, pkseed, pkroot, M):
        return SHAKE256(bytes(R) + bytes(pkseed) + bytes(pkroot) + bytes(M), self.m)

    def PRF(self, pkseed, skseed, adrs):
        return SHAKE256(bytes(pkseed) + adrs.bytes() + bytes(skseed), self.n)

    def PRFmsg(self, skprf, opt_rand, M):
        return SHAKE256(bytes(skprf) + bytes(opt_rand) + bytes(M), self.n)

    def F(self, pkseed, adrs, M1):
        return SHAKE256(bytes(pkseed) + adrs.bytes() + bytes(M1), self.n)

    def H(self, pkseed, adrs, M2):
        return SHAKE256(bytes(pkseed) + adrs.bytes() + bytes(M2), self.n)

    def T(self, pkseed, adrs, Ml):
        return SHAKE256(bytes(pkseed) + adrs.bytes() + bytes(Ml), self.n)


class Sha2HashSuite(object):
    r"""
    Sections 11.2.1 and 11.2.2.  The SHA2 instantiation.

    Security category 1 (n = 16) uses SHA-256 throughout; categories 3
    and 5 (n = 24, 32) keep SHA-256 for PRF and F but move H, T_l, and
    H_msg to SHA-512.
    """

    def __init__(self, n, m):
        self.n, self.m = n, m
        self.cat1 = (n == 16)
        # The zero paddings toByte(0, 64-n) and toByte(0, 128-n) are
        # constants; computing them once keeps the hot path to a single
        # concatenation, exactly as a real implementation would.
        self._pad256 = toByte(0, 64 - n)
        self._pad_big_bytes = toByte(0, (64 if self.cat1 else 128) - n)

    def _sha_big(self, data):
        return SHA256(data) if self.cat1 else SHA512(data)

    def Hmsg(self, R, pkseed, pkroot, M):
        inner = self._sha_big(bytes(R) + bytes(pkseed) + bytes(pkroot) + bytes(M))
        seed = bytes(R) + bytes(pkseed) + inner
        return MGF1(self._sha_big, 32 if self.cat1 else 64, seed, self.m)

    def PRF(self, pkseed, skseed, adrs):
        return SHA256(bytes(pkseed) + self._pad256
                      + adrs.compressed() + bytes(skseed))[:self.n]

    def PRFmsg(self, skprf, opt_rand, M):
        digestmod = 'sha256' if self.cat1 else 'sha512'
        return _hmac.new(bytes(skprf), bytes(opt_rand) + bytes(M),
                         digestmod).digest()[:self.n]

    def F(self, pkseed, adrs, M1):
        return SHA256(bytes(pkseed) + self._pad256
                      + adrs.compressed() + bytes(M1))[:self.n]

    def H(self, pkseed, adrs, M2):
        return self._sha_big(bytes(pkseed) + self._pad_big_bytes
                             + adrs.compressed() + bytes(M2))[:self.n]

    def T(self, pkseed, adrs, Ml):
        return self._sha_big(bytes(pkseed) + self._pad_big_bytes
                             + adrs.compressed() + bytes(Ml))[:self.n]


# ---------------------------------------------------------------------
# Section 5, Equation 5.3.
# ---------------------------------------------------------------------

def gen_len2(n, lgw):
    r"""Algorithm 1.  The number of checksum chains, len2."""
    w = 1 << int(lgw)
    len1 = (8 * int(n) + int(lgw) - 1) // int(lgw)
    max_checksum = len1 * (w - 1)
    len2 = 1
    capacity = w
    while capacity <= max_checksum:
        len2 += 1
        capacity *= w
    return len2


# ---------------------------------------------------------------------
# Section 11, Table 2.  Parameter sets.
# ---------------------------------------------------------------------

SLHDSA_PARAMS = {
    'SLH-DSA-SHA2-128s':  dict(n=16, h=63, d=7,  hp=9, a=12, k=14, lgw=4, m=30, hash='SHA2'),
    'SLH-DSA-SHAKE-128s': dict(n=16, h=63, d=7,  hp=9, a=12, k=14, lgw=4, m=30, hash='SHAKE'),
    'SLH-DSA-SHA2-128f':  dict(n=16, h=66, d=22, hp=3, a=6,  k=33, lgw=4, m=34, hash='SHA2'),
    'SLH-DSA-SHAKE-128f': dict(n=16, h=66, d=22, hp=3, a=6,  k=33, lgw=4, m=34, hash='SHAKE'),
    'SLH-DSA-SHA2-192s':  dict(n=24, h=63, d=7,  hp=9, a=14, k=17, lgw=4, m=39, hash='SHA2'),
    'SLH-DSA-SHAKE-192s': dict(n=24, h=63, d=7,  hp=9, a=14, k=17, lgw=4, m=39, hash='SHAKE'),
    'SLH-DSA-SHA2-192f':  dict(n=24, h=66, d=22, hp=3, a=8,  k=33, lgw=4, m=42, hash='SHA2'),
    'SLH-DSA-SHAKE-192f': dict(n=24, h=66, d=22, hp=3, a=8,  k=33, lgw=4, m=42, hash='SHAKE'),
    'SLH-DSA-SHA2-256s':  dict(n=32, h=64, d=8,  hp=8, a=14, k=22, lgw=4, m=47, hash='SHA2'),
    'SLH-DSA-SHAKE-256s': dict(n=32, h=64, d=8,  hp=8, a=14, k=22, lgw=4, m=47, hash='SHAKE'),
    'SLH-DSA-SHA2-256f':  dict(n=32, h=68, d=17, hp=4, a=9,  k=35, lgw=4, m=49, hash='SHA2'),
    'SLH-DSA-SHAKE-256f': dict(n=32, h=68, d=17, hp=4, a=9,  k=35, lgw=4, m=49, hash='SHAKE'),
}

# The pre-hash functions of Algorithms 23 and 25 (same OID arc as FIPS 204).
SLHDSA_PREHASH = NIST_PREHASH


class SLHDSA(object):
    r"""
    SLH-DSA at one of the 12 parameter sets of FIPS 205, Table 2.

        sage: slh = SLHDSA('SLH-DSA-SHAKE-128f')
        sage: SK, PK = slh.slh_keygen()
        sage: sig = slh.slh_sign(b"hello", b"", SK)
        sage: slh.slh_verify(b"hello", sig, b"", PK)
        True
    """

    def __init__(self, name='SLH-DSA-SHAKE-128f'):
        if name not in SLHDSA_PARAMS:
            raise ValueError("unknown parameter set %r" % (name,))
        self.name = name
        p = SLHDSA_PARAMS[name]
        self.n = p['n']
        self.h = p['h']
        self.d = p['d']
        self.hp = p['hp']            # h', the height of one XMSS tree
        self.a = p['a']
        self.k = p['k']
        self.lgw = p['lgw']
        self.m = p['m']

        # Equations 5.1 - 5.4.
        self.w = 1 << self.lgw
        self.len1 = (8 * self.n + self.lgw - 1) // self.lgw
        self.len2 = gen_len2(self.n, self.lgw)
        self.len = self.len1 + self.len2

        self.hashsuite = (ShakeHashSuite(self.n, self.m) if p['hash'] == 'SHAKE'
                          else Sha2HashSuite(self.n, self.m))

        self.pk_len = 2 * self.n
        self.sk_len = 4 * self.n
        self.sig_len = (1 + self.k * (1 + self.a) + self.h + self.d * self.len) * self.n

    # Shorthands for the hash family of Section 11.
    def _F(self, *args):
        return self.hashsuite.F(*args)

    def _H(self, *args):
        return self.hashsuite.H(*args)

    def _T(self, *args):
        return self.hashsuite.T(*args)

    def _PRF(self, *args):
        return self.hashsuite.PRF(*args)

    # ----------------------------- WOTS+ ------------------------------

    def chain(self, X, i, s, pkseed, adrs):
        r"""Algorithm 5.  Iterate F on X, s times, starting at chain step i."""
        tmp = bytes(X)
        for j in range(int(i), int(i) + int(s)):
            adrs.setHashAddress(j)
            tmp = self._F(pkseed, adrs, tmp)
        return tmp

    def wots_pkGen(self, skseed, pkseed, adrs):
        r"""Algorithm 6.  A WOTS+ public key."""
        skADRS = adrs.copy()
        skADRS.setTypeAndClear(WOTS_PRF)
        skADRS.setKeyPairAddress(adrs.getKeyPairAddress())
        tmp = b""
        for i in range(self.len):
            skADRS.setChainAddress(i)
            sk = self._PRF(pkseed, skseed, skADRS)
            adrs.setChainAddress(i)
            tmp += self.chain(sk, 0, self.w - 1, pkseed, adrs)
        wotspkADRS = adrs.copy()
        wotspkADRS.setTypeAndClear(WOTS_PK)
        wotspkADRS.setKeyPairAddress(adrs.getKeyPairAddress())
        return self._T(pkseed, wotspkADRS, tmp)

    def _wots_msg(self, M):
        r"""Lines 1-7 shared by Algorithms 7 and 8: message plus checksum."""
        msg = base_2b(M, self.lgw, self.len1)
        csum = 0
        for i in range(self.len1):
            csum += self.w - 1 - msg[i]
        csum <<= (8 - ((self.len2 * self.lgw) % 8)) % 8
        nbytes = (self.len2 * self.lgw + 7) // 8
        return msg + base_2b(toByte(csum, nbytes), self.lgw, self.len2)

    def wots_sign(self, M, skseed, pkseed, adrs):
        r"""Algorithm 7.  A WOTS+ signature on an n-byte message."""
        msg = self._wots_msg(M)
        skADRS = adrs.copy()
        skADRS.setTypeAndClear(WOTS_PRF)
        skADRS.setKeyPairAddress(adrs.getKeyPairAddress())
        sig = b""
        for i in range(self.len):
            skADRS.setChainAddress(i)
            sk = self._PRF(pkseed, skseed, skADRS)
            adrs.setChainAddress(i)
            sig += self.chain(sk, 0, msg[i], pkseed, adrs)
        return sig

    def wots_pkFromSig(self, sig, M, pkseed, adrs):
        r"""Algorithm 8.  Recover the WOTS+ public key from a signature."""
        msg = self._wots_msg(M)
        tmp = b""
        for i in range(self.len):
            adrs.setChainAddress(i)
            tmp += self.chain(sig[i * self.n:(i + 1) * self.n],
                              msg[i], self.w - 1 - msg[i], pkseed, adrs)
        wotspkADRS = adrs.copy()
        wotspkADRS.setTypeAndClear(WOTS_PK)
        wotspkADRS.setKeyPairAddress(adrs.getKeyPairAddress())
        return self._T(pkseed, wotspkADRS, tmp)

    # ------------------------------ XMSS ------------------------------

    def xmss_node(self, skseed, i, z, pkseed, adrs):
        r"""Algorithm 9.  The root of a Merkle subtree of WOTS+ public keys."""
        if z == 0:
            adrs.setTypeAndClear(WOTS_HASH)
            adrs.setKeyPairAddress(i)
            return self.wots_pkGen(skseed, pkseed, adrs)
        lnode = self.xmss_node(skseed, 2 * i, z - 1, pkseed, adrs)
        rnode = self.xmss_node(skseed, 2 * i + 1, z - 1, pkseed, adrs)
        adrs.setTypeAndClear(TREE)
        adrs.setTreeHeight(z)
        adrs.setTreeIndex(i)
        return self._H(pkseed, adrs, lnode + rnode)

    def xmss_sign(self, M, skseed, idx, pkseed, adrs):
        r"""Algorithm 10.  An XMSS signature: WOTS+ signature plus auth path."""
        AUTH = b""
        for j in range(self.hp):
            kk = (idx >> j) ^^ 1
            AUTH += self.xmss_node(skseed, kk, j, pkseed, adrs)
        adrs.setTypeAndClear(WOTS_HASH)
        adrs.setKeyPairAddress(idx)
        sig = self.wots_sign(M, skseed, pkseed, adrs)
        return sig + AUTH

    def xmss_pkFromSig(self, idx, SIG_XMSS, M, pkseed, adrs):
        r"""Algorithm 11.  Recover the XMSS root from a signature."""
        adrs.setTypeAndClear(WOTS_HASH)
        adrs.setKeyPairAddress(idx)
        sig = SIG_XMSS[:self.len * self.n]
        AUTH = SIG_XMSS[self.len * self.n:(self.len + self.hp) * self.n]
        node = self.wots_pkFromSig(sig, M, pkseed, adrs)

        adrs.setTypeAndClear(TREE)
        adrs.setTreeIndex(idx)
        for kk in range(self.hp):
            adrs.setTreeHeight(kk + 1)
            auth_k = AUTH[kk * self.n:(kk + 1) * self.n]
            if (idx >> kk) % 2 == 0:
                adrs.setTreeIndex(adrs.getTreeIndex() // 2)
                node = self._H(pkseed, adrs, node + auth_k)
            else:
                adrs.setTreeIndex((adrs.getTreeIndex() - 1) // 2)
                node = self._H(pkseed, adrs, auth_k + node)
        return node

    # ---------------------------- Hypertree ---------------------------

    def ht_sign(self, M, skseed, pkseed, idxtree, idxleaf):
        r"""Algorithm 12.  A hypertree signature: d chained XMSS signatures."""
        adrs = ADRS()
        adrs.setTreeAddress(idxtree)
        SIGtmp = self.xmss_sign(M, skseed, idxleaf, pkseed, adrs)
        SIG_HT = SIGtmp
        root = self.xmss_pkFromSig(idxleaf, SIGtmp, M, pkseed, adrs)
        for j in range(1, self.d):
            idxleaf = idxtree % (1 << self.hp)
            idxtree = idxtree >> self.hp
            adrs.setLayerAddress(j)
            adrs.setTreeAddress(idxtree)
            SIGtmp = self.xmss_sign(root, skseed, idxleaf, pkseed, adrs)
            SIG_HT += SIGtmp
            if j < self.d - 1:
                root = self.xmss_pkFromSig(idxleaf, SIGtmp, root, pkseed, adrs)
        return SIG_HT

    def ht_verify(self, M, SIG_HT, pkseed, idxtree, idxleaf, pkroot):
        r"""Algorithm 13.  Verify a hypertree signature."""
        adrs = ADRS()
        adrs.setTreeAddress(idxtree)
        width = (self.hp + self.len) * self.n
        SIGtmp = SIG_HT[:width]
        node = self.xmss_pkFromSig(idxleaf, SIGtmp, M, pkseed, adrs)
        for j in range(1, self.d):
            idxleaf = idxtree % (1 << self.hp)
            idxtree = idxtree >> self.hp
            adrs.setLayerAddress(j)
            adrs.setTreeAddress(idxtree)
            SIGtmp = SIG_HT[j * width:(j + 1) * width]
            node = self.xmss_pkFromSig(idxleaf, SIGtmp, node, pkseed, adrs)
        return node == pkroot

    # ------------------------------ FORS ------------------------------

    def fors_skGen(self, skseed, pkseed, adrs, idx):
        r"""Algorithm 14.  One FORS private-key value."""
        skADRS = adrs.copy()
        skADRS.setTypeAndClear(FORS_PRF)
        skADRS.setKeyPairAddress(adrs.getKeyPairAddress())
        skADRS.setTreeIndex(idx)
        return self._PRF(pkseed, skseed, skADRS)

    def fors_node(self, skseed, i, z, pkseed, adrs):
        r"""Algorithm 15.  The root of a Merkle subtree of FORS values."""
        if z == 0:
            sk = self.fors_skGen(skseed, pkseed, adrs, i)
            adrs.setTreeHeight(0)
            adrs.setTreeIndex(i)
            return self._F(pkseed, adrs, sk)
        lnode = self.fors_node(skseed, 2 * i, z - 1, pkseed, adrs)
        rnode = self.fors_node(skseed, 2 * i + 1, z - 1, pkseed, adrs)
        adrs.setTreeHeight(z)
        adrs.setTreeIndex(i)
        return self._H(pkseed, adrs, lnode + rnode)

    def fors_sign(self, md, skseed, pkseed, adrs):
        r"""Algorithm 16.  A FORS signature on the k*a-bit message digest."""
        SIG_FORS = b""
        indices = base_2b(md, self.a, self.k)
        for i in range(self.k):
            SIG_FORS += self.fors_skGen(skseed, pkseed, adrs,
                                        i * (1 << self.a) + indices[i])
            for j in range(self.a):
                s = (indices[i] >> j) ^^ 1
                SIG_FORS += self.fors_node(skseed,
                                           i * (1 << (self.a - j)) + s,
                                           j, pkseed, adrs)
        return SIG_FORS

    def fors_pkFromSig(self, SIG_FORS, md, pkseed, adrs):
        r"""Algorithm 17.  Recover the FORS public key from a signature."""
        indices = base_2b(md, self.a, self.k)
        root = b""
        stride = (self.a + 1) * self.n
        for i in range(self.k):
            sk = SIG_FORS[i * stride:i * stride + self.n]
            adrs.setTreeHeight(0)
            adrs.setTreeIndex(i * (1 << self.a) + indices[i])
            node = self._F(pkseed, adrs, sk)
            auth = SIG_FORS[i * stride + self.n:(i + 1) * stride]
            for j in range(self.a):
                adrs.setTreeHeight(j + 1)
                auth_j = auth[j * self.n:(j + 1) * self.n]
                if (indices[i] >> j) % 2 == 0:
                    adrs.setTreeIndex(adrs.getTreeIndex() // 2)
                    node = self._H(pkseed, adrs, node + auth_j)
                else:
                    adrs.setTreeIndex((adrs.getTreeIndex() - 1) // 2)
                    node = self._H(pkseed, adrs, auth_j + node)
            root += node
        forspkADRS = adrs.copy()
        forspkADRS.setTypeAndClear(FORS_ROOTS)
        forspkADRS.setKeyPairAddress(adrs.getKeyPairAddress())
        return self._T(pkseed, forspkADRS, root)

    # ----------------------- Section 9, internal ----------------------

    def slh_keygen_internal(self, skseed, skprf, pkseed):
        r"""Algorithm 18.  Deterministic key generation from the three seeds."""
        adrs = ADRS()
        adrs.setLayerAddress(self.d - 1)
        pkroot = self.xmss_node(skseed, 0, self.hp, pkseed, adrs)
        SK = bytes(skseed) + bytes(skprf) + bytes(pkseed) + pkroot
        PK = bytes(pkseed) + pkroot
        return SK, PK

    def _split_digest(self, digest):
        r"""Lines 6-10 of Algorithms 19 and 20: carve up the message digest."""
        ka = (self.k * self.a + 7) // 8
        t1 = (self.h - self.h // self.d + 7) // 8
        t2 = (self.h // self.d + 7) // 8
        md = digest[0:ka]
        tmp_idxtree = digest[ka:ka + t1]
        tmp_idxleaf = digest[ka + t1:ka + t1 + t2]
        idxtree = toInt(tmp_idxtree, t1) % (1 << (self.h - self.h // self.d))
        idxleaf = toInt(tmp_idxleaf, t2) % (1 << (self.h // self.d))
        return md, idxtree, idxleaf

    def slh_sign_internal(self, M, SK, addrnd=None):
        r"""
        Algorithm 19.  Sign the formatted message M.

        `addrnd` is the additional randomness of the hedged variant;
        passing None substitutes PK.seed, which is the deterministic
        variant of line 2.
        """
        n = self.n
        skseed, skprf, pkseed, pkroot = SK[0:n], SK[n:2 * n], SK[2 * n:3 * n], SK[3 * n:4 * n]
        adrs = ADRS()
        opt_rand = pkseed if addrnd is None else bytes(addrnd)
        R = self.hashsuite.PRFmsg(skprf, opt_rand, M)
        SIG = R

        digest = self.hashsuite.Hmsg(R, pkseed, pkroot, M)
        md, idxtree, idxleaf = self._split_digest(digest)

        adrs.setTreeAddress(idxtree)
        adrs.setTypeAndClear(FORS_TREE)
        adrs.setKeyPairAddress(idxleaf)
        SIG_FORS = self.fors_sign(md, skseed, pkseed, adrs)
        SIG += SIG_FORS

        PK_FORS = self.fors_pkFromSig(SIG_FORS, md, pkseed, adrs)
        SIG += self.ht_sign(PK_FORS, skseed, pkseed, idxtree, idxleaf)
        return SIG

    def slh_verify_internal(self, M, SIG, PK):
        r"""Algorithm 20.  Verify a signature on the formatted message M."""
        n = self.n
        if len(SIG) != self.sig_len:
            return False
        pkseed, pkroot = PK[0:n], PK[n:2 * n]
        adrs = ADRS()
        R = SIG[0:n]
        SIG_FORS = SIG[n:(1 + self.k * (1 + self.a)) * n]
        SIG_HT = SIG[(1 + self.k * (1 + self.a)) * n:]

        digest = self.hashsuite.Hmsg(R, pkseed, pkroot, M)
        md, idxtree, idxleaf = self._split_digest(digest)

        adrs.setTreeAddress(idxtree)
        adrs.setTypeAndClear(FORS_TREE)
        adrs.setKeyPairAddress(idxleaf)
        PK_FORS = self.fors_pkFromSig(SIG_FORS, md, pkseed, adrs)
        return self.ht_verify(PK_FORS, SIG_HT, pkseed, idxtree, idxleaf, pkroot)

    # ----------------------- Section 10, external ---------------------

    def slh_keygen(self, rbg=None):
        r"""Algorithm 21.  slh_keygen()."""
        if rbg is None:
            import os
            rbg = os.urandom
        skseed, skprf, pkseed = rbg(self.n), rbg(self.n), rbg(self.n)
        if skseed is None or skprf is None or pkseed is None:
            raise RuntimeError("random bit generation failure")
        return self.slh_keygen_internal(skseed, skprf, pkseed)

    def slh_sign(self, M, ctx, SK, deterministic=False, rbg=None):
        r"""Algorithm 22.  slh_sign(M, ctx, SK), the pure variant."""
        if len(ctx) > 255:
            raise ValueError("context string longer than 255 bytes")
        if deterministic:
            addrnd = None
        else:
            if rbg is None:
                import os
                rbg = os.urandom
            addrnd = rbg(self.n)
        Mprime = toByte(0, 1) + toByte(len(ctx), 1) + bytes(ctx) + bytes(M)
        return self.slh_sign_internal(Mprime, SK, addrnd)

    def hash_slh_sign(self, M, ctx, PH, SK, deterministic=False, rbg=None):
        r"""Algorithm 23.  hash_slh_sign(M, ctx, PH, SK), the pre-hash variant."""
        if len(ctx) > 255:
            raise ValueError("context string longer than 255 bytes")
        if deterministic:
            addrnd = None
        else:
            if rbg is None:
                import os
                rbg = os.urandom
            addrnd = rbg(self.n)
        oid, ph = SLHDSA_PREHASH[PH]
        Mprime = toByte(1, 1) + toByte(len(ctx), 1) + bytes(ctx) + oid + ph(bytes(M))
        return self.slh_sign_internal(Mprime, SK, addrnd)

    def slh_verify(self, M, SIG, ctx, PK):
        r"""Algorithm 24.  slh_verify(M, SIG, ctx, PK)."""
        if len(ctx) > 255:
            return False
        Mprime = toByte(0, 1) + toByte(len(ctx), 1) + bytes(ctx) + bytes(M)
        return self.slh_verify_internal(Mprime, SIG, PK)

    def hash_slh_verify(self, M, SIG, ctx, PH, PK):
        r"""Algorithm 25.  hash_slh_verify(M, SIG, ctx, PH, PK)."""
        if len(ctx) > 255:
            return False
        oid, ph = SLHDSA_PREHASH[PH]
        Mprime = toByte(1, 1) + toByte(len(ctx), 1) + bytes(ctx) + oid + ph(bytes(M))
        return self.slh_verify_internal(Mprime, SIG, PK)


# ---------------------------------------------------------------------
# Consistency of Table 2, re-derived with Sage's exact integer arithmetic.
# ---------------------------------------------------------------------

# The published public-key and signature sizes of Table 2, in bytes.
SLHDSA_TABLE2_SIZES = {
    'SLH-DSA-SHA2-128s': (32, 7856),   'SLH-DSA-SHAKE-128s': (32, 7856),
    'SLH-DSA-SHA2-128f': (32, 17088),  'SLH-DSA-SHAKE-128f': (32, 17088),
    'SLH-DSA-SHA2-192s': (48, 16224),  'SLH-DSA-SHAKE-192s': (48, 16224),
    'SLH-DSA-SHA2-192f': (48, 35664),  'SLH-DSA-SHAKE-192f': (48, 35664),
    'SLH-DSA-SHA2-256s': (64, 29792),  'SLH-DSA-SHAKE-256s': (64, 29792),
    'SLH-DSA-SHA2-256f': (64, 49856),  'SLH-DSA-SHAKE-256f': (64, 49856),
}


def verify_parameter_consistency():
    r"""
    Check every parameter set of Table 2 against the defining equations.

      1. h = d * h', so the hypertree really has 2^h leaves;
      2. len2 from Algorithm 1 agrees with the closed form
         floor(log_w(len1 * (w-1))) + 1, computed exactly in Sage;
      3. m is large enough to supply the FORS digest and both indices:
         m >= ceil(k*a/8) + ceil((h - h/d)/8) + ceil(h/(8d));
      4. the public-key and signature sizes match the published values.
    """
    for name, p in SLHDSA_PARAMS.items():
        n, h, d, hp = p['n'], p['h'], p['d'], p['hp']
        a, k, lgw, m = p['a'], p['k'], p['lgw'], p['m']
        w = 1 << lgw

        assert h == d * hp, "%s: h != d*h'" % name

        len1 = (8 * n + lgw - 1) // lgw
        len2 = gen_len2(n, lgw)
        closed = Integer(len1 * (w - 1)).exact_log(w) + 1
        assert len2 == closed, "%s: len2 mismatch (%s vs %s)" % (name, len2, closed)

        need = ((k * a + 7) // 8 + (h - h // d + 7) // 8 + (h // d + 7) // 8)
        assert m >= need, "%s: m too small (%s < %s)" % (name, m, need)

        slh = SLHDSA(name)
        pk_bytes, sig_bytes = SLHDSA_TABLE2_SIZES[name]
        assert slh.pk_len == pk_bytes, "%s: pk size %s != %s" % (name, slh.pk_len, pk_bytes)
        assert slh.sig_len == sig_bytes, "%s: sig size %s != %s" % (name, slh.sig_len, sig_bytes)
    return True
