# =====================================================================
#  FIPS 206 -- FN-DSA  (Falcon)
#  Fast-Fourier, Lattice-Based Digital Signature Algorithm
#
#  A complete SageMath implementation: NTRU trapdoor generation with the
#  tower-recursive NTRU solver, the FFT over the complex tower, the
#  LDL* / Falcon tree, fast Fourier sampling with the isochronous
#  discrete Gaussian sampler, signing, verification, and the compressed
#  signature and key encodings.
#
#  -------------------------------------------------------------------
#  STATUS OF THE STANDARD.  As of this writing NIST lists FIPS 206 as
#  "in development": no initial public draft has been published, and no
#  NIST ACVP test vectors exist.  The authoritative specification for
#  FN-DSA is therefore still the round-3 Falcon submission,
#
#      Falcon: Fast-Fourier Lattice-based Compact Signatures over NTRU,
#      specification v1.2, 1 October 2020,
#
#  and that is what this file implements, with its algorithm numbering.
#  When FIPS 206 is published, the parts that are expected to change are
#  the key/signature encodings, the domain separation of the hashed
#  message, and possibly the pre-hash variants -- not the lattice
#  machinery below.  Every such contact point is marked "FIPS 206 note".
#  -------------------------------------------------------------------
#
#  Sage is used throughout for the parts where it genuinely helps:
#
#      *  exact arithmetic in Z[x]/(x^n+1) (Sage's ZZ['x']) drives the
#         NTRU solver, so the equation f*G - g*F = q is verified exactly
#         rather than in floating point;
#      *  Zq[x]/(x^n+1) over GF(12289) computes h = g/f and the
#         verification relation s1 = c - s2*h;
#      *  the complex FFT runs over CDF, Sage's complex double field,
#         which is exactly the IEEE 754 binary64 arithmetic that Falcon
#         specifies for signing.
#
#  `verify_fft_against_exact_ring()` and `verify_ntru_equation()` check
#  the floating-point layer and the trapdoor against Sage's exact rings.
# =====================================================================

load("common.sage")

import os
from math import floor, sqrt, cos, sin, pi


# ---------------------------------------------------------------------
# Section 3.13, Table 3.3.  Parameters.
# ---------------------------------------------------------------------

FALCON_q = 12289

FNDSA_PARAMS = {
    'FN-DSA-512':  dict(n=512,  sigma=165.736617183, sigmin=1.277833697,
                        sig_bound=34034726, sbytelen=666,  pk_bytelen=897,
                        fg_bits=6),
    'FN-DSA-1024': dict(n=1024, sigma=168.388571447, sigmin=1.298280334,
                        sig_bound=70265242, sbytelen=1280, pk_bytelen=1793,
                        fg_bits=5),
}

FALCON_sigmax = 1.8205

# Section 3.9.3, Table 3.1: the reverse cumulative distribution table of
# the base sampler, scaled by 2^72.
RCDT = [
    3024686241123004913666, 1564742784480091954050, 636254429462080897535,
    199560484645026482916,  47667343854657281903,   8595902006365044063,
    1163297957344668388,    117656387352093658,     8867391802663976,
    496969357462633,        20680885154299,         638331848991,
    14602316184,            247426747,              3104126,
    28824,                  198,                    1,
]

# Section 3.9.3: the 64-bit coefficients of the polynomial approximating
# exp(-x) on [0, ln 2], used by ApproxExp.
APPROXEXP_C = [
    0x00000004741183A3, 0x00000036548CFC06, 0x0000024FDCBF140A,
    0x0000171D939DE045, 0x0000D00CF58F6F84, 0x000680681CF796E3,
    0x002D82D8305B0FEA, 0x011111110E066FD0, 0x0555555555070F00,
    0x155555555581FF00, 0x400000000002B400, 0x7FFFFFFFFFFF4800,
    0x8000000000000000,
]


# ---------------------------------------------------------------------
# Exact rings.  Everything integral happens here, in Sage.
# ---------------------------------------------------------------------

Zx = PolynomialRing(ZZ, 'x')
Fq = GF(FALCON_q)
Fqx = PolynomialRing(Fq, 'x')
QQx = PolynomialRing(QQ, 'x')


def _cyclo_mul(a, b, n):
    r"""Product of two integer coefficient lists in Z[x]/(x^n + 1)."""
    p = Zx(list(a)) * Zx(list(b))
    c = p.list() + [0] * (2 * n)
    return [int(c[i]) - int(c[i + n]) for i in range(n)]


def _sub(a, b):
    return [int(u) - int(v) for u, v in zip(a, b)]


def _sqnorm(*polys):
    r"""The squared Euclidean norm of a concatenation of integer vectors."""
    return sum(int(v) * int(v) for p in polys for v in p)


# ---------------------------------------------------------------------
# Section 3.6.  The FFT over the complex tower, in Sage's CDF.
#
# fft(f) evaluates f at the n complex roots of x^n + 1, ordered so that
# root[2i+1] = -root[2i].  That ordering is what makes splitfft and
# mergefft (Algorithms 1 and 2) the simple butterflies below, and it
# recurses consistently: the level-n/2 roots are the squares of the
# even-indexed level-n roots.
# ---------------------------------------------------------------------

_ROOTS_CACHE = {}


def _bitrev(i, width):
    r = 0
    for _ in range(width):
        r = (r << 1) | (i & 1)
        i >>= 1
    return r


def fft_roots(n):
    r"""The n roots of x^n + 1 in CDF, in the order described above."""
    n = int(n)
    if n in _ROOTS_CACHE:
        return _ROOTS_CACHE[n]
    if n == 1:
        w = [CDF(-1)]
    else:
        half = n // 2
        width = int(half).bit_length() - 1
        w = [CDF(0)] * n
        for i in range(half):
            ang = pi * (2 * _bitrev(i, width) + 1) / n
            z = CDF(cos(ang), sin(ang))
            w[2 * i] = z
            w[2 * i + 1] = -z
    _ROOTS_CACHE[n] = w
    return w


def split_fft(f_fft):
    r"""Algorithm 1.  splitfft: FFT(f) -> (FFT(f0), FFT(f1)), f = f0(x^2) + x f1(x^2)."""
    n = len(f_fft)
    w = fft_roots(n)
    f0 = [CDF(0)] * (n // 2)
    f1 = [CDF(0)] * (n // 2)
    for i in range(n // 2):
        a, b = f_fft[2 * i], f_fft[2 * i + 1]
        f0[i] = (a + b) / 2
        f1[i] = (a - b) / 2 * w[2 * i].conjugate()
    return f0, f1


def merge_fft(f0, f1):
    r"""Algorithm 2.  mergefft, the inverse of splitfft."""
    n = 2 * len(f0)
    w = fft_roots(n)
    f_fft = [CDF(0)] * n
    for i in range(n // 2):
        t = f1[i] * w[2 * i]
        f_fft[2 * i] = f0[i] + t
        f_fft[2 * i + 1] = f0[i] - t
    return f_fft


def fft(f):
    r"""The FFT of a real coefficient list of length n (a power of two)."""
    n = len(f)
    if n == 1:
        return [CDF(f[0])]
    f0 = [f[2 * i] for i in range(n // 2)]
    f1 = [f[2 * i + 1] for i in range(n // 2)]
    return merge_fft(fft(f0), fft(f1))


def ifft(f_fft):
    r"""The inverse FFT, returning a real coefficient list."""
    n = len(f_fft)
    if n == 1:
        return [f_fft[0].real()]
    f0, f1 = split_fft(f_fft)
    a, b = ifft(f0), ifft(f1)
    f = [0.0] * n
    for i in range(n // 2):
        f[2 * i] = a[i]
        f[2 * i + 1] = b[i]
    return f


def add_fft(a, b):
    return [u + v for u, v in zip(a, b)]


def sub_fft(a, b):
    return [u - v for u, v in zip(a, b)]


def mul_fft(a, b):
    return [u * v for u, v in zip(a, b)]


def div_fft(a, b):
    return [u / v for u, v in zip(a, b)]


def adj_fft(a):
    r"""The Hermitian adjoint f* , which is pointwise conjugation in FFT form."""
    return [u.conjugate() for u in a]


def neg_fft(a):
    return [-u for u in a]


# ---------------------------------------------------------------------
# Section 3.9.3.  The sampler over the integers.
# ---------------------------------------------------------------------

class RandomBytes(object):
    r"""
    A byte source for the sampler.  The default draws from the OS; a
    fixed byte string reproduces the specification's SamplerZ test
    vectors (Table 3.2) exactly.
    """

    def __init__(self, data=None):
        self.data = None if data is None else bytes(data)
        self.pos = 0

    def __call__(self, k):
        if self.data is None:
            return os.urandom(int(k))
        out = self.data[self.pos:self.pos + int(k)]
        if len(out) < int(k):
            raise ValueError("fixed random byte source exhausted")
        self.pos += int(k)
        return out


def UniformBits(randombytes, k):
    r"""
    Equation (3.32): an integer uniform in {0, ..., 2^k - 1}.

    Falcon reads multi-byte chunks big-endian throughout (Section 3.7),
    and the SamplerZ test vectors of Table 3.2 confirm it here.
    """
    assert k % 8 == 0
    return int.from_bytes(randombytes(k // 8), 'big')


def BaseSampler(randombytes):
    r"""Algorithm 12.  Sample z0 in {0,...,18} from the distribution chi."""
    u = UniformBits(randombytes, 72)
    z0 = 0
    for i in range(18):
        z0 += int(u < RCDT[i])
    return z0


def ApproxExp(x, ccs):
    r"""Algorithm 13.  An integral approximation of 2^63 * ccs * exp(-x)."""
    C = APPROXEXP_C
    y = C[0]
    z = int(floor(float(x) * (1 << 63)))
    for u in range(1, 13):
        y = C[u] - ((z * y) >> 63)
    z = int(floor(float(ccs) * (1 << 63)))
    y = (z * y) >> 63
    return y


def BerExp(randombytes, x, ccs):
    r"""Algorithm 14.  Return 1 with probability about ccs * exp(-x)."""
    LN2 = 0.69314718055994530941723212145818
    s = int(floor(float(x) / LN2))
    r = float(x) - s * LN2
    s = min(s, 63)
    z = ((2 * ApproxExp(r, ccs) - 1) >> s)
    i = 64
    while True:
        i -= 8
        w = UniformBits(randombytes, 8) - ((z >> i) & 0xFF)
        if not (w == 0 and i > 0):
            break
    return int(w < 0)


def SamplerZ(randombytes, mu, sigma_prime, sigmin):
    r"""Algorithm 15.  An integer distributed as D_{Z, sigma', mu}."""
    s = int(floor(float(mu)))
    r = float(mu) - s
    dss = 1.0 / (2.0 * float(sigma_prime) * float(sigma_prime))
    ccs = float(sigmin) / float(sigma_prime)
    while True:
        z0 = BaseSampler(randombytes)
        b = UniformBits(randombytes, 8) & 1
        z = b + (2 * b - 1) * z0
        x = ((z - r) ** 2) * dss - (z0 * z0) / (2.0 * FALCON_sigmax * FALCON_sigmax)
        if BerExp(randombytes, x, ccs) == 1:
            return z + s


# The specification's SamplerZ test vectors (Table 3.2, sigmin for n=512).
SAMPLERZ_KAT = [
    (-91.90471153063714, 1.7037990414754918, "0fc5442ff043d66e91d1eacac64ea5450a22941edc6c", -92),
    (-8.322564895434937, 1.7037990414754918, "f4da0f8d8444d1a77265c2ef6f98bbbb4bee7db8d9b3", -8),
    (-19.096516109216804, 1.7035823083824078, "db47f6d7fb9b19f25c36d6b9334d477a8bc0be68145d", -20),
    (-11.335543982423326, 1.7035823083824078,
     "ae41b4f5209665c74d00dcc1a8168a7bb516b3190cb42c1ded26cd52aed770eca7dd334e0547bcc3c163ce0b", -12),
    (7.9386734193997555, 1.6984647769450156,
     "31054166c1012780c603ae9b833cec73f2f41ca5807cc89c92158834632f9b1555", 8),
    (-28.990850086867255, 1.6984647769450156, "737e9d68a50a06dbbc6477", -30),
    (-9.071257914091655, 1.6980782114808988, "a98ddd14bf0bf22061d632", -10),
    (-43.88754568839566, 1.6980782114808988, "3cbf6818a68f7ab9991514", -41),
    (-58.17435547946095, 1.7010983419195522, "6f8633f5bfa5d26848668e3d5ddd46958e97630410587c", -61),
    (-43.58664906684732, 1.7010983419195522, "272bc6c25f5c5ee53f83c43a361fbc7cc91dc783e20a", -46),
    (-34.70565203313315, 1.7009387219711465, "45443c59574c2c3b07e2e1d9071e6d133dbe32754b0a", -34),
    (-44.36009577368896, 1.7009387219711465,
     "6ac116ed60c258e2cbaeab728c4823e6da36e18d08da5d0cc104e21cc7fd1f5ca8d9dbb675266c928448059e", -44),
    (-21.783037079346236, 1.6958406126012802, "68163bc1e2cbf3e18e7426", -23),
    (-39.68827784633828, 1.6958406126012802, "d6a1b51d76222a705a0259", -40),
    (-18.488607061056847, 1.6955259305261838, "f0523bfaa8a394bf4ea5c10f842366fde286d6a30803", -22),
    (-48.39610939101591, 1.6955259305261838, "87bd87e63374cee62127fc6931104aab64f136a0485b", -50),
]


def verify_samplerz_kat():
    r"""Check SamplerZ against the 16 test vectors of Table 3.2."""
    sigmin = 1.277833697
    for mu, sigma_p, rb, want in SAMPLERZ_KAT:
        src = RandomBytes(bytes.fromhex(rb))
        got = SamplerZ(src, mu, sigma_p, sigmin)
        assert got == want, "SamplerZ(%r, %r) = %s, expected %s" % (mu, sigma_p, got, want)
    return True


# ---------------------------------------------------------------------
# Section 3.8.2.  Solving the NTRU equation.
# ---------------------------------------------------------------------

def field_norm(a):
    r"""
    The field norm N: Z[x]/(x^n+1) -> Z[x]/(x^(n/2)+1).

    For a = a0(x^2) + x*a1(x^2), N(a) = a(x)*a(-x) = a0^2 - x*a1^2.
    """
    n = len(a)
    half = n // 2
    a0 = [int(a[2 * i]) for i in range(half)]
    a1 = [int(a[2 * i + 1]) for i in range(half)]
    s0 = _cyclo_mul(a0, a0, half)
    s1 = _cyclo_mul(a1, a1, half)
    # multiply s1 by x in Z[x]/(x^(n/2)+1) and subtract
    shifted = [-s1[half - 1]] + s1[:half - 1]
    return [s0[i] - shifted[i] for i in range(half)]


def lift(a):
    r"""The map a(x) -> a(x^2), from Z[x]/(x^(n/2)+1) into Z[x]/(x^n+1)."""
    n = len(a)
    out = [0] * (2 * n)
    for i in range(n):
        out[2 * i] = int(a[i])
    return out


def galois_conjugate(a):
    r"""The map a(x) -> a(-x)."""
    return [int(a[i]) if i % 2 == 0 else -int(a[i]) for i in range(len(a))]


def _bytesize(a):
    r"""The reference implementation's byte-granular size measure."""
    a = abs(int(a))
    res = 0
    while a:
        res += 8
        a >>= 8
    return res


def _size_of(v):
    return max([53] + [_bytesize(x) for x in v])


def Reduce(f, g, F, G):
    r"""
    Algorithm 7.  Reduce (F, G) with respect to (f, g).

    The coefficients of F and G start out enormous, so each round scales
    both pairs down to 53 significant bits before going through the FFT
    -- that is what keeps the rounding of k exact enough to converge.
    """
    n = len(f)
    size = max(_size_of(f), _size_of(g))
    fa = [int(x) >> (size - 53) for x in f]
    ga = [int(x) >> (size - 53) for x in g]
    fa_fft = fft([float(x) for x in fa])
    ga_fft = fft([float(x) for x in ga])
    den_fft = add_fft(mul_fft(fa_fft, adj_fft(fa_fft)),
                      mul_fft(ga_fft, adj_fft(ga_fft)))
    F, G = list(F), list(G)
    while True:
        Size = max(_size_of(F), _size_of(G))
        if Size < size:
            break
        Fa = [int(x) >> (Size - 53) for x in F]
        Ga = [int(x) >> (Size - 53) for x in G]
        Fa_fft = fft([float(x) for x in Fa])
        Ga_fft = fft([float(x) for x in Ga])
        num_fft = add_fft(mul_fft(Fa_fft, adj_fft(fa_fft)),
                          mul_fft(Ga_fft, adj_fft(ga_fft)))
        k = ifft(div_fft(num_fft, den_fft))
        k = [int(round(float(x))) for x in k]
        if all(x == 0 for x in k):
            break
        fk = _cyclo_mul(f, k, n)
        gk = _cyclo_mul(g, k, n)
        shift = Size - size
        for i in range(n):
            F[i] -= fk[i] << shift
            G[i] -= gk[i] << shift
    return F, G


def NTRUSolve(f, g):
    r"""
    Algorithm 6.  Find F, G with f*G - g*F = q in Z[x]/(x^n + 1).

    The tower recursion pushes (f, g) down through the field norm to Z,
    solves there with an extended gcd, and lifts back up.
    """
    n = len(f)
    if n == 1:
        f0, g0 = int(f[0]), int(g[0])
        d, u, v = xgcd(ZZ(f0), ZZ(g0))
        if d != 1:
            return None, None
        return [int(-FALCON_q * v)], [int(FALCON_q * u)]

    fp = field_norm(f)
    gp = field_norm(g)
    Fp, Gp = NTRUSolve(fp, gp)
    if Fp is None:
        return None, None
    F = _cyclo_mul(lift(Fp), galois_conjugate(g), n)
    G = _cyclo_mul(lift(Gp), galois_conjugate(f), n)
    return Reduce(f, g, F, G)


def gram_gs_norm(f, g):
    r"""
    The quantity gamma of Equation (3.28): the Gram-Schmidt norm of the
    Falcon basis, computed in FFT form via Equations (3.9) and (3.10).
    """
    n = len(f)
    sq1 = float(_sqnorm(f, g))
    f_fft = fft([float(x) for x in f])
    g_fft = fft([float(x) for x in g])
    den = add_fft(mul_fft(f_fft, adj_fft(f_fft)), mul_fft(g_fft, adj_fft(g_fft)))
    Ff = div_fft(adj_fft(f_fft), den)
    Gg = div_fft(adj_fft(g_fft), den)
    sq2 = FALCON_q ** 2 * sum(float((u * u.conjugate()).real()) for u in Ff + Gg) / n
    return max(sq1, sq2)


# ---------------------------------------------------------------------
# Section 3.8.3.  The LDL* decomposition and the Falcon tree.
# ---------------------------------------------------------------------

def LDL_fft(G00, G01, G10, G11):
    r"""Algorithm 8.  The LDL* decomposition of a 2x2 self-adjoint matrix."""
    D00 = G00
    L10 = div_fft(G10, G00)
    D11 = sub_fft(G11, mul_fft(mul_fft(L10, adj_fft(L10)), G00))
    return L10, D00, D11


def ffLDL_fft(G00, G01, G10, G11):
    r"""
    Algorithm 9.  The Falcon tree of a 2x2 Gram matrix.

    Nodes are ['node', L10, leftchild, rightchild] and leaves are
    ['leaf', value].  The recursion stops when the entries have FFT
    length 2: at that point D00 and D11 are self-adjoint elements of
    Q[x]/(x^2+1), hence constants, so both of their FFT entries carry
    the same real value and the leaf keeps a single number.  That is
    also the level at which ffSampling reaches its own base case, where
    t0 and t1 have length 1.
    """
    L10, D00, D11 = LDL_fft(G00, G01, G10, G11)
    if len(L10) == 2:
        return ['node', L10, ['leaf', D00[0]], ['leaf', D11[0]]]
    d00, d01 = split_fft(D00)
    d10, d11 = split_fft(D11)
    left = ffLDL_fft(d00, d01, adj_fft(d01), d00)
    right = ffLDL_fft(d10, d11, adj_fft(d11), d10)
    return ['node', L10, left, right]


def normalize_tree(T, sigma):
    r"""Steps 6-7 of Algorithm 4: leaf.value <- sigma / sqrt(leaf.value)."""
    if T[0] == 'leaf':
        T[1] = float(sigma) / sqrt(float(T[1].real()))
    else:
        normalize_tree(T[2], sigma)
        normalize_tree(T[3], sigma)


# ---------------------------------------------------------------------
# Section 3.9.2.  Fast Fourier sampling.
# ---------------------------------------------------------------------

def ffSampling(t0, t1, T, sigmin, randombytes):
    r"""Algorithm 11.  ffSampling_n(t, T)."""
    if T[0] == 'leaf':
        sigma_leaf = T[1]
        z0 = SamplerZ(randombytes, t0[0].real(), sigma_leaf, sigmin)
        z1 = SamplerZ(randombytes, t1[0].real(), sigma_leaf, sigmin)
        return [CDF(z0)], [CDF(z1)]

    ell, T0, T1 = T[1], T[2], T[3]
    t1a, t1b = split_fft(t1)
    z1a, z1b = ffSampling(t1a, t1b, T1, sigmin, randombytes)
    z1 = merge_fft(z1a, z1b)

    t0p = add_fft(t0, mul_fft(sub_fft(t1, z1), ell))
    t0a, t0b = split_fft(t0p)
    z0a, z0b = ffSampling(t0a, t0b, T0, sigmin, randombytes)
    z0 = merge_fft(z0a, z0b)
    return z0, z1


# ---------------------------------------------------------------------
# Section 3.7.  HashToPoint.
# ---------------------------------------------------------------------

def HashToPoint(data, q, n):
    r"""Algorithm 3.  Hash a byte string to a polynomial of Zq[x]/(x^n+1)."""
    k = (1 << 16) // int(q)
    ctx = XOF(bytes(data), bits=256)
    c = [0] * int(n)
    i = 0
    while i < int(n):
        b = ctx.squeeze(2)
        t = (b[0] << 8) | b[1]          # big-endian, per Section 3.7
        if t < k * int(q):
            c[i] = t % int(q)
            i += 1
    return c


# ---------------------------------------------------------------------
# Section 3.11.2.  Signature compression.
# ---------------------------------------------------------------------

def Compress(s, slen):
    r"""Algorithm 17.  Compress a short polynomial into `slen` bits."""
    bits = []
    for si in s:
        si = int(si)
        bits.append(1 if si < 0 else 0)
        a = abs(si)
        for j in range(6, -1, -1):
            bits.append((a >> j) & 1)
        for _ in range(a >> 7):
            bits.append(0)
        bits.append(1)
    if len(bits) > slen:
        return None
    bits += [0] * (slen - len(bits))
    out = bytearray(slen // 8)
    for i, b in enumerate(bits):
        if b:
            out[i // 8] |= 1 << (7 - (i % 8))
    return bytes(out)


def Decompress(data, slen, n):
    r"""Algorithm 18.  The inverse of Compress; None encodes the bottom symbol."""
    if len(data) * 8 != slen:
        return None
    bits = []
    for byte in data:
        for j in range(7, -1, -1):
            bits.append((byte >> j) & 1)
    s = []
    pos = 0
    for _ in range(n):
        if pos + 8 > len(bits):
            return None
        sign = bits[pos]
        low = 0
        for j in range(7):
            low = (low << 1) | bits[pos + 1 + j]
        pos += 8
        k = 0
        while True:
            if pos >= len(bits):
                return None
            if bits[pos] == 1:
                pos += 1
                break
            k += 1
            pos += 1
        val = low + (k << 7)
        if val == 0 and sign == 1:
            return None                       # unique encoding of zero
        s.append(-val if sign else val)
    if any(b for b in bits[pos:]):
        return None                           # trailing bits must be zero
    return s


# ---------------------------------------------------------------------
# Sections 3.11.4 and 3.11.5.  Key encodings.
# ---------------------------------------------------------------------

def _pack_signed(values, nbits):
    acc = 0
    accbits = 0
    out = bytearray()
    for v in values:
        acc = (acc << nbits) | (int(v) & ((1 << nbits) - 1))
        accbits += nbits
        while accbits >= 8:
            accbits -= 8
            out.append((acc >> accbits) & 0xFF)
    if accbits:
        out.append((acc << (8 - accbits)) & 0xFF)
    return bytes(out)


def _unpack_signed(data, nbits, count):
    acc = 0
    accbits = 0
    out = []
    pos = 0
    while len(out) < count:
        while accbits < nbits:
            acc = (acc << 8) | data[pos]
            pos += 1
            accbits += 8
        accbits -= nbits
        v = (acc >> accbits) & ((1 << nbits) - 1)
        if v >= (1 << (nbits - 1)):
            v -= (1 << nbits)
        out.append(v)
    return out


# ---------------------------------------------------------------------
# The scheme.
# ---------------------------------------------------------------------

class FNDSA(object):
    r"""
    FN-DSA (Falcon) at degree 512 or 1024.

        sage: fn = FNDSA('FN-DSA-512')
        sage: sk, pk = fn.Keygen()
        sage: sig = fn.Sign(b"hello", sk)
        sage: fn.Verify(b"hello", sig, pk)
        True
    """

    def __init__(self, name='FN-DSA-512'):
        if name not in FNDSA_PARAMS:
            raise ValueError("unknown parameter set %r" % (name,))
        self.name = name
        p = FNDSA_PARAMS[name]
        self.n = p['n']
        self.q = FALCON_q
        self.sigma = p['sigma']
        self.sigmin = p['sigmin']
        self.sig_bound = p['sig_bound']
        self.sbytelen = p['sbytelen']
        self.pk_bytelen = p['pk_bytelen']
        self.fg_bits = p['fg_bits']
        self.logn = int(self.n).bit_length() - 1
        self.slen = 8 * self.sbytelen - 328

    # ------------------------- Section 3.8 ---------------------------

    def NTRUGen(self, rng=None):
        r"""
        Algorithm 5.  Generate f, g, F, G with f*G - g*F = q and a short
        Gram-Schmidt norm.
        """
        if rng is None:
            rng = RandomBytes()
        n = self.n
        sigma_star = 1.43300980528773       # Equation (3.29)
        reps = 4096 // n
        bound = 1.17 ** 2 * self.q
        while True:
            f = [sum(SamplerZ(rng, 0, sigma_star, self.sigmin) for _ in range(reps))
                 for _ in range(n)]
            g = [sum(SamplerZ(rng, 0, sigma_star, self.sigmin) for _ in range(reps))
                 for _ in range(n)]
            # Line 7: f must be invertible modulo q, i.e. NTT(f) has no
            # zero coefficient, i.e. gcd(f, x^n+1) = 1 over GF(q).
            if gcd(Fqx(f), Fqx.gen() ^ n + 1) != 1:
                continue
            if gram_gs_norm(f, g) > bound:
                continue
            F, G = NTRUSolve(f, g)
            if F is None:
                continue
            return f, g, F, G

    def Keygen(self, rng=None):
        r"""Algorithm 4.  Produce a private key (with its Falcon tree) and h."""
        f, g, F, G = self.NTRUGen(rng)
        return self._complete_key(f, g, F, G)

    def _complete_key(self, f, g, F, G):
        r"""Steps 2-11 of Algorithm 4, shared with key loading."""
        n = self.n
        B = dict(f=f, g=g, F=F, G=G)
        g_fft = fft([float(v) for v in g])
        f_fft = fft([float(v) for v in f])
        G_fft = fft([float(v) for v in G])
        F_fft = fft([float(v) for v in F])
        # B_hat = [[FFT(g), -FFT(f)], [FFT(G), -FFT(F)]]
        B_fft = [[g_fft, neg_fft(f_fft)], [G_fft, neg_fft(F_fft)]]

        # The Gram matrix G = B_hat x B_hat*.
        G00 = add_fft(mul_fft(B_fft[0][0], adj_fft(B_fft[0][0])),
                      mul_fft(B_fft[0][1], adj_fft(B_fft[0][1])))
        G01 = add_fft(mul_fft(B_fft[0][0], adj_fft(B_fft[1][0])),
                      mul_fft(B_fft[0][1], adj_fft(B_fft[1][1])))
        G10 = adj_fft(G01)
        G11 = add_fft(mul_fft(B_fft[1][0], adj_fft(B_fft[1][0])),
                      mul_fft(B_fft[1][1], adj_fft(B_fft[1][1])))

        T = ffLDL_fft(G00, G01, G10, G11)
        normalize_tree(T, self.sigma)

        h = self.public_from_fg(f, g)
        sk = dict(B, B_fft=B_fft, T=T, f_fft=f_fft, F_fft=F_fft)
        return sk, h

    def public_from_fg(self, f, g):
        r"""Step 9 of Algorithm 4: h = g * f^{-1} mod (x^n + 1, q)."""
        n = self.n
        phi = Fqx.gen() ^ n + 1
        finv = Fqx(f).inverse_mod(phi)
        h = (Fqx(g) * finv) % phi
        c = h.list() + [Fq(0)] * n
        return [int(v) for v in c[:n]]

    # ------------------------- Section 3.9 ---------------------------

    def Sign(self, m, sk, rng=None, salt=None):
        r"""Algorithm 10.  Sign the message m, returning (salt, compressed s2)."""
        if rng is None:
            rng = RandomBytes()
        n, q = self.n, self.q

        # Lines 1-3.  The salt and the target c are drawn once, outside
        # both loops: a compression failure re-samples the signature, not
        # the salt.
        r = os.urandom(40) if salt is None else bytes(salt)
        c = HashToPoint(r + bytes(m), q, n)
        c_fft = fft([float(v) for v in c])

        # t = (FFT(c), FFT(0)) * B_hat^{-1}, using B_hat^{-1} = (1/q) *
        # [[-F, f], [-G, g]] since det B_hat = f*G - g*F = q.
        t0 = [-(u * v) / q for u, v in zip(c_fft, sk['F_fft'])]
        t1 = [(u * v) / q for u, v in zip(c_fft, sk['f_fft'])]

        while True:                                   # line 4: until s != bot
            while True:                               # line 5: until ||s|| ok
                z0, z1 = ffSampling(t0, t1, sk['T'], self.sigmin, rng)
                d0 = sub_fft(t0, z0)
                d1 = sub_fft(t1, z1)
                B = sk['B_fft']
                s0 = add_fft(mul_fft(d0, B[0][0]), mul_fft(d1, B[1][0]))
                s1 = add_fft(mul_fft(d0, B[0][1]), mul_fft(d1, B[1][1]))
                s1_poly = [int(round(float(v))) for v in ifft(s0)]
                s2_poly = [int(round(float(v))) for v in ifft(s1)]
                if _sqnorm(s1_poly, s2_poly) <= self.sig_bound:
                    break

            s = Compress(s2_poly, self.slen)
            if s is not None:
                return r, s

    def Verify(self, m, sig, h):
        r"""Algorithm 16.  Verify a signature against the public key h."""
        n, q = self.n, self.q
        r, s = sig
        s2 = Decompress(s, self.slen, n)
        if s2 is None:
            return False
        c = HashToPoint(bytes(r) + bytes(m), q, n)
        phi = Fqx.gen() ^ n + 1
        s1p = (Fqx(c) - Fqx([v % q for v in s2]) * Fqx(h)) % phi
        coeffs = s1p.list() + [Fq(0)] * n
        s1 = []
        for v in coeffs[:n]:
            v = int(v)
            s1.append(v - q if v > q // 2 else v)
        return _sqnorm(s1, s2) <= self.sig_bound

    # ------------------------ Section 3.11 ---------------------------
    #
    # FIPS 206 note: the encodings below are the round-3 Falcon formats.
    # They are the part of this file most likely to be respecified.

    def encode_public_key(self, h):
        r"""Section 3.11.4.  Header byte 0000nnnn, then 14 bits per coefficient."""
        out = bytes([self.logn])
        acc = 0
        accbits = 0
        buf = bytearray()
        for v in h:
            acc = (acc << 14) | (int(v) & 0x3FFF)
            accbits += 14
            while accbits >= 8:
                accbits -= 8
                buf.append((acc >> accbits) & 0xFF)
        return out + bytes(buf)

    def decode_public_key(self, data):
        r"""Section 3.11.4, inverse."""
        if len(data) != self.pk_bytelen or data[0] != self.logn:
            raise ValueError("bad public key encoding")
        acc = 0
        accbits = 0
        h = []
        pos = 1
        while len(h) < self.n:
            while accbits < 14:
                acc = (acc << 8) | data[pos]
                pos += 1
                accbits += 8
            accbits -= 14
            v = (acc >> accbits) & 0x3FFF
            if v >= self.q:
                raise ValueError("public key coefficient out of range")
            h.append(v)
        return h

    def encode_private_key(self, f, g, F):
        r"""Section 3.11.5.  Header 0101nnnn, then f, g, F; G is recomputed."""
        return (bytes([0x50 + self.logn])
                + _pack_signed(f, self.fg_bits)
                + _pack_signed(g, self.fg_bits)
                + _pack_signed(F, 8))

    def decode_private_key(self, data):
        r"""Section 3.11.5, inverse.  G comes from G = (q + g*F)/f mod phi."""
        n = self.n
        if data[0] != 0x50 + self.logn:
            raise ValueError("bad private key header")
        fw = n * self.fg_bits // 8
        pos = 1
        f = _unpack_signed(data[pos:pos + fw], self.fg_bits, n)
        pos += fw
        g = _unpack_signed(data[pos:pos + fw], self.fg_bits, n)
        pos += fw
        F = _unpack_signed(data[pos:pos + n], 8, n)

        # Equation (3.35): G = (q + g*F)/f in Z[x]/(x^n+1).  Since
        # x^n+1 is the 2n-th cyclotomic polynomial it is irreducible
        # over Q, so Q[x]/(x^n+1) is a field and the division is exact.
        gF = _cyclo_mul(g, F, n)
        num = list(gF)
        num[0] += self.q
        K = QQx.quotient(QQx.gen() ^ n + 1, 'y')
        Gq = (K(num) / K(list(f))).lift().list()
        Gq = Gq + [QQ(0)] * (n - len(Gq))
        G = [int(v) for v in Gq]
        return f, g, F, G

    def load_private_key(self, data):
        r"""Decode a private key and rebuild its Falcon tree."""
        f, g, F, G = self.decode_private_key(data)
        return self._complete_key(f, g, F, G)

    # --------------------- Section 3.11.6, NIST API -------------------

    def encode_signature(self, sig):
        r"""The nonce-less signature format: header 0010nnnn, then s."""
        r, s = sig
        return bytes([0x20 + self.logn]) + bytes(s)

    def sign_nist(self, m, sk, rng=None):
        r"""crypto_sign: 2-byte length, nonce, message, then the signature."""
        r, s = self.Sign(m, sk, rng)
        sigval = self.encode_signature((r, s))
        return (len(sigval).to_bytes(2, 'big') + bytes(r) + bytes(m) + sigval)

    def open_nist(self, sm, h):
        r"""crypto_sign_open: unpack the aggregate format and verify."""
        siglen = int.from_bytes(sm[0:2], 'big')
        r = sm[2:42]
        m = sm[42:len(sm) - siglen]
        sigval = sm[len(sm) - siglen:]
        if sigval[0] != 0x20 + self.logn:
            return None
        # Section 3.11.3: signatures are normally padded with zeros to
        # sbytelen, but verifiers may also accept the shorter unpadded
        # form, which is what the Falcon reference KATs contain.  Padding
        # back with zeros recovers the fixed-length encoding that
        # Decompress expects; any non-zero padding is rejected there.
        s = sigval[1:]
        if len(s) > self.slen // 8:
            return None
        s = s.ljust(self.slen // 8, b"\x00")
        if not self.Verify(m, (r, s), h):
            return None
        return m


# ---------------------------------------------------------------------
# Cross-checks against Sage's exact arithmetic.
# ---------------------------------------------------------------------

def verify_fft_against_exact_ring(n=64, trials=3, seed=0):
    r"""
    Check the CDF floating-point layer against exact arithmetic in
    Z[x]/(x^n+1):

      1. ifft(fft(f)) recovers f;
      2. mergefft inverts splitfft;
      3. pointwise multiplication in FFT form reproduces the exact
         product computed by Sage in the quotient ring.
    """
    set_random_seed(seed)
    for _ in range(trials):
        f = [ZZ.random_element(-50, 50) for _ in range(n)]
        g = [ZZ.random_element(-50, 50) for _ in range(n)]

        back = ifft(fft([float(v) for v in f]))
        assert max(abs(float(a) - float(b)) for a, b in zip(back, f)) < 1e-6, \
            "ifft . fft != id"

        ff = fft([float(v) for v in f])
        a, b = split_fft(ff)
        assert max(abs(u - v) for u, v in zip(merge_fft(a, b), ff)) < 1e-6, \
            "mergefft . splitfft != id"

        exact = _cyclo_mul(f, g, n)
        approx = ifft(mul_fft(fft([float(v) for v in f]), fft([float(v) for v in g])))
        assert max(abs(float(u) - float(v)) for u, v in zip(approx, exact)) < 1e-3, \
            "FFT multiplication disagrees with Z[x]/(x^n+1)"
    return True


def verify_ntru_equation(f, g, F, G, q=FALCON_q):
    r"""Check f*G - g*F = q exactly in Z[x]/(x^n+1), using Sage integers."""
    n = len(f)
    lhs = _sub(_cyclo_mul(f, G, n), _cyclo_mul(g, F, n))
    want = [q] + [0] * (n - 1)
    assert lhs == want, "NTRU equation f*G - g*F = q does not hold"
    return True
