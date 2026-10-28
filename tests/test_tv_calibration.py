"""Calibration of ground answers on the probes P1-P12, and the wide probes P13-P14 (two
conjunctions of ten facts, disjoint or sharing five, against a closed-form oracle) x eight evidence settings
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

The harness records the current state; it does not gate yet. A case master fails is listed in
EXPECTED_FAILURES with master's value and runs as an expected failure. The whole set runs in the
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

# (probe, setting, goal, kind) -> master's answer (3df60577). kind: main = calibration against the
# event oracle (s* its strength, z in claimed sd, var the claimed over the oracle variance);
# assuming = Assuming's answer equals MAIN's; omission = MAIN's answer equals the one without the
# zero-confidence statements.
EXPECTED_FAILURES = {
    ('P1', 'H', '(A a)', 'main'): 's .7414 c .9126 | s* .7954 c* .9106 | z 11.3 var 1.15',
    ('P2', 'H', '(And (A a) (B a))', 'main'): 's .4200 c .9190 | s* .4772 c* .9407 | z 11.0 var 1.37',
    ('P3', 'H', '(A a)', 'main'): 's .7000 c .9000 | s* .9210 c* .9339 | z 40.9 var 4.53',
    ('P3', 'H', '(B a)', 'main'): 's .8100 c .9494 | s* .9078 c* .9075 | z 30.5 var 0.96',
    ('P4', 'H', '(A a)', 'main'): 's .6948 c .9567 | s* .7970 c* .9373 | z 29.5 var 0.887',
    ('P4', 'H', '(C a)', 'main'): 's .5000 c .9000 | s* .6811 c* .8900 | z 30.7 var 1.03',
    ('P5', 'H', '(A a)', 'main'): 's .9993 c .9997 | s* .8860 c* .9327 | z 7779.1 var 2.33e-05',
    ('P5', 'H', '(B a)', 'main'): 's .6330 c .9075 | s* .6455 c* .9005 | z 2.3 var 0.937',
    ('P5', 'H', '(C a)', 'main'): 's .5412 c .9075 | s* .5570 c* .8962 | z 2.8 var 0.885',
    ('P6', 'H', '(A a)', 'main'): 's .7600 c .9184 | s* .7887 c* .9088 | z 6.4 var 0.97',
    ('P6', 'H', '(B a)', 'main'): 's .6800 c .9184 | s* .7183 c* .9005 | z 7.8 var 0.865',
    ('P6', 'H', '(C a)', 'main'): 's .5000 c .9000 | s* .7042 c* .8945 | z 34.7 var 1.13',
    ('P7', 'H', '(A a)', 'main'): 's .3500 c .9474 | s* .4828 c* .8521 | z 33.4 var 0.292',
    ('P7', 'H', '(B a)', 'main'): 's .3000 c .9474 | s* .3104 c* .8662 | z 2.7 var 0.353',
    ('P8', 'H', '(K a)', 'main'): 's .7189 c .9280 | s* .7567 c* .9251 | z 8.5 var 1.05',
    ('P9', 'H', '(A a)', 'main'): 's .7414 c .9126 | s* .7954 c* .9106 | z 11.3 var 1.15',
    ('P9', 'H', '(And (A a) (B a))', 'main'): 's .4200 c .9190 | s* .4772 c* .9407 | z 11.0 var 1.37',
    ('P10', 'H', '(C a)', 'main'): 's .9000 c .8841 | s* .6000 c* .8938 | z 78.1 var 0.414',
    ('P10', 'H', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .9000 c .8841',
    ('P10', 'H', '(And (C a) (A a))', 'main'): 's .5000 c .9000 | s* .5624 c* .8968 | z 10.6 var 0.98',
    ('P12', 'H', '(A a)', 'main'): 's .7872 c .9269 | s* .8860 c* .9327 | z 24.3 var 1.81',
    ('P12', 'H', '(B a)', 'main'): 's .6217 c .9049 | s* .6456 c* .9005 | z 4.3 var 0.978',
    ('P12', 'H', '(C a)', 'main'): 's .5313 c .9057 | s* .5570 c* .8962 | z 4.5 var 0.907',
    ('P1', 'L', '(A a)', 'main'): 's .7052 c .9016 | s* .7953 c* .9106 | z 16.9 var 1.42',
    ('P2', 'L', '(And (A a) (B a))', 'main'): 's .4200 c .9190 | s* .4771 c* .9407 | z 11.0 var 1.37',
    ('P3', 'L', '(A a)', 'main'): 's .7000 c .9000 | s* .9206 c* .9340 | z 40.9 var 4.52',
    ('P3', 'L', '(B a)', 'main'): 's .7140 c .9287 | s* .9074 c* .9078 | z 43.7 var 1.84',
    ('P4', 'L', '(A a)', 'main'): 's .5742 c .9386 | s* .7966 c* .9373 | z 49.7 var 1.48',
    ('P4', 'L', '(C a)', 'main'): 's .5000 c .9000 | s* .6808 c* .8900 | z 30.7 var 1.03',
    ('P5', 'L', '(A a)', 'main'): 's .9993 c .9996 | s* .8858 c* .9327 | z 6433.8 var 3.42e-05',
    ('P5', 'L', '(B a)', 'main'): 's .6039 c .9009 | s* .6455 c* .9005 | z 7.2 var 1.04',
    ('P5', 'L', '(C a)', 'main'): 's .5049 c .9009 | s* .5569 c* .8962 | z 8.9 var 0.962',
    ('P6', 'L', '(A a)', 'main'): 's .7081 c .9024 | s* .7885 c* .9089 | z 15.2 var 1.34',
    ('P6', 'L', '(B a)', 'main'): 's .6108 c .9024 | s* .7181 c* .9005 | z 18.9 var 1.15',
    ('P6', 'L', '(C a)', 'main'): 's .5000 c .9000 | s* .7039 c* .8946 | z 34.6 var 1.13',
    ('P7', 'L', '(A a)', 'main'): 's .6300 c .9091 | s* .4832 c* .8522 | z 27.2 var 0.538',
    ('P7', 'L', '(B a)', 'main'): 's .5400 c .9091 | s* .3110 c* .8664 | z 41.1 var 0.752',
    ('P8', 'L', '(K a)', 'main'): 's .6936 c .9234 | s* .7566 c* .9252 | z 13.4 var 1.18',
    ('P9', 'L', '(A a)', 'main'): 's .7052 c .9016 | s* .7953 c* .9106 | z 16.9 var 1.42',
    ('P9', 'L', '(And (A a) (B a))', 'main'): 's .4200 c .9190 | s* .4771 c* .9407 | z 11.0 var 1.37',
    ('P10', 'L', '(C a)', 'main'): 's .9000 c .8840 | s* .5998 c* .8938 | z 78.1 var 0.414',
    ('P10', 'L', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .9000 c .8840',
    ('P10', 'L', '(And (C a) (A a))', 'main'): 's .5000 c .9000 | s* .5623 c* .8968 | z 10.6 var 0.981',
    ('P12', 'L', '(A a)', 'main'): 's .7130 c .9039 | s* .8858 c* .9327 | z 33.1 var 2.98',
    ('P12', 'L', '(B a)', 'main'): 's .6037 c .9008 | s* .6455 c* .9005 | z 7.3 var 1.04',
    ('P12', 'L', '(C a)', 'main'): 's .5047 c .9009 | s* .5569 c* .8962 | z 8.9 var 0.962',
    ('P1', 'X', '(A a)', 'main'): 's .8913 c .9613 | s* .7954 c* .9106 | z 43.4 var 0.244',
    ('P2', 'X', '(And (A a) (B a))', 'main'): 's .4200 c .9190 | s* .4772 c* .9407 | z 11.0 var 1.37',
    ('P3', 'X', '(A a)', 'main'): 's .7000 c .9000 | s* .9210 c* .9339 | z 40.9 var 4.53',
    ('P4', 'X', '(A a)', 'main'): 's .9062 c .9822 | s* .7970 c* .9372 | z 78.6 var 0.142',
    ('P4', 'X', '(C a)', 'main'): 's .5000 c .9000 | s* .6811 c* .8900 | z 30.7 var 1.03',
    ('P5', 'X', '(A a)', 'main'): 's .9993 c .9998 | s* .8861 c* .9327 | z 7993.1 var 2.21e-05',
    ('P5', 'X', '(B a)', 'main'): 's .7990 c .9471 | s* .6456 c* .9005 | z 45.8 var 0.355',
    ('P5', 'X', '(C a)', 'main'): 's .7487 c .9471 | s* .5570 c* .8962 | z 52.9 var 0.367',
    ('P6', 'X', '(A a)', 'main'): 's .8500 c .9474 | s* .7887 c* .9088 | z 20.6 var 0.424',
    ('P6', 'X', '(B a)', 'main'): 's .8000 c .9474 | s* .7183 c* .9005 | z 24.5 var 0.397',
    ('P6', 'X', '(C a)', 'main'): 's .5000 c .9000 | s* .7042 c* .8945 | z 34.7 var 1.13',
    ('P7', 'X', '(A a)', 'main'): 's .3500 c .9474 | s* .4827 c* .8520 | z 33.4 var 0.292',
    ('P7', 'X', '(B a)', 'main'): 's .3000 c .9474 | s* .3104 c* .8662 | z 2.7 var 0.353',
    ('P8', 'X', '(K a)', 'main'): 's .8239 c .9351 | s* .7567 c* .9251 | z 18.9 var 0.676',
    ('P9', 'X', '(A a)', 'main'): 's .8913 c .9613 | s* .7954 c* .9106 | z 43.4 var 0.244',
    ('P9', 'X', '(And (A a) (B a))', 'main'): 's .4200 c .9190 | s* .4772 c* .9407 | z 11.0 var 1.37',
    ('P10', 'X', '(C a)', 'main'): 's .9000 c .8841 | s* .6000 c* .8938 | z 78.1 var 0.414',
    ('P10', 'X', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .9000 c .8841',
    ('P10', 'X', '(And (C a) (A a))', 'main'): 's .5000 c .9000 | s* .5624 c* .8968 | z 10.6 var 0.98',
    ('P12', 'X', '(A a)', 'main'): 's .9456 c .9802 | s* .8861 c* .9327 | z 52.2 var 0.143',
    ('P12', 'X', '(B a)', 'main'): 's .6263 c .9059 | s* .6456 c* .9005 | z 3.5 var 0.961',
    ('P10', 'K0', '(C a)', 'main'): 's .9000 c .0008 | s* .5000 c* .9000 | z 1.7 var 1.59e+03',
    ('P10', 'K0', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .9000 c .0008',
    ('P10', 'K0', '(C a)', 'omission'): 'MAIN s .9000 c .0008 | without the compound s .5000 c .9000',
    ('P10', 'K0', '(And (C a) (A a))', 'main'): 's .8100 c .0030 | s* .4499 c* .9083 | z 1.7 var 1.43e+03',
    ('P10', 'K0', '(And (C a) (A a))', 'assuming'): 'Assuming s .4500 c .9519 | MAIN s .8100 c .0030',
    ('P10', 'K0', '(And (C a) (A a))', 'omission'): 'MAIN s .8100 c .0030 | without the compound s .4500 c .9083',
    ('P1', 'K1', '(A a)', 'main'): 's .7006 c .9002 | s* .7942 c* .9107 | z 17.4 var 1.45',
    ('P2', 'K1', '(And (A a) (B a))', 'main'): 's .4200 c .9190 | s* .4765 c* .9404 | z 10.9 var 1.36',
    ('P3', 'K1', '(A a)', 'main'): 's .7000 c .9000 | s* .9178 c* .9346 | z 40.3 var 4.42',
    ('P3', 'K1', '(B a)', 'main'): 's .6929 c .9234 | s* .9046 c* .9106 | z 45.1 var 2.08',
    ('P4', 'K1', '(A a)', 'main'): 's .5528 c .9354 | s* .7931 c* .9380 | z 52.0 var 1.58',
    ('P4', 'K1', '(C a)', 'main'): 's .5000 c .9000 | s* .6782 c* .8905 | z 30.2 var 1.04',
    ('P5', 'K1', '(A a)', 'main'): 's .9993 c .9985 | s* .8834 c* .9327 | z 3350.1 var 0.000129',
    ('P5', 'K1', '(B a)', 'main'): 's .6004 c .9001 | s* .6449 c* .9006 | z 7.7 var 1.05',
    ('P5', 'K1', '(C a)', 'main'): 's .5005 c .9001 | s* .5562 c* .8963 | z 9.5 var 0.972',
    ('P6', 'K1', '(A a)', 'main'): 's .7009 c .9003 | s* .7873 c* .9089 | z 16.0 var 1.38',
    ('P6', 'K1', '(B a)', 'main'): 's .6012 c .9003 | s* .7164 c* .9007 | z 20.0 var 1.19',
    ('P6', 'K1', '(C a)', 'main'): 's .5000 c .9000 | s* .7011 c* .8950 | z 34.1 var 1.13',
    ('P7', 'K1', '(A a)', 'main'): 's .6915 c .9011 | s* .4868 c* .8536 | z 37.8 var 0.547',
    ('P7', 'K1', '(B a)', 'main'): 's .5927 c .9011 | s* .3159 c* .8680 | z 48.1 var 0.806',
    ('P8', 'K1', '(K a)', 'main'): 's .6904 c .9227 | s* .7559 c* .9252 | z 13.8 var 1.2',
    ('P9', 'K1', '(A a)', 'main'): 's .7006 c .9002 | s* .7942 c* .9107 | z 17.4 var 1.45',
    ('P9', 'K1', '(And (A a) (B a))', 'main'): 's .4200 c .9190 | s* .4765 c* .9404 | z 10.9 var 1.36',
    ('P10', 'K1', '(C a)', 'main'): 's .9000 c .8838 | s* .5986 c* .8940 | z 78.4 var 0.416',
    ('P10', 'K1', '(C a)', 'assuming'): 'Assuming s .5000 c .9000 | MAIN s .9000 c .8838',
    ('P10', 'K1', '(And (C a) (A a))', 'main'): 's .5000 c .9000 | s* .5609 c* .8971 | z 10.3 var 0.984',
    ('P12', 'K1', '(A a)', 'main'): 's .7014 c .9004 | s* .8842 c* .9325 | z 34.0 var 3.12',
    ('P12', 'K1', '(B a)', 'main'): 's .6004 c .9001 | s* .6455 c* .9006 | z 7.8 var 1.05',
    ('P12', 'K1', '(C a)', 'main'): 's .5005 c .9001 | s* .5566 c* .8963 | z 9.5 var 0.971',
    ('P1', 'F0', '(A a)', 'assuming'): 'Assuming s .7000 c .0000 | MAIN s .8500 c .0000',
    ('P1', 'F0', '(A a)', 'omission'): 'MAIN s .8500 c .0000 | without the compound no answer',
    ('P2', 'F0', '(And (A a) (B a))', 'main'): 's .4200 c .0000 | s* .3333 c* .0045 | z 0.2 var 5.04',
    ('P2', 'F0', '(And (A a) (B a))', 'assuming'): 'Assuming no answer | MAIN s .4200 c .0000',
    ('P2', 'F0', '(And (A a) (B a))', 'omission'): 'MAIN s .4200 c .0000 | without the compound no answer',
    ('P3', 'F0', '(A a)', 'main'): 's .7000 c .0000 | s* .8332 c* .0036 | z 0.3 var 5.83',
    ('P3', 'F0', '(A a)', 'omission'): 'MAIN s .7000 c .0000 | without the compound no answer',
    ('P3', 'F0', '(B a)', 'main'): 's .6900 c .0053 | s* .9165 c* .2065 | z 1.1 var 112',
    ('P3', 'F0', '(B a)', 'omission'): 'MAIN s .6900 c .0053 | without the compound no answer',
    ('P4', 'F0', '(A a)', 'main'): 's .6948 c .0497 | s* .7970 c* .0917 | z 1.5 var 2.5',
    ('P4', 'F0', '(A a)', 'omission'): 'MAIN s .6948 c .0497 | without the compound no answer',
    ('P4', 'F0', '(C a)', 'main'): 's .5000 c .0000 | s* .6811 c* .0027 | z 0.4 var 3.66',
    ('P4', 'F0', '(C a)', 'omission'): 'MAIN s .5000 c .0000 | without the compound no answer',
    ('P5', 'F0', '(A a)', 'main'): 's .8500 c .0000 | s* .7999 c* .0022 | z 0.1 var 2.17',
    ('P5', 'F0', '(A a)', 'assuming'): 'Assuming s .7000 c .0000 | MAIN s .8500 c .0000',
    ('P5', 'F0', '(A a)', 'omission'): 'MAIN s .8500 c .0000 | without the compound no answer',
    ('P5', 'F0', '(B a)', 'assuming'): 'Assuming s .6000 c .0000 | MAIN s .8000 c .0000',
    ('P5', 'F0', '(B a)', 'omission'): 'MAIN s .8000 c .0000 | without the compound no answer',
    ('P5', 'F0', '(C a)', 'main'): 's .7500 c .0000 | s* .6000 c* .0022 | z 0.3 var 2.17',
    ('P5', 'F0', '(C a)', 'assuming'): 'Assuming s .5000 c .0000 | MAIN s .7500 c .0000',
    ('P5', 'F0', '(C a)', 'omission'): 'MAIN s .7500 c .0000 | without the compound no answer',
    ('P6', 'F0', '(A a)', 'assuming'): 'Assuming s .7000 c .0000 | MAIN s .8500 c .0000',
    ('P6', 'F0', '(A a)', 'omission'): 'MAIN s .8500 c .0000 | without the compound no answer',
    ('P6', 'F0', '(B a)', 'assuming'): 'Assuming s .6000 c .0000 | MAIN s .8000 c .0000',
    ('P6', 'F0', '(B a)', 'omission'): 'MAIN s .8000 c .0000 | without the compound no answer',
    ('P6', 'F0', '(C a)', 'main'): 's .5000 c .0000 | s* .7999 c* .0022 | z 0.6 var 4.26',
    ('P6', 'F0', '(C a)', 'omission'): 'MAIN s .5000 c .0000 | without the compound no answer',
    ('P7', 'F0', '(A a)', 'main'): 's .3500 c .0000 | s* .3334 c* .0021 | z 0.0 var 2.77',
    ('P7', 'F0', '(A a)', 'omission'): 'MAIN s .3500 c .0000 | without the compound s .0000 c .0000',
    ('P7', 'F0', '(B a)', 'main'): 's .3000 c .0000 | s* .3334 c* .0021 | z 0.1 var 2.56',
    ('P7', 'F0', '(B a)', 'omission'): 'MAIN s .3000 c .0000 | without the compound s .0000 c .0000',
    ('P8', 'F0', '(K a)', 'assuming'): 'Assuming s .6900 c .0053 | MAIN s .7950 c .0037',
    ('P8', 'F0', '(K a)', 'omission'): 'MAIN s .7950 c .0037 | without the compound no answer',
    ('P9', 'F0', '(A a)', 'assuming'): 'Assuming s .7000 c .0000 | MAIN s .8500 c .0000',
    ('P9', 'F0', '(A a)', 'omission'): 'MAIN s .8500 c .0000 | without the compound no answer',
    ('P9', 'F0', '(And (A a) (B a))', 'main'): 's .4200 c .0000 | s* .3333 c* .0045 | z 0.2 var 5.04',
    ('P9', 'F0', '(And (A a) (B a))', 'assuming'): 'Assuming no answer | MAIN s .4200 c .0000',
    ('P9', 'F0', '(And (A a) (B a))', 'omission'): 'MAIN s .4200 c .0000 | without the compound no answer',
    ('P10', 'F0', '(C a)', 'assuming'): 'Assuming s .5000 c .0000 | MAIN s .9000 c .0005',
    ('P10', 'F0', '(C a)', 'omission'): 'MAIN s .9000 c .0005 | without the compound no answer',
    ('P10', 'F0', '(And (C a) (A a))', 'assuming'): 'Assuming s .4500 c .0056 | MAIN s .8100 c .0023',
    ('P10', 'F0', '(And (C a) (A a))', 'omission'): 'MAIN s .8100 c .0023 | without the compound no answer',
    ('P11', 'F0', '(A a)', 'main'): 's .3500 c .0000 | s* .5000 c* .0025 | z 0.3 var 2.73',
    ('P11', 'F0', '(A a)', 'assuming'): 'Assuming s .7000 c .0000 | MAIN s .3500 c .0000',
    ('P11', 'F0', '(A a)', 'omission'): 'MAIN s .3500 c .0000 | without the compound no answer',
    ('P12', 'F0', '(A a)', 'assuming'): 'Assuming s .7000 c .0000 | MAIN s .9250 c .0000',
    ('P12', 'F0', '(A a)', 'omission'): 'MAIN s .9250 c .0000 | without the compound no answer',
    ('P12', 'F0', '(B a)', 'assuming'): 'Assuming s .6000 c .0000 | MAIN s .8000 c .0000',
    ('P12', 'F0', '(B a)', 'omission'): 'MAIN s .8000 c .0000 | without the compound no answer',
    ('P12', 'F0', '(C a)', 'main'): 's .7500 c .0000 | s* .6000 c* .0022 | z 0.3 var 2.17',
    ('P12', 'F0', '(C a)', 'assuming'): 'Assuming s .5000 c .0000 | MAIN s .7500 c .0000',
    ('P12', 'F0', '(C a)', 'omission'): 'MAIN s .7500 c .0000 | without the compound no answer',
    ('P1', 'F1', '(A a)', 'main'): 's .9785 c .6079 | s* .7926 c* .1132 | z 45.1 var 0.0106',
    ('P3', 'F1', '(A a)', 'main'): 's .7000 c .1000 | s* .9194 c* .2414 | z 4.5 var 8.06',
    ('P3', 'F1', '(B a)', 'main'): 's .8100 c .4685 | s* .9079 c* .8860 | z 6.6 var 16.2',
    ('P4', 'F1', '(A a)', 'main'): 's .6948 c .6025 | s* .7970 c* .7372 | z 7.7 var 2.42',
    ('P4', 'F1', '(C a)', 'main'): 's .5000 c .1000 | s* .6811 c* .1150 | z 3.4 var 1.34',
    ('P5', 'F1', '(A a)', 'main'): 's 1.0000 c .9985 | s* .8843 c* .1465 | z 29577.9 var 2.07e-08',
    ('P5', 'F1', '(B a)', 'main'): 's .9517 c .4792 | s* .6443 c* .1024 | z 38.9 var 0.0251',
    ('P5', 'F1', '(C a)', 'main'): 's .9396 c .4792 | s* .5578 c* .0981 | z 43.5 var 0.0275',
    ('P6', 'F1', '(A a)', 'main'): 's .8500 c .1818 | s* .7850 c* .1109 | z 2.4 var 0.426',
    ('P6', 'F1', '(B a)', 'main'): 's .8000 c .1818 | s* .7159 c* .1020 | z 2.8 var 0.404',
    ('P6', 'F1', '(C a)', 'main'): 's .5000 c .1000 | s* .7063 c* .0965 | z 3.9 var 1.16',
    ('P7', 'F1', '(A a)', 'main'): 's .3500 c .1818 | s* .4790 c* .0683 | z 3.6 var 0.304',
    ('P7', 'F1', '(B a)', 'main'): 's .3000 c .1818 | s* .3116 c* .0758 | z 0.3 var 0.365',
    ('P8', 'F1', '(K a)', 'main'): 's .8849 c .8625 | s* .7548 c* .2259 | z 28.9 var 0.0257',
    ('P9', 'F1', '(A a)', 'main'): 's .9785 c .6079 | s* .7926 c* .1132 | z 45.1 var 0.0106',
    ('P10', 'F1', '(C a)', 'main'): 's .9000 c .2321 | s* .6006 c* .0969 | z 15.5 var 0.134',
    ('P10', 'F1', '(C a)', 'assuming'): 'Assuming s .5000 c .1000 | MAIN s .9000 c .2321',
    ('P12', 'F1', '(A a)', 'main'): 's .9912 c .7916 | s* .8843 c* .1465 | z 63.2 var 0.00387',
    ('P1', 'F5', '(A a)', 'main'): 's .8770 c .7092 | s* .7951 c* .5314 | z 11.0 var 0.308',
    ('P2', 'F5', '(And (A a) (B a))', 'main'): 's .4200 c .5577 | s* .4769 c* .6387 | z 3.7 var 1.37',
    ('P3', 'F5', '(A a)', 'main'): 's .7000 c .5000 | s* .9208 c* .7252 | z 13.6 var 7.59',
    ('P3', 'F5', '(B a)', 'main'): 's .8100 c .8603 | s* .9078 c* .9053 | z 17.5 var 2.85',
    ('P4', 'F5', '(A a)', 'main'): 's .6948 c .9031 | s* .7970 c* .9119 | z 19.2 var 1.46',
    ('P4', 'F5', '(C a)', 'main'): 's .5000 c .5000 | s* .6811 c* .5280 | z 10.2 var 1.29',
    ('P5', 'F5', '(A a)', 'main'): 's .9999 c .9996 | s* .8858 c* .6065 | z 19331.9 var 4.25e-07',
    ('P5', 'F5', '(B a)', 'main'): 's .7789 c .6440 | s* .6454 c* .5020 | z 12.2 var 0.42',
    ('P5', 'F5', '(C a)', 'main'): 's .7236 c .6440 | s* .5571 c* .4901 | z 14.2 var 0.431',
    ('P6', 'F5', '(A a)', 'main'): 's .8500 c .6667 | s* .7883 c* .5259 | z 6.9 var 0.424',
    ('P6', 'F5', '(B a)', 'main'): 's .8000 c .6667 | s* .7180 c* .5017 | z 8.2 var 0.398',
    ('P6', 'F5', '(C a)', 'main'): 's .5000 c .5000 | s* .7044 c* .4857 | z 11.6 var 1.13',
    ('P7', 'F5', '(A a)', 'main'): 's .3500 c .6667 | s* .4824 c* .3909 | z 11.1 var 0.293',
    ('P7', 'F5', '(B a)', 'main'): 's .3000 c .6667 | s* .3105 c* .4190 | z 0.9 var 0.354',
    ('P8', 'F5', '(K a)', 'main'): 's .8139 c .8364 | s* .7565 c* .7041 | z 9.4 var 0.383',
    ('P9', 'F5', '(A a)', 'main'): 's .8770 c .7092 | s* .7951 c* .5314 | z 11.0 var 0.308',
    ('P9', 'F5', '(And (A a) (B a))', 'main'): 's .4200 c .5577 | s* .4769 c* .6387 | z 3.7 var 1.37',
    ('P10', 'F5', '(C a)', 'main'): 's .9000 c .6892 | s* .6000 c* .4863 | z 42.1 var 0.16',
    ('P10', 'F5', '(C a)', 'assuming'): 'Assuming s .5000 c .5000 | MAIN s .9000 c .6892',
    ('P10', 'F5', '(And (C a) (A a))', 'main'): 's .5000 c .5000 | s* .5625 c* .5125 | z 3.5 var 1.07',
    ('P12', 'F5', '(A a)', 'main'): 's .9360 c .8242 | s* .8859 c* .6065 | z 12.6 var 0.195',
    ('P13', 'F0', '(And (And (F1 a) (And (F2 a) (And (F3 a) (And (F4 a) (And (F5 a) (And (F6 a) (And (F7 a) (And (F8 a) (And (F9 a) (F10 a)))))))))) (And (F11 a) (And (F12 a) (And (F13 a) (And (F14 a) (And (F15 a) (And (F16 a) (And (F17 a) (And (F18 a) (And (F19 a) (F20 a)))))))))))', 'main'): 's 0.1044 c 0.0000 | s* 0.0000 c* 0.8138 | z 0.3 var 3.27e+08',
    ('P14', 'F0', '(And (And (F1 a) (And (F2 a) (And (F3 a) (And (F4 a) (And (F5 a) (And (F6 a) (And (F7 a) (And (F8 a) (And (F9 a) (F10 a)))))))))) (And (F6 a) (And (F7 a) (And (F8 a) (And (F9 a) (And (F10 a) (And (F11 a) (And (F12 a) (And (F13 a) (And (F14 a) (F15 a)))))))))))', 'main'): 's 0.1927 c 0.0016 | s* 0.0000 c* 0.3563 | z 0.7 var 9.91e+05',
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
