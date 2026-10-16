"""Reproduce #68(c), a separate fold-reader refresh limitation.

Run from the repository root through bench/capped, with PYTHONPATH=.
The cold query reaches 0.7459165 even at 5000 steps; a repeat or warming B
first reaches 0.74999998. No negation or shared-source revision is involved.
"""
import argparse

from pettachainer import PeTTaChainer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--steps', type=int, default=5000)
    args = parser.parse_args()
    for warm_b in (False, True):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a1 (A x) (STV 1 0.9))',
            '(: b1 (B x) (STV 0.7 0.9))',
            '(: c1 (C x) (STV 1 0.9))',
            '(: (no_inverse r1) (Implication (C $v) (B $v)) (STV 0.8 0.9))',
        ])
        if warm_b:
            print('warm B:', h.query_many_refs(['(: $p (B x) $tv)'], steps=args.steps), flush=True)
        for repeat in range(2):
            rows = h.query_many_refs(['(: $p (Implication (A x) (B x)) $tv)'], steps=args.steps)[0]
            print(f'{warm_b=} {repeat=}:',
                  [(row.tv, h.expand_proof(row.proof)) for row in rows], flush=True)


if __name__ == '__main__':
    main()
