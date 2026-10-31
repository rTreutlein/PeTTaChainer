"""Direction/side-effect audit over the supplied reference graph (same exclusions)."""
from collections import defaultdict
from pathlib import Path
import json
import sys
from reference_graph import forms, references

g = json.loads(Path(sys.argv[1]).read_text())
edges = defaultdict(set)
for e in g['edges']: edges[e['caller']].add(e['callee'])
base = 'pettachainer/metta/'
owners = [base + p for p in [
    'core/vocabulary.metta', 'prolog/source_catalog.pl',
    'runtime/proofs.metta', 'prolog/proof_semantics.pl',
    'runtime/backward/value_store.metta', 'runtime/kb_publication.metta',
    'runtime/statistical_ledger.metta', 'prolog/statistical_ledger.pl',
    'runtime/execution.metta', 'prolog/execution.pl',
    'runtime/application_policy.metta',
]]
forbidden = {f for component in g['sccs'] for f in component
             if (f.startswith(base + 'runtime/backward/') and not f.endswith('/value_store.metta'))
             or f in {base + 'runtime/application_discovery.metta', base + 'runtime/application_values.metta'}}
results = {}
for owner in owners:
    reached=set();todo=list(edges[owner])
    while todo:
        file=todo.pop()
        if file in reached: continue
        reached.add(file);todo.extend(edges[file]-reached)
    results[owner] = sorted(reached & forbidden)
print(json.dumps({'largest_scc':g['largest_scc'],'owner_upward_paths':results},indent=2))
assert not any(results.values())
if Path(base + 'runtime/backward/eval_core.metta').exists():
    refs=set()
    for file in ('eval_core.metta', 'eval_versions.metta'):
        for f in forms(Path(base + 'runtime/backward/' + file).read_text()):
            if len(f)==3 and f[0]=='=' and f[1][0] in ('sk-row-state','sk-row-result'):
                refs.update(references(f[2]))
    mutations={n for n in refs if n in {'add-atom','remove-atom','change-state!','context-add!','context-remove!','record-proof!'} or n.startswith(('sk-store','sk-queue','sk-commit','sk-pend'))}
    print(json.dumps({'numerical_kernel_direct_publications_or_queue_writes':sorted(mutations)}))
    assert not mutations
