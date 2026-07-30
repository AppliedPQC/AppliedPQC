# =====================================================================
#  FIPS 203 -- ML-KEM
#  Module-Lattice-Based Key-Encapsulation Mechanism Standard
#
#  A complete, byte-exact SageMath implementation.  Every one of the 21
#  numbered algorithms of FIPS 203 appears below as its own function,
#  named after the standard and annotated with its algorithm number.
#
#  Algebraic objects are genuine Sage objects:
#
#      *  the coefficient domain is  Rq = GF(3329)[X]/(X^256 + 1),
#         a Sage quotient ring, so `f * g` is Sage ring multiplication;
#      *  the NTT domain Tq is carried as a Sage vector over GF(3329),
#         with the standard's MultiplyNTTs supplying its ring product;
#      *  module elements are Sage vectors and matrices over those.
#
#  `verify_ntt_is_a_ring_isomorphism()` at the end of this file checks the
#  two domains against each other using Sage's own arithmetic.
#
#  Reference: FIPS 203, Module-Lattice-Based Key-Encapsulation Mechanism
#  Standard, NIST, August 2024.
# =====================================================================

load("common.sage")

# ---------------------------------------------------------------------
# Section 2.4 / 4.  Rings and constants.
# ---------------------------------------------------------------------

MLKEM_n = 256
MLKEM_q = 3329
MLKEM_zeta = 17                      # a primitive 256-th root of unity mod q

Fq = GF(MLKEM_q)
Rx = PolynomialRing(Fq, 'X')
X = Rx.gen()
Rq = Rx.quotient(X ^ MLKEM_n + 1, 'x')   # R_q = Z_q[X]/(X^256+1)
Tq = VectorSpace(Fq, MLKEM_n)            # underlying set of the NTT domain


def BitRev7(i):
    r"""The bit reversal of the seven-bit integer `i` (Section 4.3)."""
    i = int(i)
    return int(''.join(reversed(format(i, '07b'))), 2)


# ZETA[i] = zeta^BitRev7(i) mod q, the twiddle factors of Algorithms 9/10.
ZETA = [Fq(MLKEM_zeta) ^ BitRev7(i) for i in range(128)]

# GAMMA[i] = zeta^(2*BitRev7(i)+1), the modulus of the i-th quadratic
# factor of X^256+1 and the constant used by BaseCaseMultiply.
GAMMA = [Fq(MLKEM_zeta) ^ (2 * BitRev7(i) + 1) for i in range(128)]


def _coeffs(f):
    r"""The 256 coefficients of an element of `Rq`, as Sage field elements."""
    c = list(f.lift())
    return c + [Fq(0)] * (MLKEM_n - len(c))


def _ints(seq):
    r"""Lift a sequence of GF(q) elements to integers in {0,...,q-1}."""
    return [int(c) for c in seq]


# ---------------------------------------------------------------------
# Section 3.3 / 3.4.  Notation examples.
#
# Algorithms 1 and 2 of FIPS 203 are not cryptographic operations; they
# are worked examples that fix the meaning of the standard's "for" loop
# and XOF notation.  They are implemented here so that the mapping from
# the standard to this file is complete, with no gaps in the numbering.
# ---------------------------------------------------------------------

def ForExample():
    r"""Algorithm 1.  Illustrates the standard's two "for"-loop forms."""
    A = [0] * 10
    for i in range(10):
        A[i] = i
    B = []
    k = 256
    while k > 1:
        B.append(k)
        k = k // 2
    return A, B


def SHAKE128example(strings, outbytes):
    r"""
    Algorithm 2.  Illustrates the Init / Absorb / Squeeze XOF interface:
    absorb each string in turn, then squeeze the requested byte counts.
    """
    ctx = XOF(b"", bits=128)
    for s in strings:
        ctx.absorb(s)
    return [ctx.squeeze(b) for b in outbytes]


# ---------------------------------------------------------------------
# Section 4.2.1.  Conversion between bits and bytes.
# ---------------------------------------------------------------------

def BitsToBytes(b):
    r"""Algorithm 3.  Pack a bit array (LSB first) into bytes."""
    ell = len(b) // 8
    B = bytearray(ell)
    for i in range(len(b)):
        B[i // 8] |= int(b[i]) << (i % 8)
    return bytes(B)


def BytesToBits(B):
    r"""Algorithm 4.  Unpack bytes into a bit array (LSB first)."""
    b = []
    for byte in bytes(B):
        v = byte
        for _ in range(8):
            b.append(v & 1)
            v >>= 1
    return b


# ---------------------------------------------------------------------
# Section 4.2.1, Equations (4.7) and (4.8).  Compression.
#
# Compress_d(x) = round(2^d / q * x) mod 2^d, ties rounded up.
# Decompress_d(y) = round(q / 2^d * y).
# ---------------------------------------------------------------------

def Compress(d, x):
    r"""Equation (4.7), one coefficient."""
    d = int(d)
    return (((int(x) << d) + MLKEM_q // 2) // MLKEM_q) % (1 << d)


def Decompress(d, y):
    r"""Equation (4.8), one coefficient."""
    d = int(d)
    return (MLKEM_q * int(y) + (1 << (d - 1))) >> d


def CompressPoly(d, f):
    r"""Compress_d applied to every coefficient of an element of `Rq`."""
    return [Compress(d, c) for c in _ints(_coeffs(f))]


def DecompressPoly(d, F):
    r"""Decompress_d applied coefficientwise, returning an element of `Rq`."""
    return Rq([Decompress(d, y) for y in F])


# ---------------------------------------------------------------------
# Section 4.2.1.  Encoding and decoding of arrays of integers.
# ---------------------------------------------------------------------

def ByteEncode(d, F):
    r"""Algorithm 5.  Serialize 256 integers of `d` bits each."""
    d = int(d)
    b = [0] * (MLKEM_n * d)
    for i in range(MLKEM_n):
        a = int(F[i])
        for j in range(d):
            b[i * d + j] = a & 1
            a >>= 1
    return BitsToBytes(b)


def ByteDecode(d, B):
    r"""Algorithm 6.  Deserialize 32*d bytes into 256 integers."""
    d = int(d)
    m = (1 << d) if d < 12 else MLKEM_q
    b = BytesToBits(B)
    return [sum(b[i * d + j] << j for j in range(d)) % m for i in range(MLKEM_n)]


# ---------------------------------------------------------------------
# Section 4.2.2.  Sampling.
# ---------------------------------------------------------------------

def SampleNTT(B):
    r"""
    Algorithm 7.  Rejection-sample a uniform element of `Tq` from a
    34-byte seed rho || j || i, using SHAKE128 as the XOF.

    Returns a Sage vector over GF(q): the NTT-domain representation.
    """
    ctx = XOF(bytes(B), bits=128)
    a = [0] * MLKEM_n
    j = 0
    while j < MLKEM_n:
        C = ctx.squeeze(3)
        d1 = C[0] + 256 * (C[1] % 16)
        d2 = (C[1] // 16) + 16 * C[2]
        if d1 < MLKEM_q:
            a[j] = d1
            j += 1
        if d2 < MLKEM_q and j < MLKEM_n:
            a[j] = d2
            j += 1
    return vector(Fq, a)


def SamplePolyCBD(eta, B):
    r"""
    Algorithm 8.  Sample an element of `Rq` whose coefficients follow the
    centered binomial distribution of parameter `eta`, from 64*eta bytes.
    """
    eta = int(eta)
    b = BytesToBits(B)
    f = [0] * MLKEM_n
    for i in range(MLKEM_n):
        base = 2 * i * eta
        xx = sum(b[base + j] for j in range(eta))
        yy = sum(b[base + eta + j] for j in range(eta))
        f[i] = (xx - yy) % MLKEM_q
    return Rq(f)


# ---------------------------------------------------------------------
# Section 4.3.  The number-theoretic transform.
# ---------------------------------------------------------------------

def NTT(f):
    r"""
    Algorithm 9.  Map `f` in `Rq` to its NTT representation in `Tq`.

    This is the Cooley-Tukey decimation-in-time butterfly network of the
    standard, run over Sage's GF(3329).
    """
    fh = _coeffs(f)
    i = 1
    length = 128
    while length >= 2:
        for start in range(0, MLKEM_n, 2 * length):
            z = ZETA[i]
            i += 1
            for j in range(start, start + length):
                t = z * fh[j + length]
                fh[j + length] = fh[j] - t
                fh[j] = fh[j] + t
        length //= 2
    return vector(Fq, fh)


def NTTInverse(fh):
    r"""Algorithm 10.  Map an NTT representation back into `Rq`."""
    f = list(fh)
    i = 127
    length = 2
    while length <= 128:
        for start in range(0, MLKEM_n, 2 * length):
            z = ZETA[i]
            i -= 1
            for j in range(start, start + length):
                t = f[j]
                f[j] = t + f[j + length]
                f[j + length] = z * (f[j + length] - t)
        length *= 2
    inv128 = Fq(3303)                    # 3303 = 128^{-1} mod 3329
    return Rq([c * inv128 for c in f])


def BaseCaseMultiply(a0, a1, b0, b1, gamma):
    r"""
    Algorithm 12.  Multiply the degree-one polynomials a0 + a1 X and
    b0 + b1 X in GF(q)[X]/(X^2 - gamma).
    """
    c0 = a0 * b0 + a1 * b1 * gamma
    c1 = a0 * b1 + a1 * b0
    return c0, c1


def MultiplyNTTs(fh, gh):
    r"""
    Algorithm 11.  The product in `Tq`: 128 independent multiplications
    of degree-one polynomials, each modulo its own quadratic X^2 - gamma.
    """
    h = [Fq(0)] * MLKEM_n
    for i in range(128):
        c0, c1 = BaseCaseMultiply(fh[2 * i], fh[2 * i + 1],
                                  gh[2 * i], gh[2 * i + 1], GAMMA[i])
        h[2 * i] = c0
        h[2 * i + 1] = c1
    return vector(Fq, h)


# Convenience: the module-level operations of Section 2.4.5, written with
# the Tq product above.  These are notation in the standard, not numbered
# algorithms, but naming them keeps K-PKE readable.

def ntt_vec_dot(vh, wh):
    r"""The Tq inner product of two length-k vectors over `Tq`."""
    acc = vector(Fq, [0] * MLKEM_n)
    for a, b in zip(vh, wh):
        acc = acc + MultiplyNTTs(a, b)
    return acc


def ntt_mat_vec(Ah, vh, transpose=False):
    r"""Matrix-vector product over `Tq`, optionally with A transposed."""
    k = len(Ah)
    out = []
    for i in range(k):
        row = [Ah[j][i] for j in range(k)] if transpose else Ah[i]
        out.append(ntt_vec_dot(row, vh))
    return out


# ---------------------------------------------------------------------
# Section 4.1.  Hash functions and the PRF/XOF instantiations.
# ---------------------------------------------------------------------

def _G(c):
    r"""G = SHA3-512, split into two 32-byte halves."""
    h = SHA3_512(c)
    return h[:32], h[32:]


def _H(s):
    r"""H = SHA3-256."""
    return SHA3_256(s)


def _J(s):
    r"""J = SHAKE256(., 256)."""
    return SHAKE256(s, 32)


def _PRF(eta, s, b):
    r"""PRF_eta(s, b) = SHAKE256(s || b, 64*eta*8)."""
    return SHAKE256(bytes(s) + bytes([int(b)]), 64 * int(eta))


# ---------------------------------------------------------------------
# Section 8.  Parameter sets.
# ---------------------------------------------------------------------

MLKEM_PARAMS = {
    'ML-KEM-512':  dict(k=2, eta1=3, eta2=2, du=10, dv=4),
    'ML-KEM-768':  dict(k=3, eta1=2, eta2=2, du=10, dv=4),
    'ML-KEM-1024': dict(k=4, eta1=2, eta2=2, du=11, dv=5),
}


class MLKEM(object):
    r"""
    ML-KEM at one of the three parameter sets of FIPS 203, Section 8.

        sage: kem = MLKEM('ML-KEM-768')
        sage: ek, dk = kem.KeyGen()
        sage: K, c = kem.Encaps(ek)
        sage: kem.Decaps(dk, c) == K
        True
    """

    def __init__(self, name='ML-KEM-768'):
        if name not in MLKEM_PARAMS:
            raise ValueError("unknown parameter set %r" % (name,))
        self.name = name
        p = MLKEM_PARAMS[name]
        self.k = p['k']
        self.eta1 = p['eta1']
        self.eta2 = p['eta2']
        self.du = p['du']
        self.dv = p['dv']
        # Byte lengths fixed by Section 8, Table 3.
        self.ek_len = 384 * self.k + 32
        self.dk_pke_len = 384 * self.k
        self.dk_len = 768 * self.k + 96
        self.c_len = 32 * (self.du * self.k + self.dv)

    # -- Section 4.3, the matrix expansion shared by KeyGen and Encrypt --

    def _ExpandA(self, rho):
        r"""A-hat[i][j] = SampleNTT(rho || j || i), Algorithm 13 lines 3-7."""
        k = self.k
        return [[SampleNTT(bytes(rho) + bytes([j, i])) for j in range(k)]
                for i in range(k)]

    # ----------------------------- K-PKE ------------------------------

    def KPKE_KeyGen(self, d):
        r"""Algorithm 13.  K-PKE.KeyGen(d) -> (ek_PKE, dk_PKE)."""
        k = self.k
        rho, sigma = _G(bytes(d) + bytes([k]))     # note the domain separator k
        N = 0
        Ah = self._ExpandA(rho)

        s = []
        for _ in range(k):
            s.append(SamplePolyCBD(self.eta1, _PRF(self.eta1, sigma, N)))
            N += 1
        e = []
        for _ in range(k):
            e.append(SamplePolyCBD(self.eta1, _PRF(self.eta1, sigma, N)))
            N += 1

        sh = [NTT(si) for si in s]
        eh = [NTT(ei) for ei in e]
        th = [ntt_vec_dot(Ah[i], sh) + eh[i] for i in range(k)]

        ek = b"".join(ByteEncode(12, _ints(t)) for t in th) + rho
        dk = b"".join(ByteEncode(12, _ints(si)) for si in sh)
        return ek, dk

    def KPKE_Encrypt(self, ek, m, r):
        r"""Algorithm 14.  K-PKE.Encrypt(ek_PKE, m, r) -> c."""
        k = self.k
        N = 0
        th = [vector(Fq, ByteDecode(12, ek[384 * i:384 * (i + 1)]))
              for i in range(k)]
        rho = ek[384 * k:384 * k + 32]
        Ah = self._ExpandA(rho)

        y = []
        for _ in range(k):
            y.append(SamplePolyCBD(self.eta1, _PRF(self.eta1, r, N)))
            N += 1
        e1 = []
        for _ in range(k):
            e1.append(SamplePolyCBD(self.eta2, _PRF(self.eta2, r, N)))
            N += 1
        e2 = SamplePolyCBD(self.eta2, _PRF(self.eta2, r, N))

        yh = [NTT(yi) for yi in y]
        Aty = ntt_mat_vec(Ah, yh, transpose=True)
        u = [NTTInverse(Aty[i]) + e1[i] for i in range(k)]

        mu = DecompressPoly(1, ByteDecode(1, m))
        v = NTTInverse(ntt_vec_dot(th, yh)) + e2 + mu

        c1 = b"".join(ByteEncode(self.du, CompressPoly(self.du, ui)) for ui in u)
        c2 = ByteEncode(self.dv, CompressPoly(self.dv, v))
        return c1 + c2

    def KPKE_Decrypt(self, dk, c):
        r"""Algorithm 15.  K-PKE.Decrypt(dk_PKE, c) -> m."""
        k, du, dv = self.k, self.du, self.dv
        split = 32 * du * k
        c1, c2 = c[:split], c[split:split + 32 * dv]

        u = [DecompressPoly(du, ByteDecode(du, c1[32 * du * i:32 * du * (i + 1)]))
             for i in range(k)]
        v = DecompressPoly(dv, ByteDecode(dv, c2))
        sh = [vector(Fq, ByteDecode(12, dk[384 * i:384 * (i + 1)]))
              for i in range(k)]

        w = v - NTTInverse(ntt_vec_dot(sh, [NTT(ui) for ui in u]))
        return ByteEncode(1, CompressPoly(1, w))

    # ---------------------------- ML-KEM ------------------------------

    def KeyGen_internal(self, d, z):
        r"""Algorithm 16.  Deterministic key generation from (d, z)."""
        ek, dk_pke = self.KPKE_KeyGen(d)
        dk = dk_pke + ek + _H(ek) + bytes(z)
        return ek, dk

    def Encaps_internal(self, ek, m):
        r"""Algorithm 17.  Deterministic encapsulation of the message `m`."""
        K, r = _G(bytes(m) + _H(ek))
        c = self.KPKE_Encrypt(ek, bytes(m), r)
        return K, c

    def Decaps_internal(self, dk, c):
        r"""Algorithm 18.  Decapsulation, with implicit rejection."""
        k = self.k
        dk_pke = dk[0:384 * k]
        ek_pke = dk[384 * k:768 * k + 32]
        h = dk[768 * k + 32:768 * k + 64]
        z = dk[768 * k + 64:768 * k + 96]

        m2 = self.KPKE_Decrypt(dk_pke, c)
        K2, r2 = _G(m2 + h)
        Kbar = _J(bytes(z) + bytes(c))
        c2 = self.KPKE_Encrypt(ek_pke, m2, r2)
        if c != c2:                      # constant-time selection in practice
            K2 = Kbar
        return K2

    # -- Section 7: the externally facing algorithms, with the checks --

    def KeyGen(self, rbg=None):
        r"""Algorithm 19.  ML-KEM.KeyGen()."""
        if rbg is None:
            import os
            rbg = os.urandom
        d = rbg(32)
        z = rbg(32)
        if d is None or z is None:
            raise RuntimeError("random bit generation failure")
        return self.KeyGen_internal(d, z)

    def Encaps(self, ek, rbg=None):
        r"""Algorithm 20.  ML-KEM.Encaps(ek), with the Section 7.2 checks."""
        self.check_encapsulation_key(ek)
        if rbg is None:
            import os
            rbg = os.urandom
        m = rbg(32)
        if m is None:
            raise RuntimeError("random bit generation failure")
        return self.Encaps_internal(ek, m)

    def Decaps(self, dk, c):
        r"""Algorithm 21.  ML-KEM.Decaps(dk, c), with the Section 7.3 checks."""
        self.check_decapsulation_key(dk)
        if len(c) != self.c_len:
            raise ValueError("ciphertext check failed: wrong length")
        return self.Decaps_internal(dk, c)

    # -- Section 7.2 / 7.3 input checking ------------------------------

    def check_encapsulation_key(self, ek):
        r"""Type check and modulus check on an encapsulation key."""
        if len(ek) != self.ek_len:
            raise ValueError("encapsulation key type check failed: wrong length")
        for i in range(self.k):
            chunk = ek[384 * i:384 * (i + 1)]
            if ByteEncode(12, ByteDecode(12, chunk)) != chunk:
                raise ValueError("encapsulation key modulus check failed")
        return True

    def check_decapsulation_key(self, dk):
        r"""Type check and hash check on a decapsulation key."""
        if len(dk) != self.dk_len:
            raise ValueError("decapsulation key type check failed: wrong length")
        k = self.k
        ek = dk[384 * k:768 * k + 32]
        if _H(ek) != dk[768 * k + 32:768 * k + 64]:
            raise ValueError("decapsulation key hash check failed")
        return True


# ---------------------------------------------------------------------
# Algebraic cross-checks, done with Sage's own ring arithmetic.
#
# These are what a SageMath implementation buys over a bytes-only one:
# the standard's hand-rolled transform can be checked directly against
# multiplication in the quotient ring it claims to implement.
# ---------------------------------------------------------------------

def Tq_factor_ring(i):
    r"""
    The i-th factor GF(q)[X]/(X^2 - zeta^(2*BitRev7(i)+1)) of the
    Chinese-remainder decomposition of `Rq` (Section 4.3, Eq. 4.10).
    """
    return Rx.quotient(X ^ 2 - GAMMA[i], 'y')


def verify_ntt_is_a_ring_isomorphism(trials=3, seed=0):
    r"""
    Check, with Sage arithmetic, that:

      1. NTT^-1 inverts NTT on `Rq`;
      2. the i-th NTT coefficient pair really is f mod (X^2 - gamma_i),
         i.e. the NTT is the CRT map of Equation (4.10);
      3. MultiplyNTTs transports multiplication in `Rq`, so that
         NTT(f*g) = MultiplyNTTs(NTT(f), NTT(g)).

    Point 3 is the statement that NTT is a ring isomorphism Rq -> Tq.
    """
    set_random_seed(seed)
    for _ in range(trials):
        f = Rq([Fq.random_element() for _ in range(MLKEM_n)])
        g = Rq([Fq.random_element() for _ in range(MLKEM_n)])

        assert NTTInverse(NTT(f)) == f, "NTT^-1 . NTT != id"

        fh = NTT(f)
        flift = f.lift()
        for i in range(128):
            Si = Tq_factor_ring(i)
            assert Si(flift) == Si([fh[2 * i], fh[2 * i + 1]]), \
                "NTT coefficient pair %d is not f mod (X^2-gamma)" % i

        assert NTT(f * g) == MultiplyNTTs(NTT(f), NTT(g)), \
            "MultiplyNTTs does not transport the product of Rq"
    return True
