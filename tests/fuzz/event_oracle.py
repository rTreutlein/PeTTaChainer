"""Independent finite-world reference; no chainer imports.

Strength is exact enumeration at analytic parameter means. With constant
normalization variance is a polynomial moment, exact with two Beta nodes.
With reports the variance integral is numerical (two quadrature orders are
reported, never called a certificate). A separate analytic lower bound can
certify overconfidence even when the integral is unresolved.
"""
import itertools
import math

import numpy as np

from tests.tv_calibration_oracles import gauss_jacobi
from .kb import formula_holds, formula_text


def distribution(s, c, role, k):
    if c == 1:
        return s, s*s, None
    n = k*c/(1-c)
    if role == 'view':
        if c == 0:
            return s, s, ('bernoulli', s)
        a, b = max(n*s, 1e-12), max(n*(1-s), 1e-12)
    else:
        a, b = n*s+1, n*(1-s)+1
    return a/(a+b), a*(a+1)/((a+b)*(a+b+1)), (a, b)


def reference(kb, k=800):
    if not kb.reference:
        return {'status': 'invariant-only'}
    atoms = list(kb.roots)
    families = {}
    for rule in kb.rules:
        families.setdefault(rule[2], []).append(rule)
        if rule[2] not in atoms:
            atoms.append(rule[2])
    if len(atoms) > 12:
        raise ValueError('event reference is limited to twelve atoms')
    params = list(kb.roots.values())
    root_indices = {a: i for i, a in enumerate(kb.roots)}
    branches = {}
    for head, rules in families.items():
        if all(r[3] in ('STV', 'FTV') and tuple(r[4]) == (1, 1) for r in rules):
            branches[head] = ('or', len(params))
            s, c = kb.bases.get(head, (.5, 0))
            params.append((s, c, 'count'))
        else:
            if len(rules) != 1:
                raise ValueError('multiple uncertain producers have no declared joint law')
            r = rules[0]
            branches[head] = ('conditional', len(params))
            params += [(*r[4], 'count'), (*r[5], 'count')]
    ds = [distribution(*p, k) for p in params]
    # World truth values are independent of theta; vectorize the small truth table.
    worlds = {a: np.array(bits, dtype=bool) for a, bits in zip(atoms, zip(*itertools.product((False, True), repeat=len(atoms))))}
    goals = [formula_holds(q, worlds) for q in kb.queries]
    likelihood = np.ones(2**len(atoms))
    for form, s, c in kb.reports:
        if c == 0:
            continue
        m = distribution(s, c, 'count', k)[0]
        likelihood *= np.where(formula_holds(form, worlds), m/max(m, 1-m), (1-m)/max(m, 1-m))

    def stats(theta):
        weight = np.broadcast_to(likelihood[:, None], (len(likelihood), theta.shape[1])).copy()
        for atom, index in root_indices.items():
            weight *= np.where(worlds[atom][:, None], theta[index], 1-theta[index])
        for head, rules in families.items():
            kind, index = branches[head]
            if kind == 'or':
                active = np.logical_or.reduce([formula_holds(r[1], worlds) for r in rules])
                p = np.where(active[:, None], 1, theta[index])
            else:
                p = np.where(formula_holds(rules[0][1], worlds)[:, None], theta[index], theta[index+1])
            weight *= np.where(worlds[head][:, None], p, 1-p)
        return weight.sum(axis=0), np.array([weight[g].sum(axis=0) for g in goals])

    z, nums = stats(np.array([[d[0]] for d in ds]))
    if z[0] == 0:
        return {'status': 'impossible', 'rows': [None]*len(goals)}
    means = nums[:, 0]/z[0]

    def integrate(nodes):
        axes = []
        for mu, _, shape in ds:
            if shape is None:
                axes.append((np.array([mu]), np.ones(1)))
            elif shape[0] == 'bernoulli':
                axes.append((np.array([0., 1.]), np.array([1-mu, mu])))
            else:
                axes.append(gauss_jacobi(*shape, nodes))
        size = math.prod(len(a) for a, _ in axes)
        if size > 150_000:
            return None
        grid = np.array(np.meshgrid(*[a for a, _ in axes], indexing='ij')).reshape(len(axes), -1)
        weights = np.prod(np.array(np.meshgrid(*[w for _, w in axes], indexing='ij')), axis=0).ravel()
        second, q = np.zeros(len(goals)), np.zeros(len(goals))
        for start in range(0, size, 256):
            zz, nn = stats(grid[:, start:start+256])
            dd = nn-means[:, None]*zz
            ww = weights[start:start+256]
            second += (np.divide(dd*dd, zz, out=np.zeros_like(dd), where=zz>0)*ww).sum(axis=1)
            q += (dd*dd*ww).sum(axis=1)
        # Z <= max(world likelihood), since prior world weights sum to one.
        return second/z[0], q/(z[0]*max(likelihood))

    # Degree two moments, including Q, are analytic under a two-point Gauss rule.
    polynomial = integrate(2)
    neutral = all(s == .5 or c == 0 for _, s, c in kb.reports)
    fine, coarse = (polynomial, polynomial) if neutral else (integrate(24), integrate(12))
    rows = []
    for i, mean in enumerate(means):
        rows.append({'atom': formula_text(kb.queries[i]), 's': float(mean),
                     'variance': None if fine is None else float(fine[0][i]),
                     'variance_lower': float(polynomial[1][i]),
                     'variance_delta': None if fine is None or coarse is None else float(abs(fine[0][i]-coarse[0][i])),
                     'variance_status': 'exact-polynomial' if neutral else 'numerical' if fine is not None else 'lower-bound-only'})
    return {'status': 'enumerated', 'rows': rows}
