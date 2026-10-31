"""The event moment node's polynomial moments (pettachainer/metta/prolog/event_node.pl) against the D0 oracles
and the acceptance cases of bench/results/fresh-design/event-moment-node.md, section 2b: the mean is
exact, constant-Z variance is exact and varying-Z variance is conservative, the coupling
interval holds the truth, and a widened answer holds its interval within 2 sd."""
import itertools
import math
import os
import re
import unittest

import janus_swi as janus
import numpy as np

from tests.tv_calibration_oracles import (SETTINGS, beta_ab, event_oracle, gauss_jacobi, params, point_value,
                                          predictive, probes, wide_oracle, wide_probes)

MODULE = os.path.join(os.path.dirname(__file__), '..', 'pettachainer', 'metta', 'prolog', 'event_node.pl')
janus.consult(os.path.abspath(MODULE))


def q(name):
    return "'" + name.replace("'", "\\'") + "'"


def dist(s, c):
    p = point_value(s, c)
    return f'point({p!r})' if p is not None else 'beta({!r}, {!r})'.format(*beta_ab(s, c))


def moments(variables, terms, goals):
    """variables: [(id, dist text)], terms: [(coef, [(id, bit)], [goal index])]; -> [(s, v, how)]."""
    text = 'node([{}], [{}], [{}])'.format(
        ', '.join(f'{q(i)}-{d}' for i, d in variables),
        ', '.join('t({!r}, [{}], [{}])'.format(c, ', '.join(f'{q(i)}-{b}' for i, b in lits), ', '.join(map(str, gs)))
                  for c, lits, gs in terms),
        ', '.join(map(str, range(1, goals + 1))))
    out = janus.query_once('term_string(node(_Vs, _Ts, _Gs), T), event_node:event_node_moments(_Vs, _Ts, _Gs, _As), '
                           '( _As == inconsistent -> Out = inconsistent ; findall([_S, _V, _H], member(a(_S, _V, _H), _As), Out) )',
                           {'T': text})
    return out['Out']


def probe_node(m):
    """The probe's network as a node: root strengths and rule branches as parameters, each world a
    term with its compounds' Pearl factors (c = 0 dropped) as the coefficient."""
    ps = params(m)
    comps = [(predictive(s, c), f) for _n, f, s, c in m['comps'] if c > 0]
    goals = list(m['goals'])
    terms = []
    for bits in itertools.product((False, True), repeat=len(m['atoms'])):
        w = dict(zip(m['atoms'], (np.bool_(b) for b in bits)))
        lits = [('f_' + r, int(w[r])) for r in m['roots']]
        lits += [(ch + ('|1' if w[par] else '|0'), int(w[ch])) for ch, (par, _b1, _b0) in m['rules'].items()]
        coef = math.prod(mk if f(w) else 1 - mk for mk, f in comps)
        if coef > 0:
            terms.append((coef, lits, [i + 1 for i, g in enumerate(goals) if m['goals'][g](w)]))
    return [(k, dist(*sc)) for k, sc in ps.items()], terms, goals


def quadrature(shapes, terms, goals, nodes=17):
    """The oracle's answer for a node of Beta parameters x0, x1, ...: s* = E[N]/E[Z] and
    Var* = E[N^2/Z]/E[Z] - s*^2 on the tensor Gauss-Jacobi rule of the parameters' own Betas."""
    rules = [gauss_jacobi(a, b, nodes) for a, b in shapes]
    EZ, EN, EH = 0.0, np.zeros(goals), np.zeros(goals)
    for point in itertools.product(*[range(nodes)] * len(shapes)):
        x = {f'x{i}': rules[i][0][j] for i, j in enumerate(point)}
        w = math.prod(rules[i][1][j] for i, j in enumerate(point))
        weights = [c * math.prod(x[k] if bit else 1 - x[k] for k, bit in lits) for c, lits, _gs in terms]
        Z = sum(weights)
        N = np.array([sum(wt for wt, (_c, _l, gs) in zip(weights, terms) if g + 1 in gs) for g in range(goals)])
        EZ += w * Z
        EN += w * N
        EH += w * N * N / Z
    s = EN / EZ
    return list(zip(s, EH / EZ - s * s))


def fuzz_cases(count=300, seed=11):
    """Random nodes for the empirical calibration check: 1-6 independent atoms whose
    probabilities are Beta, Bernoulli or point parameters, up to three evidence factors (an atom,
    an And or an Xor of two atoms, at weak, strong or opposing lambda) and two goals (an atom, an
    And, an Xor). Yields (parameter texts, terms, [(s*, var*)]) with the brute-force answer:
    tensor Gauss-Jacobi (33 nodes) over at most 3 Betas, else 1e6 Monte Carlo draws, both on
    var* = E[(N - s* Z)^2 / Z] / E[Z] with s* = E[N] / E[Z] exact."""
    rng = np.random.default_rng(seed)
    shapes = [0.5, 1.0, 2.0, 5.0, 20.0, 100.0]
    for _ in range(count):
        k = int(rng.integers(1, 7))
        params = []
        for i in range(k):
            kind = rng.choice(['beta', 'beta', 'bernoulli', 'point'])
            if kind == 'beta':
                params.append(('beta', float(rng.choice(shapes)), float(rng.choice(shapes))))
            else:
                params.append((str(kind), float(rng.uniform(0.05, 0.95))))
        pick = lambda: tuple(int(x) for x in rng.choice(k, size=min(2, k), replace=False))

        def structure():
            atoms = pick()
            shape = rng.choice(['atom', 'and', 'xor']) if len(atoms) == 2 else 'atom'
            if shape == 'atom':
                return lambda w, i=atoms[0]: w[i]
            if shape == 'and':
                return lambda w, i=atoms[0], j=atoms[1]: w[i] & w[j]
            return lambda w, i=atoms[0], j=atoms[1]: w[i] ^ w[j]
        factors = [(structure(), float(rng.choice([0.5 + rng.uniform(-0.05, 0.05), 0.9, 0.1, 0.99, 0.01])))
                   for _ in range(int(rng.integers(0, 4)))]
        goals = [structure(), structure()]
        worlds = list(itertools.product((0, 1), repeat=k))
        terms = []
        for w in worlds:
            coef = math.prod(m if f(w) else 1 - m for f, m in factors)
            terms.append((coef, [(f'x{i}', b) for i, b in enumerate(w)], [g + 1 for g in range(2) if goals[g](w)]))
        texts = [(f'x{i}', 'beta({!r}, {!r})'.format(p[1], p[2]) if p[0] == 'beta' else f'{p[0]}({p[1]!r})')
                 for i, p in enumerate(params)]
        yield texts, terms, brute_force(params, worlds, terms)


def brute_force(params, worlds, terms):
    betas = [i for i, p in enumerate(params) if p[0] == 'beta']
    W = np.array([[float(b) for b in w] for w in worlds])           # worlds x k
    coef = np.array([c for c, _l, _g in terms])
    goal = np.array([[1.0 if g + 1 in gs else 0.0 for g in range(2)] for _c, _l, gs in terms])
    if len(betas) <= 3:
        axes = []
        for p in params:
            if p[0] == 'beta':
                axes.append(gauss_jacobi(p[1], p[2], 33))
            elif p[0] == 'bernoulli':
                axes.append((np.array([0.0, 1.0]), np.array([1 - p[1], p[1]])))
            else:
                axes.append((np.array([p[1]]), np.ones(1)))
        grids = np.meshgrid(*[a for a, _ in axes], indexing='ij')
        wts = np.ones_like(grids[0])
        for i, (_a, wi) in enumerate(axes):
            wts = wts * wi.reshape([len(wi) if j == i else 1 for j in range(len(axes))])
        theta, wts = np.stack([g.ravel() for g in grids], axis=1), wts.ravel()
    else:
        rng = np.random.default_rng(5)
        cols = []
        for p in params:
            if p[0] == 'beta':
                cols.append(rng.beta(p[1], p[2], 1_000_000))
            elif p[0] == 'bernoulli':
                cols.append((rng.random(1_000_000) < p[1]).astype(float))
            else:
                cols.append(np.full(1_000_000, p[1]))
        theta, wts = np.stack(cols, axis=1), np.full(1_000_000, 1e-6)
    P = np.prod(np.where(W[None, :, :] == 1.0, theta[:, None, :], 1.0 - theta[:, None, :]), axis=2)   # points x worlds
    Zs = (P * coef).sum(axis=1)
    Ns = (P * coef) @ goal                                            # points x goals
    EZ = np.sum(wts * Zs)
    s = (wts @ Ns) / EZ
    safe = np.where(Zs > 0, Zs, 1.0)
    var = (wts @ np.where(Zs[:, None] > 0, (Ns - s * Zs[:, None]) ** 2 / safe[:, None], 0.0)) / EZ
    return list(zip(s, var))


def or_node(b):
    """Uniform a, b a constant, (Or A B) certain; goal A. Exact: s = 1 / (2 E[Z]),
    E[a^2 / Z] = 1/(2c) - b/c^2 + b^2/c^3 ln(1/b) with c = 1 - b, E[Z] = b + c/2."""
    terms = [(1.0, [('a', 1), ('b', 1)], [1]), (1.0, [('a', 1), ('b', 0)], [1]), (1.0, [('a', 0), ('b', 1)], [])]
    c = 1 - b
    ez = b + c / 2
    s = 0.5 / ez
    var = (1 / (2 * c) - b / c ** 2 + b ** 2 / c ** 3 * math.log(1 / b)) / ez - s * s
    return [('a', 'beta(1.0, 1.0)'), ('b', f'point({b!r})')], terms, s, var


class EventNodeTests(unittest.TestCase):
    def test_concentrated_stationary_xor_has_exact_interaction_variance(self):
        terms = [(1., [('x', x), ('y', y)], [1] if x != y else [])
                 for x, y in itertools.product((0, 1), repeat=2)]
        for a in (1, 100, 1000, 3601):
            with self.subTest(a=a):
                (s, v, kind), = moments([('x', f'beta({a},{a})'), ('y', f'beta({a},{a})')], terms, 1)
                self.assertEqual(kind, 'exact')
                self.assertEqual(s, .5)
                self.assertAlmostEqual(v/(1/(4*(2*a+1)**2)), 1, delta=1e-12)

    def test_eight_concentrated_betas_use_the_closed_ratio_bound(self):
        variables = [(f'x{i}', 'beta(3601,3601)') for i in range(8)]
        every = [(f'x{i}', 1) for i in range(8)]
        (s, v, kind), = moments(variables, [(1., [], []), (1., every, [1])], 1)
        mean = .5**8
        variance = (3602/(2*7203))**8-mean**2
        # N=P, Z=1+P, D=(P-E[P])/(1+E[P]).
        q = variance/(1+mean)**2
        expected = (q+(1-s)*math.sqrt(variance*q))/(1+mean)**2
        self.assertEqual(kind, 'conservative')
        self.assertAlmostEqual(s, 1/257, delta=1e-15)
        self.assertAlmostEqual(v/expected, 1, delta=1e-10)

    def test_parameter_distributions(self):
        # A view keeps its moments: at c = 0 the variance s(1 - s) is Bernoulli(s)'s, and a
        # strength of 0 or 1 below c = 1 a Beta whose shapes are clipped at 1e-12, so every
        # other strength keeps its mean (only c = 1 is a point); a stored count at c = 0
        # is the uniform prior.
        cases = (('stored', 0.7, 0.9, 'beta', (5041.0, 2161.0)), ('view', 0.7, 0.9, 'beta', (5040.0, 2160.0)),
                 ('stored', 0.4, 1.0, 'point', (0.4,)), ('stored', 0.4, 0.0, 'beta', (1.0, 1.0)),
                 ('view', 0.4, 0.0, 'bernoulli', (0.4,)), ('view', 0.0, 0.5, 'beta', (1.0e-12, 800.0)),
                 ('view', 1.0, 0.5, 'beta', (800.0, 1.0e-12)),
                 ('view', 1.0e-12, 0.999999, 'beta', (0.0007999992, 799999199.9992)))
        for kind, s, c, head, args in cases:
            with self.subTest(kind=kind, s=s, c=c):
                got = janus.query_once('event_node:event_node_dist(K, S, C, 800.0, _D), _D =.. [H|As]',
                                       {'K': kind, 'S': s, 'C': c})
                self.assertEqual(got['H'], head)
                np.testing.assert_allclose(got['As'], args, rtol=1e-9)

    def test_d0_probes_mean_exact_variance_exact_or_conservative(self):
        for setting, cfg in SETTINGS.items():
            for name, m in probes(*cfg).items():
                variables, terms, goals = probe_node(m)
                oracle = event_oracle(dict(m, comps=[k for k in m['comps'] if k[3] > 0]))
                for (s, v, how), g in zip(moments(variables, terms, len(goals)), goals):
                    with self.subTest(probe=name, setting=setting, goal=g):
                        self.assertAlmostEqual(s, oracle[g]['s'], delta=1e-9)
                        if how == 'exact':
                            self.assertAlmostEqual(v / oracle[g]['var'], 1, delta=1e-7)
                        else:
                            self.assertGreaterEqual(v, (1-1e-7)*oracle[g]['var'])

    def test_wide_products_have_constant_z(self):
        for setting, cfg in SETTINGS.items():
            for name, m in wide_probes(cfg[0]).items():
                for goal in m['goals']:
                    atoms = sorted(set(re.findall(r'\((F\d+) a\)', goal)))
                    variables = [('f_' + a, dist(*m['roots'][a])) for a in atoms]
                    every = [('f_' + a, 1) for a in atoms]
                    terms = [(1.0, [], []), (-1.0, every, []), (1.0, every, [1])]
                    (s, v, how), = moments(variables, terms, 1)
                    o = wide_oracle(m)[goal]
                    with self.subTest(probe=name, setting=setting):
                        self.assertAlmostEqual(s, o['s'], delta=1e-12)
                        if how == 'exact':
                            self.assertTrue(0.5 <= v / o['var'] <= 2.0, (v, o['var']))
                        else:
                            self.assertGreaterEqual(v, o['var'])

    def test_twelve_uniforms_under_a_weak_conjunction_report_never_understate(self):
        # Codex's case: first-order quadrature alone claims .134 of the variance (m .6).
        every = [(f'x{i}', 1) for i in range(12)]
        variables = [(f'x{i}', 'beta(1.0, 1.0)') for i in range(12)]
        for mk, exact in ((0.6, 4.02e-6), (0.9, 1.20e-4)):
            with self.subTest(m=mk):
                terms = [(1 - mk, [], []), (-(1 - mk), every, []), (mk, every, [1])]
                (s, v, how), = moments(variables, terms, 1)
                self.assertAlmostEqual(s, mk * 0.5 ** 12 / ((1 - mk) + (2 * mk - 1) * 0.5 ** 12), delta=1e-15)
                self.assertGreaterEqual(v, exact)

    def test_a_uniform_part_against_a_certain_disjunction(self):
        # Codex's cases: b = 1/2 gives 2/3 (an expansion about the prior gave 50/81); towards b = 0
        # every fixed rule understates the variance, so the node refines or claims the bound.
        for b in (0.5, 0.1, 0.01, 0.001, 1e-4):
            with self.subTest(b=b):
                variables, terms, s_star, var = or_node(b)
                (s, v, how), = moments(variables, terms, 1)
                self.assertAlmostEqual(s, s_star, delta=1e-12)
                self.assertGreaterEqual(v, 0.5 * var, how)
        self.assertAlmostEqual(moments(*or_node(0.5)[:2], 1)[0][0], 2 / 3, delta=1e-12)

    def test_weak_nuisances_do_not_hide_a_thin_boundary(self):
        p, m = 1e-6, .5000000001
        terms = []
        for a, b, *cs in itertools.product((0, 1), repeat=5):
            if not (a or b):
                continue
            coefficient = p if a else 1-p
            for c in cs:
                coefficient *= m if a and c else 1-m
            terms.append((coefficient, list(zip(('b', 'c1', 'c2', 'c3'), (b, *cs))), [1] if a else []))
        variables = [(name, 'beta(1.0, 1.0)') for name in ('b', 'c1', 'c2', 'c3')]
        # Integrating each c exactly gives a likelihood .5 on A and 1-m
        # otherwise. Only b's thin boundary remains numerically difficult.
        prior = p * .5**3 / (p * .5**3 + (1-p) * (1-m)**3)
        mean = 2*prior/(1+prior)
        variance = prior**2 * (-math.log(prior)/(1-prior))/((1+prior)/2) - mean**2
        (s, v, kind), = moments(variables, terms, 1)
        self.assertEqual(kind, 'conservative')
        self.assertAlmostEqual(s, mean, delta=1e-15)
        self.assertGreaterEqual(v, variance)

    def test_tiny_complement_keeps_its_positive_variance(self):
        epsilon = 1e-9
        b = 1 - epsilon
        integral = -1 / b**2 - 1 / (2 * b) - math.log(epsilon) / b**3
        expected = epsilon**2 * integral / ((1 + epsilon) / 2) - (epsilon / (1 + epsilon))**2
        terms = [(1.0, [('p', 1)], [1]), (epsilon, [('p', 0)], [2])]
        actual = moments([('p', 'beta(1.0, 1.0)')], terms, 2)
        for s, variance, kind in actual:
            self.assertEqual(kind, 'conservative')
            self.assertGreaterEqual(variance, expected)
            # Q=epsilon^2 Var(p)/E[Z]^2; the closed bound simplifies to this.
            bound = 2*epsilon*(1-epsilon)/(3*(1+epsilon)**3)
            self.assertAlmostEqual(variance / bound, 1, delta=1e-7)
        self.assertAlmostEqual(actual[0][0], 1 / (1 + epsilon), delta=1e-15)
        self.assertAlmostEqual(actual[1][0], epsilon / (1 + epsilon), delta=1e-20)

    def test_no_possible_world_is_inconsistent(self):
        self.assertEqual(moments([('a', 'point(1.0)')], [(1.0, [('a', 0)], [1])], 1), 'inconsistent')

    def test_xor_of_two_uniforms_without_evidence(self):
        # Every one-parameter slice of XOR is constant at the other's mean 1/2, so a first-order
        # estimate sees no variance; Z is constant and the exact moments give 1/36.
        terms = [(1.0, [('x0', 1), ('x1', 0)], [1]), (1.0, [('x0', 0), ('x1', 1)], [1]),
                 (1.0, [('x0', 1), ('x1', 1)], []), (1.0, [('x0', 0), ('x1', 0)], [])]
        (s, v, how), = moments([('x0', 'beta(1.0, 1.0)'), ('x1', 'beta(1.0, 1.0)')], terms, 1)
        self.assertEqual(how, 'exact')
        self.assertAlmostEqual(s, 0.5, delta=1e-15)
        self.assertAlmostEqual(v, 1 / 36, delta=1e-15)

    def test_xor_of_two_uniforms_under_evidence_on_it(self):
        # lambda (.75, .25) on XOR: Z is not constant; the truth (at least 1/64) by quadrature.
        terms = [(0.75, [('x0', 1), ('x1', 0)], [1]), (0.75, [('x0', 0), ('x1', 1)], [1]),
                 (0.25, [('x0', 1), ('x1', 1)], []), (0.25, [('x0', 0), ('x1', 0)], [])]
        s_star, var = quadrature([(1.0, 1.0), (1.0, 1.0)], terms, 1)[0]
        self.assertGreaterEqual(var, 1 / 64)
        (s, v, how), = moments([('x0', 'beta(1.0, 1.0)'), ('x1', 'beta(1.0, 1.0)')], terms, 1)
        self.assertAlmostEqual(s, s_star, delta=1e-12)
        self.assertGreaterEqual(v, 0.5 * var, how)
        if how == 'exact':
            self.assertLessEqual(v, 2 * var)

    def test_random_multilinear_nodes_against_quadrature(self):
        rng = np.random.default_rng(7)
        worlds = list(itertools.product((0, 1), repeat=3))
        for case in range(40):
            shapes = [tuple(float(x) for x in rng.choice([1.0, 2.0, 5.0, 50.0, 500.0], 2)) for _ in range(3)]
            terms = [(float(rng.uniform(0.05, 1.0)), [(f'x{i}', b) for i, b in enumerate(w)],
                      [g + 1 for g in range(2) if rng.random() < 0.5]) for w in worlds]
            variables = [(f'x{i}', 'beta({!r}, {!r})'.format(*sh)) for i, sh in enumerate(shapes)]
            for (s, v, how), (s_star, var) in zip(moments(variables, terms, 2), quadrature(shapes, terms, 2)):
                with self.subTest(case=case):
                    self.assertAlmostEqual(s, s_star, delta=1e-12)
                    self.assertGreaterEqual(v, 0.5 * var, how)
                    if how == 'exact':
                        self.assertLessEqual(v, 2 * var)

    def test_both_estimates_at_zero_with_a_positive_variance(self):
        # Codex's case: X, Y ~ Bernoulli(1/4), T = (X - 1/4)(Y - 1/4), Z = 1 + T, N = 1/2 + .4 T;
        # every slice and the ratio expansion see no variance, the truth is about 3.1e-4.
        # T = XY - X/4 - Y/4 + 1/16, as terms over the literals of X and Y: the goal's terms are N,
        # and Z sums them with the rest, Z - N = 1/2 + .6 T.
        both, x, y = [('x0', 1), ('x1', 1)], [('x0', 1)], [('x1', 1)]
        terms = [(0.5 + 0.6 / 16, [], []), (0.6, both, []), (-0.15, x, []), (-0.15, y, []),
                 (0.5 + 0.4 / 16, [], [1]), (0.4, both, [1]), (-0.1, x, [1]), (-0.1, y, [1])]
        worlds = [(a, b) for a in (0, 1) for b in (0, 1)]
        p = {0: 0.75, 1: 0.25}
        T = lambda a, b: (a - 0.25) * (b - 0.25)
        EZ = sum(p[a] * p[b] * (1 + T(a, b)) for a, b in worlds)
        s_star = sum(p[a] * p[b] * (0.5 + 0.4 * T(a, b)) for a, b in worlds) / EZ
        var = sum(p[a] * p[b] * (0.5 + 0.4 * T(a, b) - s_star * (1 + T(a, b))) ** 2 / (1 + T(a, b)) for a, b in worlds) / EZ
        self.assertGreater(var, 3e-4)
        (s, v, how), = moments([('x0', 'bernoulli(0.25)'), ('x1', 'bernoulli(0.25)')], terms, 1)
        self.assertAlmostEqual(s, s_star, delta=1e-12)
        self.assertGreaterEqual(v, 0.5 * var, how)

    def test_bernoulli_endpoints_without_any_world(self):
        # At x0 = 0 no world is possible (Z = 0); it adds nothing to E[N^2 / Z].
        (s, v, how), = moments([('x0', 'bernoulli(0.5)')], [(1.0, [('x0', 1)], [1])], 1)
        self.assertEqual((s, v, how), (1.0, 0.0, 'exact'))

    def test_random_nodes_never_claim_less_than_half_the_variance(self):
        # The empirical calibration check (stats in scratch: claimed / true, bound share): the
        # first 60 random nodes, all 300 nightly (bench/nightly.sh sets PETTACHAINER_NIGHTLY=1).
        count = 300 if os.environ.get("PETTACHAINER_NIGHTLY") == "1" else 60
        for case, (texts, terms, truth) in enumerate(fuzz_cases(count)):
            for (s, v, how), (s_star, var) in zip(moments(texts, terms, 2), truth):
                with self.subTest(case=case):
                    self.assertAlmostEqual(s, s_star, delta=max(1e-9, 5e-3 * math.sqrt(var)))
                    self.assertGreaterEqual(v, 0.5 * var - 1e-15, how)     # a truth of 0 is rounding there

    def test_a_common_likelihood_factor_changes_nothing(self):
        variables, terms, _s, _var = or_node(0.1)
        scaled = [(c * 1e-200, lits, gs) for c, lits, gs in terms]
        self.assertEqual(moments(variables, scaled, 1), moments(variables, terms, 1))
        lam = [0.1 * 0.9, 0.9 * 0.9, 0.1 * 0.1, 0.9 * 0.1]
        self.assertEqual(self.coupling([0.5, 0.5], [x * 1e-200 for x in lam], [0, 1, 0, 1]),
                         self.coupling([0.5, 0.5], lam, [0, 1, 0, 1]))

    def test_impossible_couplings_and_evidence_are_inconsistent(self):
        # A pair joint above a marginal admits no joint; evidence that rules out every cell the
        # marginals allow leaves no posterior; neither is an interval, not even an empty-goal [0, 0].
        self.assertEqual(self.coupling([0.5, 0.5], [1.0] * 4, [0, 0, 0, 1], pairs=[(1, 2, 0.9)]), 'inconsistent')
        self.assertEqual(self.coupling([1.0, 0.5], [1.0, 0.0, 1.0, 0.0], [0, 1, 0, 1]), 'inconsistent')
        self.assertEqual(self.coupling([1.0, 0.5], [1.0, 0.0, 1.0, 0.0], [0, 0, 0, 0]), 'inconsistent')
        self.assertEqual(self.coupling([0.5, 0.5], [1.0] * 4, [0, 0, 0, 0]), (0.0, 0.0))

    def coupling(self, ps, lambdas, goal, pairs=()):
        text = 'c([{}], [{}], [{}], [{}])'.format(', '.join(map(repr, ps)),
                                                  ', '.join(f'pj({i}, {j}, {p!r})' for i, j, p in pairs),
                                                  ', '.join(map(repr, lambdas)), ', '.join(map(str, goal)))
        got = janus.query_once('term_string(c(_Ps, _Pj, _Ls, _G), T), event_node:event_node_coupling(_Ps, _Pj, _Ls, _G, _R), '
                               '( _R = interval(Lo, Hi) -> true ; Lo = _R, Hi = _R )', {'T': text})
        return got['Lo'] if got['Lo'] == 'inconsistent' else (got['Lo'], got['Hi'])

    def widen(self, s, v, lo, hi):
        got = janus.query_once('event_node:event_node_widen(S, V, Lo, Hi, S1, V1)', {'S': s, 'V': v, 'Lo': lo, 'Hi': hi})
        return got['S1'], got['V1']

    def test_xor_over_a_dropped_shared_parent(self):
        # X = R and Y = R, P(R) = 1/2, the dependence beyond the cap: cells 00, 10, 01, 11.
        lo, hi = self.coupling([0.5, 0.5], [1.0] * 4, [0, 1, 1, 0])
        self.assertAlmostEqual(lo, 0.0, delta=1e-12)
        self.assertAlmostEqual(hi, 1.0, delta=1e-12)
        s, v = self.widen(0.5, 0.0, lo, hi)
        self.assertLessEqual(abs(0.0 - s), 2 * math.sqrt(v) + 1e-12)

    def test_opposite_evidence_on_two_nodes_keeps_the_truth(self):
        # X = Y = R, X observed (.9, .1) and Y (.1, .9): every cell's likelihood enters the bound.
        lam = [0.1 * 0.9, 0.9 * 0.9, 0.1 * 0.1, 0.9 * 0.1]       # cells 00, 10, 01, 11 (bit 0 is X)
        lo, hi = self.coupling([0.5, 0.5], lam, [0, 1, 0, 1])
        self.assertLessEqual(lo, 0.5 + 1e-12)
        self.assertGreaterEqual(hi, 0.5 - 1e-12)

    def test_a_dropped_dependence_holds_the_truth_within_two_sd(self):
        # P(R) = .1, X = Y = R, goal And(X, Y): truth .1, the independent value .01.
        lo, hi = self.coupling([0.1, 0.1], [1.0] * 4, [0, 0, 0, 1])
        self.assertAlmostEqual(lo, 0.0, delta=1e-12)
        self.assertAlmostEqual(hi, 0.1, delta=1e-12)
        s, v = self.widen(0.01, 1e-6, lo, hi)
        self.assertLessEqual(abs(0.1 - s), 2 * math.sqrt(v))

    def test_known_pair_joints_constrain_the_coupling(self):
        lo, hi = self.coupling([0.5, 0.5], [1.0] * 4, [0, 0, 0, 1], pairs=[(1, 2, 0.3)])
        self.assertAlmostEqual(lo, 0.3, delta=1e-12)
        self.assertAlmostEqual(hi, 0.3, delta=1e-12)

    def test_beyond_four_events_the_interval_is_everything(self):
        self.assertEqual(self.coupling([0.5] * 5, [1.0] * 32, [1] + [0] * 31), (0.0, 1.0))


if __name__ == '__main__':
    unittest.main()
