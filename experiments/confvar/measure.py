"""Reproduce the confvar decision from existing oracle models and captured calls.

All posterior marginal parameter means/variances are exact polynomial moments
of prior(theta)*Z. The candidate is the requested diagonal delta variance at
those means. Reference rational integrals use independent centered tensor
Gauss-Jacobi passes, explicitly labelled numerical; constant-Z products and
XOR counterexamples use closed forms. Production answers are never references
unless separately identified as such.
"""
import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import sys

import janus_swi as janus
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tests.test_event_node import dist, or_node
from tests.posterior_fixture_oracle import evidence_k, source_model
from tests.tv_calibration_oracles import SETTINGS, gauss_jacobi, params, predictive, probes, wide_probes, wide_oracle


def node(m):
    terms = []
    for bits in itertools.product((False, True), repeat=len(m['atoms'])):
        world = dict(zip(m['atoms'], map(np.bool_, bits)))
        literals = [('f_'+r, int(world[r])) for r in m['roots']]
        for child, (parent, _, _) in m['rules'].items():
            bit = parent(world) if callable(parent) else world[parent]
            literals.append((child+('|1' if bit else '|0'), int(world[child])))
        weight = math.prod(predictive(s,c) if f(world) else 1-predictive(s,c)
                           for _,f,s,c in m['comps'] if c > 0)
        if weight:
            terms.append((weight, literals, [j+1 for j,f in enumerate(m['goals'].values()) if f(world)]))
    return [(name, dist(*sc)) for name,sc in params(m).items()], terms, list(range(1,len(m['goals'])+1))


def distribution(text):
    kind, body = text.split('(', 1)
    return [kind, *map(float, body[:-1].split(','))]


def forms(theta, terms, goals, derivative=None):
    z = np.zeros(theta.shape[0])
    ns = np.zeros((theta.shape[0], len(goals)))
    for coefficient, literals, hits in terms:
        w = np.full(theta.shape[0], coefficient, dtype=float)
        found = derivative is None
        for index, bit in literals:
            if index == derivative:
                w *= 1 if bit else -1
                found = True
            else:
                w *= theta[:, index] if bit else 1 - theta[:, index]
        if found:
            z += w
            for j, goal in enumerate(goals):
                if goal in hits:
                    ns[:, j] += w
    return z, ns


def estimate(dists, terms, goals):
    means, variances, thirds = [], [], []
    for kind, *p in dists:
        if kind == 'beta':
            a, b = p
            t = a + b
            m, v = a/t, a*b/(t*t*(t+1))
            third = 2*(b-a)*a*b/(t**3*(t+1)*(t+2))
        else:
            m = p[0]
            v = m*(1-m) if kind == 'bernoulli' else 0.
            third = v*(1-2*m)
        means.append(m)
        variances.append(v)
        thirds.append(third)
    mu = np.array([means])
    z, ns = forms(mu, terms, goals)
    if z[0] <= 0:
        return None
    strength = ns[0]/z[0]
    slopes = np.array([forms(mu, terms, goals, i)[0][0]/z[0] for i in range(len(dists))])
    pv = np.array(variances)
    posterior_mu = mu[0] + pv*slopes
    posterior_var = np.maximum(0, pv + np.array(thirds)*slopes - (pv*slopes)**2)
    pz, pn = forms(posterior_mu[None, :], terms, goals)
    ps = pn[0]/pz[0]
    delta = np.zeros(len(goals))
    prior_delta = np.zeros(len(goals))
    for i in range(len(dists)):
        dz, dn = forms(posterior_mu[None, :], terms, goals, i)
        delta += ((dn[0]-ps*dz[0])/pz[0])**2 * posterior_var[i]
        dz0, dn0 = forms(mu, terms, goals, i)
        prior_delta += ((dn0[0]-strength*dz0[0])/z[0])**2 * pv[i]
    return strength, delta, prior_delta, posterior_mu, posterior_var


def integrate(dists, terms, goals, strength, nodes):
    axes = []
    for kind, *p in dists:
        if kind == 'point':
            axes.append((np.array(p), np.ones(1)))
        elif kind == 'bernoulli':
            axes.append((np.array([0., 1.]), np.array([1-p[0], p[0]])))
        else:
            axes.append(gauss_jacobi(*p, nodes))
    total = math.prod(len(x) for x, _ in axes)
    ez, ev = 0., np.zeros(len(goals))
    for start in range(0, total, 8192):
        ids = np.array(np.unravel_index(np.arange(start, min(start+8192, total)),
                                       [len(x) for x, _ in axes])).T
        theta = np.column_stack([x[ids[:, i]] for i, (x, _) in enumerate(axes)])
        wt = np.prod(np.column_stack([w[ids[:, i]] for i, (_, w) in enumerate(axes)]), axis=1)
        z, ns = forms(theta, terms, goals)
        ez += wt @ z
        safe = np.where(z > 0, z, 1.)
        ev += wt @ np.where(z[:, None] > 0,
                            (ns-z[:, None]*strength)**2/safe[:, None], 0.)
    return ev/ez, total


def model(label, variables, terms, goals, truth=None, production=None):
    ids = {name: i for i, (name, _) in enumerate(variables)}
    ds = [distribution(d) for _, d in variables]
    scale = max((abs(c) for c,_,_ in terms), default=0.)
    if scale == 0:
        return []
    ts = [(c/scale, [(ids[k], b) for k, b in ls], gs) for c, ls, gs in terms]
    candidate = estimate(ds, ts, goals)
    if candidate is None:
        return []
    s, delta, prior_delta, pm, pv = candidate
    dimensions = sum(d[0] == 'beta' for d in ds)
    bernoulli = sum(d[0] == 'bernoulli' for d in ds)
    if all(d[0] == 'point' for d in ds):
        truth = [0.] * len(goals)
    if truth is not None:
        ref = np.array(truth)
        err, method = np.zeros(len(goals)), 'closed-form'
    else:
        fine = next((n for n in (65, 33, 17, 9, 7, 5, 3, 2)
                     if n**dimensions * 2**bernoulli <= 200000), None)
        if fine is None:
            return []
        coarse = max(2, (fine+1)//2)
        ref, points = integrate(ds, ts, goals, s, fine)
        low, _ = integrate(ds, ts, goals, s, coarse)
        err = abs(ref-low)/np.maximum(ref, 1e-300)
        method = f'tensor-{coarse}-{fine} ({points} points)'
    rows = []
    for j, goal in enumerate(goals):
        row = dict(case=label, goal=goal, strength=float(s[j]), first_order=float(delta[j]),
                   prior_first_order=float(prior_delta[j]), reference=float(ref[j]),
                   ratio=float(delta[j]/ref[j]) if ref[j] > 0 else None,
                   reference_method=method, refinement_relative_gap=float(err[j]),
                   parameters=len(ds), beta_dimensions=dimensions,
                   broad=any(d[0]=='bernoulli' or d[0]=='beta' and d[1]+d[2] <= 10 for d in ds),
                   near_endpoint=any(m < .01 or m > .99 for m in pm),
                   posterior_parameter_means=pm.tolist(), posterior_parameter_variances=pv.tolist())
        if production is not None and production != 'inconsistent':
            row['production'] = production[j]
        rows.append(row)
    return rows


def captured(path):
    record = json.loads(path)
    out = janus.query_once(
        'term_string(node(_Vs,_Ts,Gs,_As), Text), '
        'findall([_IdText,_DText],(member(_Id-_D,_Vs),term_string(_Id,_IdText),term_string(_D,_DText)),Vars), '
        'findall([_C,_L,_H],(member(t(_C,_Ls,_H),_Ts),findall([_IText,_B],(member(_I-_B,_Ls),term_string(_I,_IText)),_L)),Terms), '
        '(_As==inconsistent -> Answers=inconsistent; findall([_S,_V,_K],member(a(_S,_V,_K),_As),Answers))',
        {'Text': record['node']})
    return record, out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--captures', nargs='*', default=[])
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    rows = []
    for setting, cfg in SETTINGS.items():
        for name, m in probes(*cfg).items():
            variables, terms, goals = node(m)
            rows.extend(model(f'D0/{name}/{setting}', variables, terms, goals))
        for name, m in wide_probes(cfg[0]).items():
            for goal, used in m['goals'].items():
                variables = [(f, dist(*m['roots'][f])) for f in used]
                every = [(f, 1) for f in used]
                rows.extend(model(f'D0/{name}/{setting}', variables,
                                  [(1., [], []), (-1., every, []), (1., every, [1])],
                                  [1], [wide_oracle(m)[goal]['var']]))
    fixtures = json.loads((ROOT/'tests/fixtures/posterior1_oracle_audit.json').read_text())
    for index, fixture in enumerate(fixtures):
        with evidence_k(fixture['k']):
            m = source_model(fixture['sources'], fixture['goal'], fixture['rates'],
                             fixture['k'], fixture['smoothing'])
            variables, terms, goals = node(m)
        rows.extend(model(f'fixture/{index}/{fixture["file"]}', variables, terms, goals))
    # Narrow Betas are included: broad-only widening cannot fix stationary goals.
    for a in (1., 10., 100., 1000., 3601.):
        terms = [(1., [('x', x), ('y', y)], [1] if x != y else [])
                 for x,y in itertools.product((0,1), repeat=2)]
        v = 1/(4*(2*a+1))
        rows.extend(model(f'analytic/XOR/Beta({a},{a})',
                          [('x', f'beta({a},{a})'), ('y', f'beta({a},{a})')], terms, [1], [4*v*v]))
    for epsilon in (1e-6, 1e-8):
        p = .5 + epsilon
        a,b = 2000*p, 2000*(1-p)
        actual_p = a/(a+b)
        v = actual_p*(1-actual_p)/2001
        reference = 8*(actual_p-.5)**2*v + 4*v*v
        rows.extend(model(f'analytic/near-XOR/epsilon={epsilon}',
                          [('x', f'beta({a},{b})'), ('y', f'beta({a},{b})')],
                          terms, [1], [reference]))
    for b in (.5, .1, .01, .001, 1e-4, 1e-6, 1e-9):
        variables, terms, _, _ = or_node(b)
        # Integrate the complement. E[s^2]-E[s]^2 cancels near s=1.
        c = 1-b
        integral = -1/c**2 - 1/(2*c) - math.log(b)/c**3
        variance = b*b*integral/((1+b)/2) - (b/(1+b))**2
        rows.extend(model(f'analytic/boundary/point={b}', variables, terms, [1], [variance]))
    seen = set()
    for pattern in args.captures:
        for path in sorted(ROOT.glob(pattern)):
            for line in path.read_text().splitlines():
                record, out = captured(line)
                key = hashlib.sha256(record['node'].encode()).hexdigest()
                if key in seen:
                    continue
                seen.add(key)
                label = f'capture/{path.name}/{record["case"]}/{key[:12]}'
                print(label, flush=True)
                rows.extend(model(label, out['Vars'], out['Terms'], out['Gs'], production=out['Answers']))
    target = ROOT/args.output
    target.write_text(''.join(json.dumps(row, allow_nan=False)+'\n' for row in rows))
    print(f'{len(rows)} goal measurements written to {target}', flush=True)


if __name__ == '__main__':
    main()
