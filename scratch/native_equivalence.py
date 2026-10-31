"""Compare native clauses per predicate/arity, independent of source partition."""
from collections import defaultdict
from pathlib import Path
import json
import subprocess
import tempfile

root=Path.cwd()
files=subprocess.check_output(['git','ls-tree','-r','--name-only','77cce1fa','--','pettachainer/metta'],text=True).splitlines()
files=[f for f in files if f.endswith('.pl')]
def parsed(paths):
    rows=json.loads(subprocess.check_output(['swipl','-q','-f','scratch/native_terms.pl','--',*map(str,paths)],text=True))
    out=defaultdict(list)
    for r in rows:
        n=r['name'].replace('hypothesis_generalize_argument','generalize_argument')
        t=r['term'].replace('hypothesis_generalize_argument','generalize_argument')
        out[n,r['arity']].append(t)
    return out
with tempfile.TemporaryDirectory(dir=root/'scratch',prefix='native-base-') as tmp:
    paths=[]
    for f in files:
        p=Path(tmp)/f;p.parent.mkdir(parents=True,exist_ok=True)
        p.write_bytes(subprocess.check_output(['git','show',f'77cce1fa:{f}']))
        paths.append(p)
    before=parsed(paths)
after=parsed(sorted((root/'pettachainer/metta').rglob('*.pl')))
changed=[f'{n}/{a}' for n,a in sorted(before.keys()|after.keys()) if before.get((n,a))!=after.get((n,a))]
print(json.dumps({'predicates_before':len(before),'predicates_after':len(after),'clauses_before':sum(map(len,before.values())),'clauses_after':sum(map(len,after.values())),'changed_predicates':changed},indent=2))
assert changed==[],changed
