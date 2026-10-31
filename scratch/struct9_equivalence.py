"""Audit clauses and MeTTa declarations/equations independently of file ownership."""
from collections import defaultdict, Counter
from pathlib import Path
import importlib.util
import json
import subprocess
import tempfile

root=Path.cwd()
base='13622cf3'
files=subprocess.check_output(['git','ls-tree','-r','--name-only',base,'--','pettachainer/metta'],text=True).splitlines()
spec=importlib.util.spec_from_file_location('reference_graph',root/'scratch/reference_graph.py')
graph=importlib.util.module_from_spec(spec);spec.loader.exec_module(graph)
def native(paths):
 rows=json.loads(subprocess.check_output(['swipl','-q','-f','scratch/native_terms.pl','--',*map(str,paths)],text=True))
 out=defaultdict(list)
 for row in rows: out[row['name'],row['arity']].append(row['term'])
 return out
def metta(paths):
 return Counter(json.dumps(form) for path in paths for form in graph.forms(path.read_text())
                if form and form[0] in ('=',':','datatype'))
with tempfile.TemporaryDirectory(dir=root/'scratch',prefix='struct9-base-') as tmp:
 paths=[]
 for file in files:
  if Path(file).suffix not in ('.pl','.metta'): continue
  path=Path(tmp)/file;path.parent.mkdir(parents=True,exist_ok=True)
  path.write_bytes(subprocess.check_output(['git','show',f'{base}:{file}']))
  paths.append(path)
 before=native([p for p in paths if p.suffix=='.pl'])
 mb=metta([p for p in paths if p.suffix=='.metta'])
after=native(sorted((root/'pettachainer/metta').rglob('*.pl')))
ma=metta(sorted((root/'pettachainer/metta').rglob('*.metta')))
changed=[f'{n}/{a}' for n,a in sorted(before.keys()|after.keys()) if before.get((n,a))!=after.get((n,a))]
r={'native_predicates_before':len(before),'native_predicates_after':len(after),
   'native_clauses_before':sum(map(len,before.values())),'native_clauses_after':sum(map(len,after.values())),
   'native_changed':changed,'metta_removed':sum((mb-ma).values()),'metta_added':sum((ma-mb).values())}
print(json.dumps(r,indent=2))
assert not changed,changed
assert mb==ma, {'removed':list(mb-ma),'added':list(ma-mb)}

# Raw stores must not reach reader/controller policy through a native back-edge.
refs=graph.measure(root)
assert refs['largest_scc'] <= 11
assert all(len(component)==1 for component in refs['sccs']
           if any('/runtime/store/' in path for path in component))
edges=defaultdict(set)
for edge in refs['edges']: edges[edge['caller']].add(edge['callee'])
seen=set()
pending=[path for component in refs['sccs'] for path in component if '/runtime/store/' in path]
while pending:
 path=pending.pop()
 if path in seen: continue
 seen.add(path);pending.extend(edges[path])
allowed=('/core/','/lib/','/runtime/store/')
assert all(not path.endswith('.metta') or any(part in path for part in allowed) for path in seen), sorted(seen)
assert not any(path.endswith(('/application_support.pl','/search_state.pl','/proof_semantics.pl','/source_catalog.pl','/ingestion.pl')) for path in seen), sorted(seen)
print('raw-store SCCs: all singleton; transitive callees: core, collections and raw stores only')
