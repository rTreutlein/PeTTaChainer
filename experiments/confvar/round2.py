"""Closed polynomial moments and a Cauchy ratio bound on the round-1 inputs.

References are the committed round-1 references, including their error labels.
No numerical integration runs here. All expectations below are under the prior.
"""
import json
import math
from collections import defaultdict
from pathlib import Path

import numpy as np
import measure

BASE = Path(__file__).resolve().parent
REFERENCES = {(r['case'], r['goal']): r for r in
              map(json.loads, (BASE/'measurements.jsonl').read_text().splitlines())}


def polynomial(terms, means, goal=None):
    groups = defaultdict(list)
    for c, literals, hits in terms:
        if goal is not None and goal not in hits:
            continue
        expanded = {(): c}
        for i, bit in literals:
            if means[i][1] == 0:
                expanded = {k: v*(means[i][0] if bit else 1-means[i][0])
                            for k, v in expanded.items()}
            elif bit:
                expanded = {tuple(sorted((*k, i))): v for k, v in expanded.items()}
            else:
                expanded.update({tuple(sorted((*k, i))): -v for k, v in list(expanded.items())})
        for k, v in expanded.items():
            groups[k].append(v)
    return {k: v for k, vs in groups.items() if (v := math.fsum(vs)) != 0}


def covariance(a, b, means):
    parts = []
    for ka, ca in a.items():
        sa = set(ka)
        for kb, cb in b.items():
            shared = sa.intersection(kb)
            base, delta = 1., 0.
            for i in sorted(shared):
                mu, var = means[i]
                delta = delta*(mu*mu+var) + base*var
                base *= mu*mu
            outside = math.prod(means[i][0] for i in sa.symmetric_difference(kb))
            parts.append(ca*cb*outside*delta)
    return math.fsum(parts)


def model(label, variables, terms, goals, truth=None, production=None):
    ids = {name: i for i, (name, _) in enumerate(variables)}
    ds = [measure.distribution(d) for _, d in variables]
    means = []
    for kind, *p in ds:
        if kind == 'beta':
            a, b = p
            means.append((a/(a+b), a*b/((a+b)**2*(a+b+1))))
        else:
            means.append((p[0], p[0]*(1-p[0]) if kind == 'bernoulli' else 0.))
    scale = max(abs(c) for c, _, _ in terms)
    ts = [(c/scale, [(ids[i], bit) for i, bit in ls], hits) for c, ls, hits in terms]
    z0, ns = measure.forms(np.array([[mu for mu, _ in means]]), ts, goals)
    if z0[0] <= 0:
        return []
    z = polynomial(ts, means)
    vz = max(0., covariance(z, z, means))
    rows = []
    for j, goal in enumerate(goals):
        old = REFERENCES.get((label, goal))
        if old is None:
            continue
        s = ns[0, j]/z0[0]
        n = polynomial(ts, means, goal)
        d = {k: n.get(k, 0.)-s*z.get(k, 0.) for k in n.keys() | z.keys()}
        vd = max(0., covariance(d, d, means))
        raw = (vd + max(s, 1-s)*math.sqrt(vz*vd))/z0[0]**2
        bound = min(s*(1-s), raw)
        row = dict(old, polynomial_variance=vd/z0[0]**2,
                   normalization_variance=vz, candidate_variance=bound,
                   constant_z=all(not k for k in z),
                   polynomial_terms=len(z), numerator_terms=len(n),
                   candidate_ratio=bound/old['reference'] if old['reference'] > 0 else None)
        rows.append(row)
    return rows


if __name__ == '__main__':
    measure.model = model
    measure.main()
