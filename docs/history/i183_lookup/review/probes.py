import json,pathlib,sys
from pettachainer import PeTTaChainer
fixtures=pathlib.Path(sys.argv[1]) if len(sys.argv)>1 else pathlib.Path(__file__).with_name('fixtures.json')
cases=json.loads(fixtures.read_text())
for name,(facts,queries) in cases.items():
    h=PeTTaChainer();h.add_atoms_no_check(facts)
    for q in queries:
        if q.startswith('+'): h.add_atom(q[1:]);continue
        steps=0 if q.startswith('@') else 400;q=q.lstrip('@')
        try:
            rows=h.query_many_refs([f'(: $p {q} $tv)'],steps=steps)[0]
            answers=[dict(tv=r.tv,proof=h.expand_proof(r.proof)) for r in rows]
        except Exception as e: answers=str(e)
        print(json.dumps(dict(case=name,query=q,steps=steps,answers=answers)),flush=True)
