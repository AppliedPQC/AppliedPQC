# =====================================================================
#  common.sage -- shared primitives for the FIPS 203/204/205/206
#                 SageMath reference implementations.
#
#  Nothing here is algorithm-specific.  It provides the sponge functions
#  that all four standards draw on, plus a small incremental-squeeze
#  wrapper around SHAKE, because Python's hashlib exposes only a
#  one-shot `digest(n)`.
# =====================================================================

import hashlib
from hashlib import sha3_256, sha3_512, shake_128, shake_256, sha256, sha512


# The NIST hash-algorithm arc 2.16.840.1.101.3.4.2.x, as DER-encoded OIDs
# together with their digest functions.  FIPS 204 (Algorithms 4 and 5) and
# FIPS 205 (Algorithms 23 and 25) both select a pre-hash function from
# this table; the standards spell out a few cases and leave the rest to
# the OID arc.
def _der_oid(last):
    return bytes([0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, last])


NIST_PREHASH = {
    'SHA2-256':     (_der_oid(0x01), lambda M: hashlib.sha256(M).digest()),
    'SHA2-384':     (_der_oid(0x02), lambda M: hashlib.sha384(M).digest()),
    'SHA2-512':     (_der_oid(0x03), lambda M: hashlib.sha512(M).digest()),
    'SHA2-224':     (_der_oid(0x04), lambda M: hashlib.sha224(M).digest()),
    'SHA2-512/224': (_der_oid(0x05), lambda M: hashlib.new('sha512_224', M).digest()),
    'SHA2-512/256': (_der_oid(0x06), lambda M: hashlib.new('sha512_256', M).digest()),
    'SHA3-224':     (_der_oid(0x07), lambda M: hashlib.sha3_224(M).digest()),
    'SHA3-256':     (_der_oid(0x08), lambda M: hashlib.sha3_256(M).digest()),
    'SHA3-384':     (_der_oid(0x09), lambda M: hashlib.sha3_384(M).digest()),
    'SHA3-512':     (_der_oid(0x0A), lambda M: hashlib.sha3_512(M).digest()),
    'SHAKE-128':    (_der_oid(0x0B), lambda M: hashlib.shake_128(M).digest(32)),
    'SHAKE-256':    (_der_oid(0x0C), lambda M: hashlib.shake_256(M).digest(64)),
}


def SHAKE128(data, outlen):
    r"""SHAKE128(`data`, 8 * `outlen`) as a byte string of length `outlen`."""
    return shake_128(bytes(data)).digest(int(outlen))


def SHAKE256(data, outlen):
    r"""SHAKE256(`data`, 8 * `outlen`) as a byte string of length `outlen`."""
    return shake_256(bytes(data)).digest(int(outlen))


def SHA3_256(data):
    return sha3_256(bytes(data)).digest()


def SHA3_512(data):
    return sha3_512(bytes(data)).digest()


def SHA256(data):
    return sha256(bytes(data)).digest()


def SHA512(data):
    return sha512(bytes(data)).digest()


class XOF(object):
    r"""
    An incremental extendable-output function.

    FIPS 203 and FIPS 204 both use SHAKE in a streaming ``Init / Absorb /
    Squeeze`` pattern: the rejection samplers pull a few bytes at a time
    and stop as soon as enough coefficients have been accepted.  Python's
    ``hashlib`` has no streaming squeeze, but SHAKE output is a prefix
    family -- ``digest(m)`` extends ``digest(n)`` for ``n <= m`` -- so a
    growing buffer reproduces the streaming interface exactly.

    Blocks are grown a keccak rate at a time (168 bytes for SHAKE128,
    136 for SHAKE256), which is also how a real implementation squeezes.
    """

    def __init__(self, data=b"", bits=128):
        self._bits = int(bits)
        self._rate = 168 if self._bits == 128 else 136
        self._absorbed = bytearray(data)
        self._buf = b""
        self._pos = 0

    def absorb(self, data):
        r"""Append more input.  Only legal before the first squeeze."""
        if self._pos:
            raise ValueError("cannot absorb after squeezing has begun")
        self._absorbed += bytearray(data)
        return self

    def _grow(self, need):
        if need <= len(self._buf):
            return
        blocks = -(-need // self._rate)
        outlen = blocks * self._rate
        h = shake_128 if self._bits == 128 else shake_256
        self._buf = h(bytes(self._absorbed)).digest(int(outlen))

    def squeeze(self, nbytes):
        r"""Return the next `nbytes` output bytes of the stream."""
        nbytes = int(nbytes)
        self._grow(self._pos + nbytes)
        out = self._buf[self._pos:self._pos + nbytes]
        self._pos += nbytes
        return out
