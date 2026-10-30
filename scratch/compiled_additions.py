"""Capture compiler products with variables alpha-normalized per addition."""
import json
import re
from pettachainer import PeTTaChainer

h = PeTTaChainer()
h._call('set-positive-only-predicate', ['positiveKb A'])
h._call('set-complete-predicate', ['completeKb B'])
h._call('set-rule-refinement', ['refineKb true'])
samples = [
    ('plainKb', '(: fact (A a) (STV 0.7 0.9))'),
    ('plainKb', '(: negative (Not (A a)) (STV 0.7 0.9))'),
    ('plainKb', '(: r (Implication (A $x) (B $x)) (STV 0.8 0.9))'),
    ('plainKb', '(: r (Implication (And (A $x) (C $x)) (B $x)) (CTV (STV 0.8 0.9) (STV 0.2 0.9)))'),
    ('plainKb', '(: r (BiImplication (A $x) (B $x)) (STV 0.8 0.9))'),
    ('plainKb', '(: r (ForAll ($c) (Implication (A $c $x) (B $c $x))) (STV 0.8 0.9))'),
    ('plainKb', '(: r (Implication (Exists ($y) (A $x $y)) (B $x)) (STV 0.8 0.9))'),
    ('plainKb', '(: r (Implication (A $x) (Exists ($y) (B $x $y))) (STV 0.8 0.9))'),
    ('positiveKb', '(: r (Implication (A $x) (B $x)) (STV 0.8 0.9))'),
    ('completeKb', '(: r (Implication (A $x) (B $x)) (STV 0.8 0.9))'),
    ('refineKb', '(: r (Implication (A $x) (B $x)) (STV 0.8 0.9))'),
    ('plainKb', '(: r (Implication (And (A $x) (And (C $x) (D $x))) (Not (B $x))) (STV 0.8 0.9))'),
]
def alpha(term):
    names = {}
    def replace(match):
        value = match.group()
        return names.setdefault(value, f'$v{len(names)}')
    return re.sub(r'\$[^\s()]+', replace, term)
rows = []
for kb, statement in samples:
    for function in ('compile_', 'mm2compile'):
        products = h._call(function, [f'{kb} {statement}'])
        assert products, (function, kb, statement)
        rows.append(dict(function=function, kb=kb, source=statement, products=[alpha(p) for p in products]))
for statement in ('(: $p (A $x) $tv)', '(: $p (And (A $x) (B $x)) $tv)', '(: $p (Implication (A $x) (B $x)) $tv)', '(: $p (Assuming (A a) (B a)) $tv)'):
    products = h._call('mm2compileQuery', [f'queryKb {statement}'])
    assert products, statement
    rows.append(dict(function='mm2compileQuery', kb='queryKb', source=statement, products=[alpha(p) for p in products]))
print(json.dumps(rows, indent=2))
