---
title: The post-quantum problem Bitcoin layer 2s inherit
date: 2026-07-31
summary: Bitcoin's own migration plans do not cover what layer 2s build on top. A survey of where the exposure actually sits, with GOAT as a worked case study.
---

# The post-quantum problem Bitcoin layer 2s inherit

Most discussion of Bitcoin's post-quantum migration is about the base layer:
[BIP-360](https://github.com/bitcoin/bips/blob/master/bip-0360.mediawiki)'s
pay-to-quantum-resistant output type, and BIP-361's proposal to sunset the
signature schemes a quantum adversary would break. Those matter. But they solve
a problem layer 2s only partly share.

A layer 2 inherits the base layer's cryptography **and adds its own**. Even a
fully migrated Bitcoin leaves an L2 exposed wherever the L2 introduced an
assumption Bitcoin never made — a pairing-friendly curve, an aggregate
signature, a proof system with a discrete-log step buried in it. Those are not
fixed by anything happening at the base layer, and they are usually the parts
with the longest rebuild time.

We spent some time working through this on a real system rather than in the
abstract. The full write-up is at
[**AppliedPQC/btc-l2-pqc-research**](https://github.com/AppliedPQC/btc-l2-pqc-research);
this post is the short version.

## Three different axes, not one ranking

The tempting move is to rank the exposures from worst to least bad. That turns
out to be the wrong shape, because the severity depends on which question you
are asking:

- **How easy is it to attack?** The easiest target is usually the most ordinary
  one. A Taproot key-path spend, aggregated with MuSig2, is a single Schnorr
  key on a curve Shor breaks — no exotic cryptography required. The mitigation
  is available today and costs nothing to adopt: use a NUMS point so the key
  path is provably unspendable and force everything through the script path.

- **How long does the fix take?** Here the ordering inverts. Verifying a
  Groth16 proof on-chain means BN254 pairings, and BitVM2-style constructions
  are built *around* that verifier. Swapping the proof system is not a
  parameter change; it is a rebuild of the component. That is months of work
  regardless of how hard the underlying break is.

- **How much of the system does it touch?** An EVM layer is the broad one. It
  is easy to say "accounts use ECDSA" and stop there, but the precompiles are
  the real surface: `ecrecover`, the BN254 add/mul/pairing operations, and
  everything built on them. That is a lot of contract behaviour resting on
  assumptions that a migration has to preserve or explicitly break.

## What is already fine, and what surprised us

Some of the machinery is in better shape than expected. BitVM2's plumbing uses
Winternitz one-time signatures, which are hash-based and hold up fine — the
post-quantum weakness is not in the plumbing but in the Groth16 verifier it
carries.

The most interesting finding was in the proof system. It is easy to assume a
STARK-based core is post-quantum by construction, since STARKs rest on hashes.
That is not quite true in practice: a multiset memory-consistency check can use
a hash-to-group step whose soundness rests on discrete log. In Ziren's case
this is tracked as
[issue #276](https://github.com/ProjectZKM/Ziren/issues/276), and the fix —
replacing it with a lattice-free homomorphic hash such as LtHash — already has
a working prototype. So the gap is real, but it is narrow and someone is
already closing it.

That pattern held generally. The exposures are rarely where the marketing
material implies, and the fixes range from *free today* to *rebuild the
component*.

## Why write it down

None of this is a vulnerability disclosure. Nothing here is exploitable by
anything that exists. The point of doing the survey now is that the expensive
fixes are expensive because of engineering time, not cryptographic difficulty —
and engineering time is the one input you cannot buy at the last minute.

The [full document](https://github.com/AppliedPQC/btc-l2-pqc-research) covers
the general problem, the base-layer plans, the GOAT case study in detail, a
concrete list of what to do in what order, and a verification log recording
which claims were checked against source and which remain inference.
