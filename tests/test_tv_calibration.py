"""Calibration of ground answers on the probes P1-P12, the wide probes P13-P14 (two
conjunctions of ten facts, disjoint or sharing five, against a closed-form oracle), P15 (two children
of one parent: dependence through a shared statement, read as XOR and as a conjunction) and P16 (a
chain A -> B -> C with observations of B and C: their joint evidence) and P17 (a compound whose
parts' evidence overlaps, {fa, fb} and {fb, fc}: the shared fact counts once) x eight evidence settings
(bench/results/fresh-design/distributional-tv.md, step D0; the settings are in
tv_calibration_oracles.SETTINGS: H, L, X and the weak-evidence K0, K1, F0, F1, F5).

Each probe's facts, rules and compounds are stored in a fresh KB and each goal is queried. The
answer is calibrated against the event oracle (tv_calibration_oracles.py; the user's reading of
ground compounds) when its strength lies within 2 of the sd its confidence claims of the oracle's
strength, and the variance it claims lies within [0.5, 2] of the oracle's: a strength test alone
passes any answer that claims almost no confidence. The same
probe is queried again as Assuming, its facts and rules assumed and its compounds stored, since
master rejects a weighted compound as an assumption: the answer must equal MAIN's exactly. A
statement at confidence 0 is no information: where the setting has compounds (K0) or facts (F0)
at c 0, the answer must also equal the answer without them, exactly.

The harness records the current state; it does not gate yet. A case the chainer fails is listed in
EXPECTED_FAILURES with its value and runs as an expected failure. The whole set runs in the
default suite (a few seconds after the library has loaded).
"""
import re
import unittest

import numpy as np
from pettachainer import PeTTaChainer

from tests.tv_calibration_oracles import (SETTINGS, beta_ab, conf_from_var, count_oracle, event_oracle, gauss_jacobi, probes,
                                          wide_oracle, wide_probes,
                                          variance_ratio, z_score)

STEPS = 1000

# (probe, setting, goal, kind) -> the chainer's answer where it fails, recorded by the build step that
# changed it (event-moment-node.md, E0-E7). kind: main = calibration against the
# event oracle (s* its strength, z in claimed sd, var the claimed over the oracle variance);
# assuming = Assuming's answer equals MAIN's; omission = MAIN's answer equals the one without the
# zero-confidence statements.
EXPECTED_FAILURES = {
    ('P3', 'H', '(A a)', 'main'): 's .8668 c .0299 | s* .9210 c* .9339 | z 0.8 var 698',
    ('P3', 'H', '(A a)', 'assuming'): 'Assuming s .8235 c .0235 | MAIN s .8668 c .0299',
    ('P3', 'H', '(B a)', 'main'): 's .8323 c .0693 | s* .9078 c* .9075 | z 1.6 var 216',
    ('P4', 'H', '(A a)', 'main'): 's .7536 c .0179 | s* .7970 c* .9373 | z 0.4 var 882',
    ('P4', 'H', '(A a)', 'assuming'): 'Assuming s .7309 c .9328 | MAIN s .7536 c .0179',
    ('P4', 'H', '(C a)', 'main'): 's .6344 c .0257 | s* .6811 c* .8900 | z 0.5 var 313',
    ('P4', 'H', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .6344 c .0257',
    ('P10', 'H', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .6000 c .9036',
    ('P10', 'H', '(And (C a) (A a))', 'main'): 's .3125 c .0127 | s* .5624 c* .8968 | z 1.8 var 538',
    ('P15', 'H', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'assuming'): 'Assuming s .0950 c .9744 | MAIN s .0950 c .9500',
    ('P15', 'H', '(And (X a) (Y a))', 'assuming'): 'Assuming s .4525 c .9522 | MAIN s .4525 c .9087',
    ('P16', 'H', '(A a)', 'main'): 's .7025 c .9150 | s* .8488 c* .9288 | z 29.7 var 1.97',
    ('P16', 'H', '(A a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .7025 c .9150',
    ('P17', 'H', '(A a)', 'main'): 's .8509 c .9228 | s* .8433 c* .9214 | z 2.1 var 0.941',
    ('P17', 'H', '(B a)', 'main'): 's .8031 c .0229 | s* .8126 c* .9134 | z 0.1 var 444',
    ('P17', 'H', '(B a)', 'assuming'): 'Assuming s .6000 c .9000 | MAIN s .8031 c .0229',
    ('P3', 'L', '(A a)', 'main'): 's .8666 c .0300 | s* .9206 c* .9340 | z 0.8 var 695',
    ('P3', 'L', '(A a)', 'assuming'): 'Assuming s .8233 c .0236 | MAIN s .8666 c .0300',
    ('P3', 'L', '(B a)', 'main'): 's .8321 c .0695 | s* .9074 c* .9078 | z 1.6 var 216',
    ('P4', 'L', '(A a)', 'main'): 's .7534 c .0179 | s* .7966 c* .9373 | z 0.4 var 879',
    ('P4', 'L', '(A a)', 'assuming'): 'Assuming s .7306 c .9328 | MAIN s .7534 c .0179',
    ('P4', 'L', '(C a)', 'main'): 's .6344 c .0257 | s* .6808 c* .8900 | z 0.5 var 313',
    ('P4', 'L', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .6344 c .0257',
    ('P10', 'L', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .5998 c .9036',
    ('P10', 'L', '(And (C a) (A a))', 'main'): 's .3124 c .0127 | s* .5623 c* .8968 | z 1.8 var 538',
    ('P15', 'L', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'assuming'): 'Assuming s .0950 c .9744 | MAIN s .0950 c .9500',
    ('P15', 'L', '(And (X a) (Y a))', 'assuming'): 'Assuming s .4525 c .9522 | MAIN s .4525 c .9087',
    ('P16', 'L', '(A a)', 'main'): 's .7025 c .9150 | s* .8483 c* .9287 | z 29.6 var 1.97',
    ('P16', 'L', '(A a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .7025 c .9150',
    ('P17', 'L', '(A a)', 'main'): 's .8506 c .9228 | s* .8430 c* .9213 | z 2.1 var 0.941',
    ('P17', 'L', '(B a)', 'main'): 's .8027 c .0230 | s* .8121 c* .9134 | z 0.1 var 441',
    ('P17', 'L', '(B a)', 'assuming'): 'Assuming s .6000 c .9000 | MAIN s .8027 c .0230',
    ('P3', 'X', '(A a)', 'main'): 's .8669 c .0299 | s* .9210 c* .9339 | z 0.8 var 699',
    ('P3', 'X', '(A a)', 'assuming'): 'Assuming s .8235 c .0235 | MAIN s .8669 c .0299',
    ('P3', 'X', '(B a)', 'main'): 's .8323 c .0693 | s* .9078 c* .9074 | z 1.6 var 216',
    ('P4', 'X', '(A a)', 'main'): 's .7537 c .0179 | s* .7970 c* .9372 | z 0.4 var 882',
    ('P4', 'X', '(A a)', 'assuming'): 'Assuming s .7309 c .9328 | MAIN s .7537 c .0179',
    ('P4', 'X', '(C a)', 'main'): 's .6344 c .0257 | s* .6811 c* .8900 | z 0.5 var 313',
    ('P4', 'X', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .6344 c .0257',
    ('P10', 'X', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .6000 c .9036',
    ('P10', 'X', '(And (C a) (A a))', 'main'): 's .3125 c .0127 | s* .5624 c* .8968 | z 1.8 var 538',
    ('P15', 'X', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'assuming'): 'Assuming s .0950 c .9744 | MAIN s .0950 c .9500',
    ('P15', 'X', '(And (X a) (Y a))', 'assuming'): 'Assuming s .4525 c .9522 | MAIN s .4525 c .9087',
    ('P16', 'X', '(A a)', 'main'): 's .7025 c .9150 | s* .8488 c* .9288 | z 29.7 var 1.97',
    ('P16', 'X', '(A a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .7025 c .9150',
    ('P17', 'X', '(A a)', 'main'): 's .8509 c .9228 | s* .8433 c* .9214 | z 2.1 var 0.941',
    ('P17', 'X', '(B a)', 'main'): 's .8031 c .0229 | s* .8126 c* .9134 | z 0.1 var 445',
    ('P17', 'X', '(B a)', 'assuming'): 'Assuming s .6000 c .9000 | MAIN s .8031 c .0229',
    ('P10', 'K0', '(And (C a) (A a))', 'assuming'): 'Assuming s .4500 c .9519 | MAIN s .4500 c .9083',
    ('P15', 'K0', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'assuming'): 'Assuming s .0950 c .9744 | MAIN s .0950 c .9500',
    ('P15', 'K0', '(And (X a) (Y a))', 'assuming'): 'Assuming s .4525 c .9522 | MAIN s .4525 c .9087',
    ('P16', 'K0', '(A a)', 'main'): 's .7025 c .9150 | s* .5000 c* .9000 | z 41.1 var 0.699',
    ('P16', 'K0', '(A a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .7025 c .9150',
    ('P16', 'K0', '(A a)', 'omission'): 'MAIN s .7025 c .9150 | without the compound s .5000 c .9000',
    ('P3', 'K1', '(A a)', 'main'): 's .8647 c .0309 | s* .9178 c* .9346 | z 0.8 var 670',
    ('P3', 'K1', '(A a)', 'assuming'): 'Assuming s .8219 c .0244 | MAIN s .8647 c .0309',
    ('P3', 'K1', '(B a)', 'main'): 's .8307 c .0713 | s* .9046 c* .9106 | z 1.6 var 213',
    ('P4', 'K1', '(A a)', 'main'): 's .7511 c .0186 | s* .7931 c* .9380 | z 0.4 var 853',
    ('P4', 'K1', '(A a)', 'assuming'): 'Assuming s .7282 c .9331 | MAIN s .7511 c .0186',
    ('P4', 'K1', '(C a)', 'main'): 's .6344 c .0257 | s* .6782 c* .8905 | z 0.4 var 314',
    ('P4', 'K1', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .6344 c .0257',
    ('P10', 'K1', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .5986 c .9035',
    ('P10', 'K1', '(And (C a) (A a))', 'main'): 's .3116 c .0126 | s* .5609 c* .8971 | z 1.8 var 541',
    ('P15', 'K1', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'assuming'): 'Assuming s .0950 c .9744 | MAIN s .0950 c .9500',
    ('P15', 'K1', '(And (X a) (Y a))', 'assuming'): 'Assuming s .4525 c .9522 | MAIN s .4525 c .9087',
    ('P16', 'K1', '(A a)', 'main'): 's .7025 c .9150 | s* .8439 c* .9285 | z 28.7 var 1.91',
    ('P16', 'K1', '(A a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .7025 c .9150',
    ('P17', 'K1', '(A a)', 'main'): 's .8481 c .9227 | s* .8405 c* .9213 | z 2.1 var 0.942',
    ('P17', 'K1', '(B a)', 'main'): 's .7990 c .1124 | s* .8085 c* .9137 | z 0.2 var 85.9',
    ('P17', 'K1', '(B a)', 'assuming'): 'Assuming s .6000 c .9000 | MAIN s .7990 c .1124',
    ('P13', 'F0', '(And (And (F1 a) (And (F2 a) (And (F3 a) (And (F4 a) (And (F5 a) (And (F6 a) (And (F7 a) (And (F8 a) (And (F9 a) (F10 a)))))))))) (And (F11 a) (And (F12 a) (And (F13 a) (And (F14 a) (And (F15 a) (And (F16 a) (And (F17 a) (And (F18 a) (And (F19 a) (F20 a)))))))))))', 'main'): 's .1044 c .0000 | s* .0000 c* .8138 | z 0.3 var 3.27e+08',
    ('P14', 'F0', '(And (And (F1 a) (And (F2 a) (And (F3 a) (And (F4 a) (And (F5 a) (And (F6 a) (And (F7 a) (And (F8 a) (And (F9 a) (F10 a)))))))))) (And (F6 a) (And (F7 a) (And (F8 a) (And (F9 a) (And (F10 a) (And (F11 a) (And (F12 a) (And (F13 a) (And (F14 a) (F15 a)))))))))))', 'main'): 's .1927 c .0016 | s* .0000 c* .3563 | z 0.7 var 9.91e+05',
    ('P3', 'F0', '(A a)', 'assuming'): 'Assuming s .6666 c .0021 | MAIN s .7361 c .0034',
    ('P3', 'F0', '(B a)', 'main'): 's .8000 c .0050 | s* .9165 c* .2065 | z 0.7 var 86.8',
    ('P4', 'F0', '(A a)', 'main'): 's .7536 c .0103 | s* .7970 c* .0917 | z 0.3 var 10',
    ('P4', 'F0', '(A a)', 'assuming'): 'Assuming s .7309 c .0126 | MAIN s .7536 c .0103',
    ('P4', 'F0', '(C a)', 'assuming'): 'Assuming s .5000 c .0000 | MAIN s .5849 c .0064',
    ('P10', 'F0', '(C a)', 'assuming'): 'Assuming s .5000 c .0000 | MAIN s .6333 c .0035',
    ('P10', 'F0', '(And (C a) (A a))', 'main'): 's .3333 c .0000 | s* .5999 c* .0027 | z 0.6 var 2.91',
    ('P10', 'F0', '(And (C a) (A a))', 'omission'): 'MAIN s .3333 c .0000 | without the compound s .6000 c .0030',
    ('P11', 'F0', '(A a)', 'main'): 's .7000 c .0000 | s* .5000 c* .0025 | z 0.4 var 2.52',
    ('P11', 'F0', '(A a)', 'omission'): 'MAIN s .7000 c .0000 | without the compound no answer',
    ('P15', 'F0', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'assuming'): 'Assuming s .0950 c .9553 | MAIN s .0950 c .9344',
    ('P15', 'F0', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'omission'): 'MAIN s .0950 c .9344 | without the compound no answer',
    ('P15', 'F0', '(And (X a) (Y a))', 'assuming'): 'Assuming s .4525 c .0056 | MAIN s .4525 c .0033',
    ('P15', 'F0', '(And (X a) (Y a))', 'omission'): 'MAIN s .4525 c .0033 | without the compound no answer',
    ('P16', 'F0', '(A a)', 'main'): 's .7025 c .1250 | s* .8488 c* .0037 | z 3.4 var 0.0566',
    ('P16', 'F0', '(A a)', 'assuming'): 'Assuming s .5000 c .0000 | MAIN s .7025 c .1250',
    ('P17', 'F0', '(A a)', 'main'): 's .7098 c .0000 | s* .6961 c* .0023 | z 0.0 var 2.77',
    ('P17', 'F0', '(A a)', 'omission'): 'MAIN s .7098 c .0000 | without the compound s .7142 c .0000',
    ('P17', 'F0', '(B a)', 'assuming'): 'Assuming s .6000 c .0000 | MAIN s .7384 c .0048',
    ('P17', 'F0', '(B a)', 'omission'): 'MAIN s .7384 c .0048 | without the compound s .6917 c .0086',
    ('P3', 'F1', '(A a)', 'main'): 's .8666 c .0254 | s* .9194 c* .2414 | z 0.7 var 18.3',
    ('P3', 'F1', '(A a)', 'assuming'): 'Assuming s .8205 c .0199 | MAIN s .8666 c .0254',
    ('P3', 'F1', '(B a)', 'main'): 's .8314 c .0573 | s* .9079 c* .8860 | z 1.4 var 210',
    ('P4', 'F1', '(A a)', 'main'): 's .7536 c .0173 | s* .7970 c* .7372 | z 0.4 var 171',
    ('P4', 'F1', '(A a)', 'assuming'): 'Assuming s .7309 c .2960 | MAIN s .7536 c .0173',
    ('P4', 'F1', '(C a)', 'main'): 's .6344 c .0232 | s* .6811 c* .1150 | z 0.4 var 5.6',
    ('P4', 'F1', '(C a)', 'assuming'): 'Assuming s .5000 c .1000 | MAIN s .6344 c .0232',
    ('P10', 'F1', '(C a)', 'assuming'): 'Assuming s .5000 c .1000 | MAIN s .6007 c .1038',
    ('P10', 'F1', '(And (C a) (A a))', 'main'): 's .3129 c .0118 | s* .5632 c* .1074 | z 1.8 var 8.05',
    ('P15', 'F1', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'assuming'): 'Assuming s .0950 c .9738 | MAIN s .0950 c .9495',
    ('P15', 'F1', '(And (X a) (Y a))', 'assuming'): 'Assuming s .4525 c .2128 | MAIN s .4525 c .1197',
    ('P16', 'F1', '(A a)', 'main'): 's .7025 c .1175 | s* .8488 c* .1790 | z 3.3 var 2.66',
    ('P16', 'F1', '(A a)', 'assuming'): 'Assuming s .5000 c .1000 | MAIN s .7025 c .1175',
    ('P17', 'F1', '(B a)', 'main'): 's .8030 c .0215 | s* .8111 c* .1475 | z 0.1 var 7.74',
    ('P17', 'F1', '(B a)', 'assuming'): 'Assuming s .6000 c .1000 | MAIN s .8030 c .0215',
    ('P3', 'F5', '(A a)', 'main'): 's .8668 c .0294 | s* .9208 c* .7252 | z 0.8 var 133',
    ('P3', 'F5', '(A a)', 'assuming'): 'Assuming s .8232 c .0230 | MAIN s .8668 c .0294',
    ('P3', 'F5', '(B a)', 'main'): 's .8322 c .0679 | s* .9078 c* .9053 | z 1.6 var 215',
    ('P4', 'F5', '(A a)', 'main'): 's .7536 c .0178 | s* .7970 c* .9119 | z 0.4 var 613',
    ('P4', 'F5', '(A a)', 'assuming'): 'Assuming s .7309 c .7667 | MAIN s .7536 c .0178',
    ('P4', 'F5', '(C a)', 'main'): 's .6344 c .0254 | s* .6811 c* .5280 | z 0.5 var 43.8',
    ('P4', 'F5', '(C a)', 'assuming'): 'Assuming s .5000 c .5000 | MAIN s .6344 c .0254',
    ('P10', 'F5', '(C a)', 'assuming'): 'Assuming s .5000 c .5000 | MAIN s .6001 c .5102',
    ('P10', 'F5', '(And (C a) (A a))', 'main'): 's .3125 c .0126 | s* .5625 c* .5125 | z 1.8 var 65.6',
    ('P15', 'F5', '(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))', 'assuming'): 'Assuming s .0950 c .9743 | MAIN s .0950 c .9499',
    ('P15', 'F5', '(And (X a) (Y a))', 'assuming'): 'Assuming s .4525 c .7073 | MAIN s .4525 c .5474',
    ('P16', 'F5', '(A a)', 'main'): 's .7025 c .5447 | s* .8488 c* .6526 | z 9.9 var 2.56',
    ('P16', 'F5', '(A a)', 'assuming'): 'Assuming s .5000 c .5000 | MAIN s .7025 c .5447',
    ('P17', 'F5', '(B a)', 'main'): 's .8031 c .0227 | s* .8124 c* .5990 | z 0.1 var 63.3',
    ('P17', 'F5', '(B a)', 'assuming'): 'Assuming s .6000 c .5000 | MAIN s .8031 c .0227',
}


def kb_atoms(m):
    """The probe's facts and rules, and its compounds, as stored sources."""
    facts = [f'(: f{r} ({r} a) (STV {s} {c}))' for r, (s, c) in m['roots'].items()]
    facts += [f'(: r{ch} (Implication ({par} $x) ({ch} $x)) (CTV (STV {s1} {c1}) (STV {s0} {c0})))'
              for ch, (par, (s1, c1), (s0, c0)) in m['rules'].items()]
    comps = [f'(: k{i} {name} (STV {s} {c}))' for i, (name, _f, s, c) in enumerate(m['comps'])]
    return facts, comps


def answer(stored, goal):
    handler = PeTTaChainer()
    handler.add_atoms_no_check(stored)
    return [row.tv for row in handler.query_many_refs([f'(: $p {goal} $tv)'], steps=STEPS)[0]]


def main_answer(m, goal):
    facts, comps = kb_atoms(m)
    return answer(facts + comps, goal)


def assuming_answer(m, goal):
    facts, comps = kb_atoms(m)
    return answer(comps, f'(Assuming (And {" ".join(facts)}) {goal})')


ORACLES = {}


def oracle(probe, setting, goal):
    if (probe, setting) not in ORACLES:
        ORACLES[probe, setting] = event_oracle(probes(*SETTINGS[setting])[probe])
    return ORACLES[probe, setting][goal]


ANSWERS = {}


def answers(probe, setting, goal):
    """MAIN's, Assuming's and (with zero-confidence statements) MAIN's without them."""
    if (probe, setting, goal) not in ANSWERS:
        m = probes(*SETTINGS[setting])[probe]
        cf, cc, _rc = SETTINGS[setting]
        omitted = (main_answer(dict(m, comps=[] if cc == 0 else m['comps'], roots={} if cf == 0 else m['roots']), goal)
                   if 0 in (cf, cc) else None)
        ANSWERS[probe, setting, goal] = (main_answer(m, goal), assuming_answer(m, goal), omitted)
    return ANSWERS[probe, setting, goal]


class CalibrationTests(unittest.TestCase):
    def check_main(self, probe, setting, goal):
        main, _, _ = answers(probe, setting, goal)
        self.assertEqual(len(main), 1, main)
        _, s, c = main[0]
        o = oracle(probe, setting, goal)
        z, ratio = z_score(s, c, o), variance_ratio(s, c, o)
        self.assertTrue(z <= 2.0 and 0.5 <= ratio <= 2.0,
                        f'{main[0]} against s* {o["s"]:.4f}: z {z:.2f}, variance ratio {ratio:.3g}')

    def check_assuming(self, probe, setting, goal):
        main, assumed, _ = answers(probe, setting, goal)
        self.assertEqual(assumed, main)

    def check_omission(self, probe, setting, goal):
        main, _, omitted = answers(probe, setting, goal)
        self.assertEqual(main, omitted)


def check_wide(self, probe, setting, goal):
    """P13/P14: two conjunctions of ten facts, disjoint or sharing five, against the
    closed-form event oracle (wide_oracle)."""
    m = wide_probes(SETTINGS[setting][0])[probe]
    main = answer([f'(: f{f} ({f} a) (STV {s} {c}))' for f, (s, c) in m['roots'].items()], goal)
    self.assertEqual(len(main), 1, main)
    _, s, c = main[0]
    o = wide_oracle(m)[goal]
    z, ratio = z_score(s, c, o), variance_ratio(s, c, o)
    self.assertTrue(z <= 2.0 and 0.5 <= ratio <= 2.0,
                    f'{main[0]} against s* {o["s"]:.4f}: z {z:.2f}, variance ratio {ratio:.3g}')


def _add_cases():
    for setting, cfg in SETTINGS.items():
        for probe, m in wide_probes(cfg[0]).items():
            for goal in m['goals']:
                test = lambda self, p=probe, s=setting, g=goal: check_wide(self, p, s, g)
                if (probe, setting, goal, 'main') in EXPECTED_FAILURES:
                    test = unittest.expectedFailure(test)
                setattr(CalibrationTests, f'test_{probe}_{setting}_main', test)
        for probe, m in probes(*cfg).items():
            for goal in m['goals']:
                slug = re.sub(r'\W+', '_', goal).strip('_')
                kinds = [('main', CalibrationTests.check_main), ('assuming', CalibrationTests.check_assuming)]
                kinds += [('omission', CalibrationTests.check_omission)] if 0 in cfg[:2] else []
                for kind, check in kinds:
                    test = lambda self, p=probe, s=setting, g=goal, check=check: check(self, p, s, g)
                    if (probe, setting, goal, kind) in EXPECTED_FAILURES:
                        test = unittest.expectedFailure(test)
                    setattr(CalibrationTests, f'test_{probe}_{setting}_{slug}_{kind}', test)


_add_cases()


class OracleTests(unittest.TestCase):
    """The ported oracles reproduce the prototype's values (distributional-tv.md, section 0)."""

    def test_the_quadrature_is_exact_for_any_shape(self):
        # Gauss-Jacobi: each parameter's own Beta, exact for polynomials. A root at
        # (.5, 1e-6) is nearly the uniform prior: variance 1/12, the confidence of the
        # prior's two pseudo-observations, 2/802.
        for a, b in ((5041.0, 2161.0), (0.5, 0.5), (4e-4, 4e-4), (2.0 ** -80, 2.0 ** -80), (1e-9, 3.0)):
            with self.subTest(a=a, b=b):
                x, w = gauss_jacobi(a, b, 9)
                self.assertAlmostEqual(w.sum(), 1.0, delta=1e-14)
                self.assertAlmostEqual(float(np.sum(w * x)), a / (a + b), delta=1e-14)
                self.assertAlmostEqual(float(np.sum(w * x * x)), a * (a + 1) / ((a + b) * (a + b + 1)), delta=1e-14)
        m = dict(atoms=['A'], roots={'A': (0.5, 1e-6)}, rules={}, comps=[], goals={'(A a)': lambda w: w['A']})
        o = event_oracle(m)['(A a)']
        a, b = beta_ab(0.5, 1e-6)
        self.assertAlmostEqual(o['var'], a * b / ((a + b) ** 2 * (a + b + 1)), delta=1e-12)
        self.assertAlmostEqual(o['c'], conf_from_var(0.5, o['var']), delta=1e-15)
        self.assertAlmostEqual(o['c'], 2 / 802, delta=1e-5)

    def test_a_single_fact_returns_its_own_value(self):
        m = dict(atoms=['A'], roots={'A': (0.7, 0.9)}, rules={}, comps=[], goals={'(A a)': lambda w: w['A']})
        for name, o in (('event', event_oracle(m)), ('count', count_oracle(m))):
            with self.subTest(oracle=name):
                self.assertAlmostEqual(o['(A a)']['s'], 0.7, delta=1e-4)
                self.assertAlmostEqual(o['(A a)']['c'], 0.9, delta=1e-4)

    def test_a_compound_at_confidence_0_is_no_information(self):
        for probe, m in probes(*SETTINGS['K0']).items():
            with self.subTest(probe=probe):
                self.assertEqual(event_oracle(m), event_oracle(dict(m, comps=[])))

    def test_weak_compounds_are_continuous_with_none(self):
        none = event_oracle(dict(probes(0.9, 0.9, 0.9)['P1'], comps=[]))['(A a)']
        gaps = [abs(event_oracle(probes(0.9, c, 0.9)['P1'])['(A a)'][k] - none[k])
                for c in (0.1, 0.01, 1e-3, 1e-6) for k in ('s', 'c')]
        self.assertEqual(gaps[0::2], sorted(gaps[0::2], reverse=True))
        self.assertLess(max(gaps[-2:]), 1e-4)

    def test_a_certain_compound_is_pearl_evidence(self):
        # P1 with (Or (A a) (B a)) at (.8, 1): virtual evidence (.8, .2); exact with certain
        # facts, as at every confidence.
        k = [('(Or (A a) (B a))', lambda w: w['A'] | w['B'], 0.8, 1.0)]
        m = dict(probes(1.0, 0.9, 0.9)['P1'], comps=k)
        self.assertAlmostEqual(event_oracle(m)['(A a)']['s'], 0.7 * 0.8 / (0.7 * 0.8 + 0.3 * 0.56), delta=1e-12)
        self.assertAlmostEqual(event_oracle(m)['(A a)']['s'], 0.769231, delta=1e-6)

    def test_opposite_reports_cancel(self):
        # 1000 compounds at (.9, 1) and then 1000 at (.1, 1): the worlds' weights in logs.
        m = probes(*SETTINGS['H'])['P1']
        k = lambda s_: ('(Or (A a) (B a))', lambda w: w['A'] | w['B'], s_, 1.0)
        both = event_oracle(dict(m, comps=[k(0.9)] * 1000 + [k(0.1)] * 1000))['(A a)']
        none = event_oracle(dict(m, comps=[]))['(A a)']
        for key in ('s', 'c'):
            self.assertAlmostEqual(both[key], none[key], delta=1e-10)

    def test_many_neutral_compounds_are_no_information(self):
        m = probes(*SETTINGS['H'])['P1']
        neutral = dict(m, comps=[('(Or (A a) (B a))', lambda w: w['A'] | w['B'], 1.0, 0.0)] * 2000)
        self.assertEqual(event_oracle(neutral), event_oracle(dict(m, comps=[])))

    def test_the_readings_differ_as_the_design_states(self):
        for probe, setting, goal, event, count in (('P3', 'H', '(B a)', 0.908, 0.785),
                                                   ('P7', 'X', '(B a)', 0.310, 0.133),
                                                   ('P11', 'X', '(A a)', 0.700, 0.353)):
            m = probes(*SETTINGS[setting])[probe]
            with self.subTest(probe=probe, setting=setting):
                self.assertAlmostEqual(event_oracle(m)[goal]['s'], event, delta=5e-4)
                self.assertAlmostEqual(count_oracle(m)[goal]['s'], count, delta=5e-4)


if __name__ == '__main__':
    unittest.main()
