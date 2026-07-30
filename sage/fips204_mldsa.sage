# =====================================================================
#  FIPS 204 -- ML-DSA
#  Module-Lattice-Based Digital Signature Standard
#
#  A complete, byte-exact SageMath implementation.  Every one of the 49
#  numbered algorithms of FIPS 204 appears below as its own function,
#  named after the standard and annotated with its algorithm number.
#
#  Algebraic objects are genuine Sage objects:
#
#      *  Rq = GF(8380417)[X]/(X^256 + 1) is a Sage quotient ring, and
#         carries every polynomial that is reduced modulo q;
#      *  Tq, the NTT domain, is the product ring (Z_q)^256, carried as a
#         Sage vector over GF(q); its product is coordinatewise, which is
#         exactly Algorithm 45;
#      *  polynomials of R with a restricted integer coefficient range
#         (t1, w1, h, r0) stay integer lists, as the standard requires --
#         FIPS 204 is careful to distinguish R from R_q, and so is this.
#
#  `verify_ntt_is_a_ring_isomorphism()` at the end of this file checks
#  the transform against Sage's own arithmetic in Rq.
#
#  Reference: FIPS 204, Module-Lattice-Based Digital Signature Standard,
#  NIST, August 2024.
# =====================================================================

load("common.sage")

# ---------------------------------------------------------------------
# Sections 2.5 and 4.  Rings and constants.
# ---------------------------------------------------------------------

MLDSA_n = 256
MLDSA_q = 8380417                  # 2^23 - 2^13 + 1
MLDSA_zeta = 1753                  # a 512-th root of unity modulo q
MLDSA_d = 13                       # dropped bits of t

Fq = GF(MLDSA_q)
Rx = PolynomialRing(Fq, 'X')
X = Rx.gen()
Rq = Rx.quotient(X ^ MLDSA_n + 1, 'x')   # R_q = Z_q[X]/(X^256+1)
Tq = VectorSpace(Fq, MLDSA_n)            # the product ring (Z_q)^256


def bitlen(x):
    r"""The bit length of a nonnegative integer; bitlen(0) = 0."""
    return int(x).bit_length()


def mod_pm(m, a):
    r"""
    Section 2.3: m mod+- a, the representative m' congruent to m modulo a
    with -ceil(a/2) < m' <= floor(a/2).
    """
    m, a = int(m), int(a)
    r = m % a
    return r - a if r > a // 2 else r


def _coeffs(f):
    r"""The 256 coefficients of an element of `Rq`, as integers in [0,q)."""
    c = [int(v) for v in f.lift()]
    return c + [0] * (MLDSA_n - len(c))


def centered(f):
    r"""The coefficients of an element of `Rq` reduced mod+- q."""
    return [mod_pm(c, MLDSA_q) for c in _coeffs(f)]


def inf_norm(f):
    r"""||f||_inf for an element of `Rq` (Section 2.3)."""
    return max(abs(c) for c in centered(f))


def inf_norm_vec(v):
    r"""||v||_inf for a vector of elements of `Rq`."""
    return max(inf_norm(f) for f in v)


def inf_norm_ints(w):
    r"""||w||_inf for a vector of integer polynomials."""
    return max(max(abs(int(c)) for c in p) for p in w)


# ---------------------------------------------------------------------
# Section 3.7.  The XOF wrappers H (SHAKE256) and G (SHAKE128).
# ---------------------------------------------------------------------

def H(s, ell):
    r"""H(str, l) = SHAKE256(str, 8l)."""
    return SHAKE256(s, ell)


def G(s, ell):
    r"""G(str, l) = SHAKE128(str, 8l)."""
    return SHAKE128(s, ell)


# ---------------------------------------------------------------------
# Section 7.1.  Conversion between data types.
# ---------------------------------------------------------------------

def IntegerToBits(x, alpha):
    r"""Algorithm 9.  Little-endian base-2 expansion of x mod 2^alpha."""
    x = int(x)
    y = [0] * int(alpha)
    for i in range(int(alpha)):
        y[i] = x & 1
        x >>= 1
    return y


def BitsToInteger(y, alpha):
    r"""Algorithm 10.  The integer with little-endian bit string y."""
    x = 0
    for i in range(1, int(alpha) + 1):
        x = 2 * x + int(y[int(alpha) - i])
    return x


def IntegerToBytes(x, alpha):
    r"""Algorithm 11.  Little-endian base-256 expansion of x mod 256^alpha."""
    x = int(x)
    y = bytearray(int(alpha))
    for i in range(int(alpha)):
        y[i] = x % 256
        x //= 256
    return bytes(y)


def BitsToBytes(y):
    r"""Algorithm 12.  Pack a bit string into bytes, little-endian."""
    z = bytearray((len(y) + 7) // 8)
    for i in range(len(y)):
        z[i // 8] |= int(y[i]) << (i % 8)
    return bytes(z)


def BytesToBits(z):
    r"""Algorithm 13.  Unpack a byte string into bits, little-endian."""
    y = []
    for byte in bytes(z):
        v = byte
        for _ in range(8):
            y.append(v & 1)
            v >>= 1
    return y


def CoeffFromThreeBytes(b0, b1, b2):
    r"""Algorithm 14.  An element of Z_q from three bytes, or None for bot."""
    b2p = int(b2)
    if b2p > 127:
        b2p -= 128
    z = 65536 * b2p + 256 * int(b1) + int(b0)
    return z if z < MLDSA_q else None


def CoeffFromHalfByte(b, eta):
    r"""Algorithm 15.  An element of [-eta, eta] from a nibble, or None."""
    b = int(b)
    if eta == 2 and b < 15:
        return 2 - (b % 5)
    if eta == 4 and b < 9:
        return 4 - b
    return None


def SimpleBitPack(w, b):
    r"""Algorithm 16.  Pack a polynomial with coefficients in [0, b]."""
    c = bitlen(b)
    z = []
    for i in range(MLDSA_n):
        z += IntegerToBits(w[i], c)
    return BitsToBytes(z)


def BitPack(w, a, b):
    r"""Algorithm 17.  Pack a polynomial with coefficients in [-a, b]."""
    c = bitlen(int(a) + int(b))
    z = []
    for i in range(MLDSA_n):
        z += IntegerToBits(int(b) - int(w[i]), c)
    return BitsToBytes(z)


def SimpleBitUnpack(v, b):
    r"""Algorithm 18.  The inverse of SimpleBitPack."""
    c = bitlen(b)
    z = BytesToBits(v)
    return [BitsToInteger(z[i * c:i * c + c], c) for i in range(MLDSA_n)]


def BitUnpack(v, a, b):
    r"""Algorithm 19.  The inverse of BitPack."""
    c = bitlen(int(a) + int(b))
    z = BytesToBits(v)
    return [int(b) - BitsToInteger(z[i * c:i * c + c], c) for i in range(MLDSA_n)]


def HintBitPack(h, omega, k):
    r"""Algorithm 20.  Encode the hint vector h into omega + k bytes."""
    y = bytearray(int(omega) + int(k))
    Index = 0
    for i in range(k):
        for j in range(MLDSA_n):
            if int(h[i][j]) != 0:
                y[Index] = j
                Index += 1
        y[omega + i] = Index
    return bytes(y)


def HintBitUnpack(y, omega, k):
    r"""Algorithm 21.  The inverse of HintBitPack; None encodes bot."""
    h = [[0] * MLDSA_n for _ in range(k)]
    Index = 0
    for i in range(k):
        if y[omega + i] < Index or y[omega + i] > omega:
            return None
        First = Index
        while Index < y[omega + i]:
            if Index > First:
                if y[Index - 1] >= y[Index]:
                    return None
            h[i][y[Index]] = 1
            Index += 1
    for i in range(Index, omega):
        if y[i] != 0:
            return None
    return h


# ---------------------------------------------------------------------
# Section 7.4.  High-order and low-order bits, and hints.
#
# These are defined on Z_q; the vector forms below apply them
# coefficientwise, as required by the text of Section 7.4.
# ---------------------------------------------------------------------

def Power2Round(r):
    r"""Algorithm 35.  r = r1*2^d + r0 mod q, with r0 = r mod+- 2^d."""
    rp = int(r) % MLDSA_q
    r0 = mod_pm(rp, 1 << MLDSA_d)
    return (rp - r0) >> MLDSA_d, r0


def Decompose(r, gamma2):
    r"""Algorithm 36.  r = r1*(2*gamma2) + r0 mod q, avoiding wraparound."""
    rp = int(r) % MLDSA_q
    r0 = mod_pm(rp, 2 * int(gamma2))
    if rp - r0 == MLDSA_q - 1:
        return 0, r0 - 1
    return (rp - r0) // (2 * int(gamma2)), r0


def HighBits(r, gamma2):
    r"""Algorithm 37."""
    return Decompose(r, gamma2)[0]


def LowBits(r, gamma2):
    r"""Algorithm 38."""
    return Decompose(r, gamma2)[1]


def MakeHint(z, r, gamma2):
    r"""Algorithm 39.  Does adding z to r change the high bits of r?"""
    r1 = HighBits(r, gamma2)
    v1 = HighBits(int(r) + int(z), gamma2)
    return 1 if r1 != v1 else 0


def UseHint(h, r, gamma2):
    r"""Algorithm 40.  The high bits of r, corrected by the hint bit h."""
    m = (MLDSA_q - 1) // (2 * int(gamma2))
    r1, r0 = Decompose(r, gamma2)
    if int(h) == 1:
        return (r1 + 1) % m if r0 > 0 else (r1 - 1) % m
    return r1


# Vector forms (Section 7.4, applied componentwise).

def Power2RoundVec(t):
    t1, t0 = [], []
    for f in t:
        pairs = [Power2Round(c) for c in _coeffs(f)]
        t1.append([p[0] for p in pairs])
        t0.append([p[1] for p in pairs])
    return t1, t0


def HighBitsVec(w, gamma2):
    return [[HighBits(c, gamma2) for c in _coeffs(f)] for f in w]


def LowBitsVec(w, gamma2):
    return [[LowBits(c, gamma2) for c in _coeffs(f)] for f in w]


def MakeHintVec(z, r, gamma2):
    return [[MakeHint(zc, rc, gamma2)
             for zc, rc in zip(_coeffs(zf), _coeffs(rf))]
            for zf, rf in zip(z, r)]


def UseHintVec(h, r, gamma2):
    return [[UseHint(hc, rc, gamma2)
             for hc, rc in zip(hf, _coeffs(rf))]
            for hf, rf in zip(h, r)]


# ---------------------------------------------------------------------
# Section 7.5.  The NTT and its inverse.
# ---------------------------------------------------------------------

def BitRev8(m):
    r"""Algorithm 43.  Reverse the bits of a byte."""
    b = IntegerToBits(m, 8)
    brev = [b[7 - i] for i in range(8)]
    return BitsToInteger(brev, 8)


# zetas[m] = zeta^BitRev8(m) mod q, Appendix B.
ZETAS = [Fq(MLDSA_zeta) ^ BitRev8(m) for m in range(MLDSA_n)]


def NTT(w):
    r"""Algorithm 41.  Rq -> Tq, returning a Sage vector over GF(q)."""
    wh = [Fq(c) for c in (_coeffs(w) if hasattr(w, 'lift') else list(w))]
    m = 0
    length = 128
    while length >= 1:
        start = 0
        while start < MLDSA_n:
            m += 1
            z = ZETAS[m]
            for j in range(start, start + length):
                t = z * wh[j + length]
                wh[j + length] = wh[j] - t
                wh[j] = wh[j] + t
            start += 2 * length
        length //= 2
    return vector(Fq, wh)


def NTTInverse(wh):
    r"""Algorithm 42.  Tq -> Rq."""
    w = list(wh)
    m = MLDSA_n
    length = 1
    while length < MLDSA_n:
        start = 0
        while start < MLDSA_n:
            m -= 1
            z = -ZETAS[m]
            for j in range(start, start + length):
                t = w[j]
                w[j] = t + w[j + length]
                w[j + length] = z * (t - w[j + length])
            start += 2 * length
        length *= 2
    f = Fq(8347681)                    # 8347681 = 256^{-1} mod q
    return Rq([c * f for c in w])


# ---------------------------------------------------------------------
# Section 7.6.  Arithmetic in the product ring Tq.
# ---------------------------------------------------------------------

def AddNTT(ah, bh):
    r"""Algorithm 44."""
    return ah + bh


def MultiplyNTT(ah, bh):
    r"""Algorithm 45.  Tq is a direct product, so the product is pointwise."""
    return ah.pairwise_product(bh)


def AddVectorNTT(vh, wh):
    r"""Algorithm 46."""
    return [AddNTT(a, b) for a, b in zip(vh, wh)]


def ScalarVectorNTT(ch, vh):
    r"""Algorithm 47."""
    return [MultiplyNTT(ch, a) for a in vh]


def MatrixVectorNTT(Mh, vh):
    r"""Algorithm 48."""
    k = len(Mh)
    out = []
    for i in range(k):
        acc = vector(Fq, [0] * MLDSA_n)
        for j in range(len(vh)):
            acc = AddNTT(acc, MultiplyNTT(Mh[i][j], vh[j]))
        out.append(acc)
    return out


# ---------------------------------------------------------------------
# Appendix A.  Montgomery reduction.
#
# Not used by the code above -- Sage's GF(q) handles the modular
# arithmetic -- but specified by the standard, so it is implemented and
# exercised by the self-test at the bottom of this file.
# ---------------------------------------------------------------------

def MontgomeryReduce(a):
    r"""Algorithm 49.  Compute a * 2^-32 mod q."""
    QINV = 58728449                    # q^{-1} mod 2^32
    a = int(a)
    t = mod_pm((a % (1 << 32)) * QINV % (1 << 32), 1 << 32)
    return (a - t * MLDSA_q) >> 32


# ---------------------------------------------------------------------
# Section 4, Table 1.  Parameter sets.
# ---------------------------------------------------------------------

MLDSA_PARAMS = {
    'ML-DSA-44': dict(tau=39, lam=128, gamma1=1 << 17, gamma2=(MLDSA_q - 1) // 88,
                      k=4, ell=4, eta=2, omega=80),
    'ML-DSA-65': dict(tau=49, lam=192, gamma1=1 << 19, gamma2=(MLDSA_q - 1) // 32,
                      k=6, ell=5, eta=4, omega=55),
    'ML-DSA-87': dict(tau=60, lam=256, gamma1=1 << 19, gamma2=(MLDSA_q - 1) // 32,
                      k=8, ell=7, eta=2, omega=75),
}

# Pre-hash function identifiers for Algorithms 4 and 5.  The standard
# spells out the SHA-256, SHA-512, and SHAKE128 cases and ends the switch
# with "case ...", leaving the remaining approved hash functions to the
# same OID arc; `NIST_PREHASH` in common.sage supplies the whole arc.
MLDSA_PREHASH = NIST_PREHASH


class MLDSA(object):
    r"""
    ML-DSA at one of the three parameter sets of FIPS 204, Table 1.

        sage: dsa = MLDSA('ML-DSA-65')
        sage: pk, sk = dsa.KeyGen()
        sage: sig = dsa.Sign(sk, b"hello", b"")
        sage: dsa.Verify(pk, b"hello", sig, b"")
        True
    """

    def __init__(self, name='ML-DSA-65'):
        if name not in MLDSA_PARAMS:
            raise ValueError("unknown parameter set %r" % (name,))
        self.name = name
        p = MLDSA_PARAMS[name]
        self.tau = p['tau']
        self.lam = p['lam']
        self.gamma1 = p['gamma1']
        self.gamma2 = p['gamma2']
        self.k = p['k']
        self.ell = p['ell']
        self.eta = p['eta']
        self.omega = p['omega']
        self.beta = self.tau * self.eta
        self.d = MLDSA_d
        # Byte lengths implied by Table 1.
        self.pk_len = 32 + 32 * self.k * (bitlen(MLDSA_q - 1) - self.d)
        self.sk_len = (32 + 32 + 64 +
                       32 * ((self.ell + self.k) * bitlen(2 * self.eta)
                             + self.d * self.k))
        self.sig_len = (self.lam // 4
                        + self.ell * 32 * (1 + bitlen(self.gamma1 - 1))
                        + self.omega + self.k)

    # ------------------ Section 7.2, key and signature encodings -----

    def pkEncode(self, rho, t1):
        r"""Algorithm 22."""
        top = (1 << (bitlen(MLDSA_q - 1) - self.d)) - 1
        pk = bytes(rho)
        for i in range(self.k):
            pk += SimpleBitPack(t1[i], top)
        return pk

    def pkDecode(self, pk):
        r"""Algorithm 23."""
        top = (1 << (bitlen(MLDSA_q - 1) - self.d)) - 1
        width = 32 * (bitlen(MLDSA_q - 1) - self.d)
        rho = pk[:32]
        t1 = [SimpleBitUnpack(pk[32 + i * width:32 + (i + 1) * width], top)
              for i in range(self.k)]
        return rho, t1

    def skEncode(self, rho, K, tr, s1, s2, t0):
        r"""Algorithm 24."""
        sk = bytes(rho) + bytes(K) + bytes(tr)
        for i in range(self.ell):
            sk += BitPack(s1[i], self.eta, self.eta)
        for i in range(self.k):
            sk += BitPack(s2[i], self.eta, self.eta)
        for i in range(self.k):
            sk += BitPack(t0[i], (1 << (self.d - 1)) - 1, 1 << (self.d - 1))
        return sk

    def skDecode(self, sk):
        r"""Algorithm 25."""
        we = 32 * bitlen(2 * self.eta)
        wt = 32 * self.d
        rho, K, tr = sk[:32], sk[32:64], sk[64:128]
        off = 128
        s1 = []
        for _ in range(self.ell):
            s1.append(BitUnpack(sk[off:off + we], self.eta, self.eta))
            off += we
        s2 = []
        for _ in range(self.k):
            s2.append(BitUnpack(sk[off:off + we], self.eta, self.eta))
            off += we
        t0 = []
        for _ in range(self.k):
            t0.append(BitUnpack(sk[off:off + wt],
                                (1 << (self.d - 1)) - 1, 1 << (self.d - 1)))
            off += wt
        return rho, K, tr, s1, s2, t0

    def sigEncode(self, ctilde, z, h):
        r"""Algorithm 26."""
        sigma = bytes(ctilde)
        for i in range(self.ell):
            sigma += BitPack(z[i], self.gamma1 - 1, self.gamma1)
        return sigma + HintBitPack(h, self.omega, self.k)

    def sigDecode(self, sigma):
        r"""Algorithm 27.  Returns h = None when the hint is malformed."""
        cl = self.lam // 4
        wz = 32 * (1 + bitlen(self.gamma1 - 1))
        ctilde = sigma[:cl]
        z = [BitUnpack(sigma[cl + i * wz:cl + (i + 1) * wz],
                       self.gamma1 - 1, self.gamma1) for i in range(self.ell)]
        y = sigma[cl + self.ell * wz:]
        h = HintBitUnpack(y, self.omega, self.k)
        return ctilde, z, h

    def w1Encode(self, w1):
        r"""Algorithm 28."""
        top = (MLDSA_q - 1) // (2 * self.gamma2) - 1
        out = b""
        for i in range(self.k):
            out += SimpleBitPack(w1[i], top)
        return out

    # -------------------- Section 7.3, sampling ----------------------

    def SampleInBall(self, rho):
        r"""Algorithm 29.  A sparse ternary polynomial of Hamming weight tau."""
        c = [0] * MLDSA_n
        ctx = XOF(bytes(rho), bits=256)
        s = ctx.squeeze(8)
        h = BytesToBits(s)
        for i in range(MLDSA_n - self.tau, MLDSA_n):
            j = ctx.squeeze(1)[0]
            while j > i:
                j = ctx.squeeze(1)[0]
            c[i] = c[j]
            c[j] = -1 if h[i + self.tau - MLDSA_n] == 1 else 1
        return c

    def RejNTTPoly(self, rho):
        r"""Algorithm 30.  Rejection-sample a uniform element of Tq."""
        ctx = XOF(bytes(rho), bits=128)
        a = [0] * MLDSA_n
        j = 0
        while j < MLDSA_n:
            s = ctx.squeeze(3)
            coeff = CoeffFromThreeBytes(s[0], s[1], s[2])
            if coeff is not None:
                a[j] = coeff
                j += 1
        return vector(Fq, a)

    def RejBoundedPoly(self, rho):
        r"""Algorithm 31.  Rejection-sample a polynomial with coeffs in [-eta,eta]."""
        ctx = XOF(bytes(rho), bits=256)
        a = [0] * MLDSA_n
        j = 0
        while j < MLDSA_n:
            z = ctx.squeeze(1)[0]
            z0 = CoeffFromHalfByte(z % 16, self.eta)
            z1 = CoeffFromHalfByte(z // 16, self.eta)
            if z0 is not None:
                a[j] = z0
                j += 1
            if z1 is not None and j < MLDSA_n:
                a[j] = z1
                j += 1
        return a

    def ExpandA(self, rho):
        r"""Algorithm 32.  The k x ell matrix over Tq."""
        return [[self.RejNTTPoly(bytes(rho) + IntegerToBytes(s, 1)
                                 + IntegerToBytes(r, 1))
                 for s in range(self.ell)] for r in range(self.k)]

    def ExpandS(self, rho):
        r"""Algorithm 33.  The short secret vectors s1 and s2."""
        s1 = [self.RejBoundedPoly(bytes(rho) + IntegerToBytes(r, 2))
              for r in range(self.ell)]
        s2 = [self.RejBoundedPoly(bytes(rho) + IntegerToBytes(r + self.ell, 2))
              for r in range(self.k)]
        return s1, s2

    def ExpandMask(self, rho, mu):
        r"""Algorithm 34.  The masking vector y with coefficients in (-g1, g1]."""
        c = 1 + bitlen(self.gamma1 - 1)
        y = []
        for r in range(self.ell):
            v = H(bytes(rho) + IntegerToBytes(int(mu) + r, 2), 32 * c)
            y.append(BitUnpack(v, self.gamma1 - 1, self.gamma1))
        return y

    # -------------------- Section 6, internal functions ---------------

    def KeyGen_internal(self, xi):
        r"""Algorithm 6.  Deterministic key generation from the seed xi."""
        seed = H(bytes(xi) + IntegerToBytes(self.k, 1) + IntegerToBytes(self.ell, 1), 128)
        rho, rhop, K = seed[:32], seed[32:96], seed[96:128]

        Ah = self.ExpandA(rho)
        s1, s2 = self.ExpandS(rhop)

        s1h = [NTT(Rq(p)) for p in s1]
        As1 = MatrixVectorNTT(Ah, s1h)
        t = [NTTInverse(As1[i]) + Rq(s2[i]) for i in range(self.k)]

        t1, t0 = Power2RoundVec(t)
        pk = self.pkEncode(rho, t1)
        tr = H(pk, 64)
        sk = self.skEncode(rho, K, tr, s1, s2, t0)
        return pk, sk

    def Sign_internal(self, sk, Mprime, rnd, mu=None):
        r"""
        Algorithm 7.  Fiat-Shamir with aborts, on the formatted message.

        Line 6 of the standard notes that the message representative mu
        "may optionally be computed in a different cryptographic module";
        passing `mu` supplies it directly and skips that line.
        """
        rho, K, tr, s1, s2, t0 = self.skDecode(sk)
        s1h = [NTT(Rq(p)) for p in s1]
        s2h = [NTT(Rq(p)) for p in s2]
        t0h = [NTT(Rq(p)) for p in t0]
        Ah = self.ExpandA(rho)

        if mu is None:
            mu = H(bytes(tr) + bytes(Mprime), 64)
        rhopp = H(bytes(K) + bytes(rnd) + mu, 64)

        kappa = 0
        while True:
            y = self.ExpandMask(rhopp, kappa)
            yh = [NTT(Rq(p)) for p in y]
            Ay = MatrixVectorNTT(Ah, yh)
            w = [NTTInverse(a) for a in Ay]
            w1 = HighBitsVec(w, self.gamma2)

            ctilde = H(mu + self.w1Encode(w1), self.lam // 4)
            c = self.SampleInBall(ctilde)
            ch = NTT(Rq(c))

            cs1 = [NTTInverse(MultiplyNTT(ch, a)) for a in s1h]
            cs2 = [NTTInverse(MultiplyNTT(ch, a)) for a in s2h]
            z = [Rq(y[i]) + cs1[i] for i in range(self.ell)]
            wcs2 = [w[i] - cs2[i] for i in range(self.k)]
            r0 = LowBitsVec(wcs2, self.gamma2)

            kappa += self.ell
            if inf_norm_vec(z) >= self.gamma1 - self.beta:
                continue
            if inf_norm_ints(r0) >= self.gamma2 - self.beta:
                continue

            ct0 = [NTTInverse(MultiplyNTT(ch, a)) for a in t0h]
            h = MakeHintVec([-p for p in ct0],
                            [wcs2[i] + ct0[i] for i in range(self.k)],
                            self.gamma2)
            if inf_norm_vec(ct0) >= self.gamma2:
                continue
            if sum(sum(p) for p in h) > self.omega:
                continue

            return self.sigEncode(ctilde, [centered(zi) for zi in z], h)

    def Verify_internal(self, pk, Mprime, sigma, mu=None):
        r"""Algorithm 8.  As in Algorithm 7, `mu` may be supplied directly."""
        if len(pk) != self.pk_len or len(sigma) != self.sig_len:
            return False
        rho, t1 = self.pkDecode(pk)
        ctilde, z, h = self.sigDecode(sigma)
        if h is None:
            return False

        Ah = self.ExpandA(rho)
        if mu is None:
            tr = H(pk, 64)
            mu = H(bytes(tr) + bytes(Mprime), 64)
        c = self.SampleInBall(ctilde)

        zh = [NTT(Rq(p)) for p in z]
        Az = MatrixVectorNTT(Ah, zh)
        ch = NTT(Rq(c))
        t1h = [NTT(Rq([int(v) << self.d for v in t1[i]])) for i in range(self.k)]
        ct1 = ScalarVectorNTT(ch, t1h)
        wapprox = [NTTInverse(Az[i] - ct1[i]) for i in range(self.k)]

        w1p = UseHintVec(h, wapprox, self.gamma2)
        ctildep = H(mu + self.w1Encode(w1p), self.lam // 4)
        return (max(max(abs(int(v)) for v in p) for p in z) < self.gamma1 - self.beta
                and ctilde == ctildep)

    # -------------------- Section 5, external functions ---------------

    def KeyGen(self, rbg=None):
        r"""Algorithm 1.  ML-DSA.KeyGen()."""
        if rbg is None:
            import os
            rbg = os.urandom
        xi = rbg(32)
        if xi is None:
            raise RuntimeError("random bit generation failure")
        return self.KeyGen_internal(xi)

    def Sign(self, sk, M, ctx=b"", deterministic=False, rbg=None):
        r"""Algorithm 2.  ML-DSA.Sign(sk, M, ctx)."""
        if len(ctx) > 255:
            raise ValueError("context string longer than 255 bytes")
        if deterministic:
            rnd = bytes(32)
        else:
            if rbg is None:
                import os
                rbg = os.urandom
            rnd = rbg(32)
            if rnd is None:
                raise RuntimeError("random bit generation failure")
        Mprime = IntegerToBytes(0, 1) + IntegerToBytes(len(ctx), 1) + bytes(ctx) + bytes(M)
        return self.Sign_internal(sk, Mprime, rnd)

    def Verify(self, pk, M, sigma, ctx=b""):
        r"""Algorithm 3.  ML-DSA.Verify(pk, M, sigma, ctx)."""
        if len(ctx) > 255:
            return False
        Mprime = IntegerToBytes(0, 1) + IntegerToBytes(len(ctx), 1) + bytes(ctx) + bytes(M)
        return self.Verify_internal(pk, Mprime, sigma)

    def HashSign(self, sk, M, ctx=b"", PH='SHA2-256', deterministic=False, rbg=None):
        r"""Algorithm 4.  HashML-DSA.Sign(sk, M, ctx, PH)."""
        if len(ctx) > 255:
            raise ValueError("context string longer than 255 bytes")
        if deterministic:
            rnd = bytes(32)
        else:
            if rbg is None:
                import os
                rbg = os.urandom
            rnd = rbg(32)
        oid, ph = MLDSA_PREHASH[PH]
        Mprime = (IntegerToBytes(1, 1) + IntegerToBytes(len(ctx), 1)
                  + bytes(ctx) + oid + ph(bytes(M)))
        return self.Sign_internal(sk, Mprime, rnd)

    def HashVerify(self, pk, M, sigma, ctx=b"", PH='SHA2-256'):
        r"""Algorithm 5.  HashML-DSA.Verify(pk, M, sigma, ctx, PH)."""
        if len(ctx) > 255:
            return False
        oid, ph = MLDSA_PREHASH[PH]
        Mprime = (IntegerToBytes(1, 1) + IntegerToBytes(len(ctx), 1)
                  + bytes(ctx) + oid + ph(bytes(M)))
        return self.Verify_internal(pk, Mprime, sigma)


# ---------------------------------------------------------------------
# Algebraic cross-checks, done with Sage's own ring arithmetic.
# ---------------------------------------------------------------------

def verify_ntt_is_a_ring_isomorphism(trials=3, seed=0):
    r"""
    Check, with Sage arithmetic, that:

      1. NTT^-1 inverts NTT on `Rq`;
      2. the NTT is evaluation at the 256 odd powers of zeta, so that
         MultiplyNTT (pointwise multiplication in the direct product
         ring Tq) transports multiplication in `Rq`;
      3. MontgomeryReduce(a) really equals a * 2^-32 mod q.
    """
    set_random_seed(seed)
    for _ in range(trials):
        f = Rq([Fq.random_element() for _ in range(MLDSA_n)])
        g = Rq([Fq.random_element() for _ in range(MLDSA_n)])

        assert NTTInverse(NTT(f)) == f, "NTT^-1 . NTT != id"

        # Equation (7.1): NTT(w)[j] = w(zeta^(2*BitRev8(j)+1)).
        fh = NTT(f)
        flift = f.lift()
        for j in range(MLDSA_n):
            pt = Fq(MLDSA_zeta) ^ (2 * BitRev8(j) + 1)
            assert fh[j] == flift(pt), "NTT is not evaluation at zeta^(2 BitRev8 j + 1)"

        assert NTT(f * g) == MultiplyNTT(NTT(f), NTT(g)), \
            "MultiplyNTT does not transport the product of Rq"

    for a in [1, 2, 12345, MLDSA_q - 1, -7, 2 ^ 31]:
        assert (MontgomeryReduce(a) - a * inverse_mod(2 ^ 32, MLDSA_q)) % MLDSA_q == 0, \
            "MontgomeryReduce is wrong at a = %d" % a
    return True
