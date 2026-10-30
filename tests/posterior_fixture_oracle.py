"""Independent source-to-Boolean-model adapter for posterior fixture audits.

Only explicit, single-producer CTVs and ground Boolean events are accepted.
This reads authored terms, never the compiler's graph or runtime answers.
"""
from contextlib import contextmanager

import numpy as np

from pettachainer.metta_syntax import parse_term, render
from tests import tv_calibration_oracles as oracle


def match(pattern, value, env):
    if isinstance(pattern, str) and pattern.startswith('$'):
        if pattern in env:
            return env[pattern] == value
        env[pattern] = value
        return True
    if isinstance(pattern, list):
        return isinstance(value, list) and len(pattern) == len(value) and all(match(p, v, env) for p, v in zip(pattern, value))
    return pattern == value


def substitute(term, env):
    return [substitute(t, env) for t in term] if isinstance(term, list) else env.get(term, term)


def ground(term):
    return all(ground(t) for t in term) if isinstance(term, list) else not str(term).startswith('$')


def literals(term):
    if isinstance(term, list) and term[0] in ('And', 'Or', 'Not'):
        return [a for child in term[1:] for a in literals(child)]
    return [term]


def holds(term, world):
    if isinstance(term, list):
        if term[0] == 'Not':
            return ~holds(term[1], world)
        if term[0] == 'And':
            return np.bool_(all(holds(t, world) for t in term[1:]))
        if term[0] == 'Or':
            return np.bool_(any(holds(t, world) for t in term[1:]))
    return world[render(term)]


@contextmanager
def evidence_k(k):
    previous = oracle.K
    oracle.K = k
    try:
        yield
    finally:
        oracle.K = previous


def source_model(sources, goal, rates=(), k=800, smoothing=False):
    sources = [parse_term(s) if isinstance(s, str) else s for s in sources]
    goal = parse_term(goal) if isinstance(goal, str) and goal.startswith('(') else goal
    facts, templates = [], []
    for _, name, statement, tv in sources:
        params = []
        if isinstance(statement, list) and statement[0] == 'ForAll':
            params, statement = statement[1:]
        if isinstance(statement, list) and statement[0] == 'Implication':
            templates.append((statement[1], statement[2], tv, params))
        else:
            if isinstance(statement, list) and statement[0] == 'Not':
                statement, tv = statement[1], ['STV', 1-float(tv[1]), tv[2]]
            facts.append((statement, tuple(map(float, tv[1:]))))
    rates = [(parse_term(p) if isinstance(p, str) and p.startswith('(') else p, tuple(map(float, tv[1:]))) for p, tv in rates]
    todo, seen, rules, patterns, observed = [goal], {}, {}, {}, []
    while todo:
        term = todo.pop(0)
        key = render(term)
        if key in seen:
            continue
        assert len(seen) < 24, 'oracle component exceeds discovery cap'
        seen[key] = term
        for p, tv in facts:
            if p == term and tv[1] > 0:
                observed.append((term, tv))
        if isinstance(term, list) and term[0] in ('And', 'Or', 'Not'):
            todo.extend(literals(term))
        for parent, child, tv, params in templates:
            for side in [child] + literals(parent):
                env = {}
                if not match(side, term, env):
                    continue
                p, c = substitute(parent, env), substitute(child, env)
                if not ground([p, c]):
                    continue
                assert tv[0] == 'CTV', (p, c, tv)
                ck = render(c)
                spec = (p, tuple(map(float, tv[1][1:])), tuple(map(float, tv[2][1:])))
                assert ck not in rules or rules[ck] == spec, 'multiple producers'
                rules[ck] = spec
                todo.extend([c] + literals(p))
                for atom in literals(parent):
                    instance = substitute(atom, env)
                    if ground(instance):
                        patterns.setdefault(render(instance), substitute(atom, {v: env[v] for v in params if v in env}))
        for p, tv in facts:
            if isinstance(p, list) and p[0] in ('And', 'Or') and term in literals(p) and tv[1] > 0:
                todo.append(p)
    atoms = {render(a): a for t in seen.values() for a in literals(t)}
    roots = {}
    for key, term in atoms.items():
        if key in rules:
            continue
        own = [tv for p, tv in facts if p == term and tv[1] > 0]
        if own:
            certain = [s for s, c in own if c >= 1]
            if certain:
                assert all(s == certain[0] for s in certain)
                roots[key] = (certain[0], 1.)
            else:
                counts = [(s, k*c/(1-c)) for s, c in own]
                mass = sum(n for _, n in counts)
                roots[key] = (sum(s*n for s, n in counts)/mass, mass/(mass+k))
        else:
            pattern = patterns.get(key, [term[0]] + [f'$_{i}' for i in range(len(term)-1)] if isinstance(term, list) else term)
            explicit = [tv for p, tv in rates if match(p, term, {}) and (p == pattern or not ground(pattern))]
            if explicit:
                roots[key] = explicit[0]
            else:
                samples = [tv for p, tv in facts if match(pattern, p, {}) and render(p) not in seen]
                mass = sum(c for _, c in samples)
                if mass:
                    total = sum(s*c for s, c in samples)
                    roots[key] = ((total + k*.5)/(mass+k) if smoothing else total/mass, mass/(mass+k))
                else:
                    roots[key] = (.5, 0.)
    comps = [(render(t), lambda w, t=t: holds(t,w), *tv) for t, tv in observed if render(t) in rules or isinstance(t,list) and t[0] in ('And','Or','Not')]
    return dict(atoms=list(atoms), roots=roots,
                rules={key: (lambda w,p=p: holds(p,w), pos,neg) for key,(p,pos,neg) in rules.items()},
                comps=comps, goals={render(goal): lambda w: holds(goal,w)})


def source_oracle(sources, goal, rates=(), k=800, smoothing=False, nodes=None):
    model = source_model(sources, goal, rates, k, smoothing)
    if nodes is None:
        dimensions = sum(c < 1 for _, c in oracle.params(model).values())
        nodes = 33 if dimensions <= 3 else 9
    with evidence_k(k), np.errstate(divide='ignore', invalid='ignore'):
        result = oracle.event_oracle(model, nodes=nodes)[next(iter(model['goals']))]
        if all(c >= 1 for _, c in oracle.params(model).values()):
            result['var'], result['c'] = 0., .9999
        return result
