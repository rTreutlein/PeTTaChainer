import json
from pettachainer import PeTTaChainer
# An optional baseline source is consulted only after the normal library load,
# in this process, without changing runtime files or the PeTTa load cache.
import sys
if len(sys.argv) > 1:
 import janus_swi as janus
 PeTTaChainer()
 janus.consult(sys.argv[1])
cases=[]
def add(name,facts,goal): cases.append((name,facts,goal))
parts=['(: a A (STV 1 0.99))','(: b B (STV 1 0.99))','(: c C (STV 1 0.99))']
neg=['(: report (Not (And A B C)) (STV 1 0.99))']
pos=['(: report (And A B C) (STV 1 0.99))']
pair=['(: report (Not (And A B)) (STV 1 0.99))']
for i,q in enumerate(['(Not A)','(And A B C)','(Not (And A B C))'],1): add(str(i),parts,q)
for i,fs,q in [(4,neg,'(Not (And A B C))'),(5,neg,'(And A B C)'),(6,pos,'(And A B C)'),(7,pos,'(Not (And A B C))'),(8,pair+parts[:1],'(Not (And A B))'),(9,pair+parts[:1],'(And A B)')]: add(str(i),fs,q)
add('conflict',pair+parts[:2],'(And A B)')
add('part',['(: report (And A B) (STV 1 0.99))'],'A')
add('shared',['(: report (And A B) (STV 1 0.99))'],'(And A C)')
add('rule-part-ctv',pair+['(: x X (STV 1 0.99))','(: r (Implication X A) (CTV (STV 0.9 0.99) (STV 0.1 0.99)))'],'(And A B)')
add('rule-part',pair+['(: x X (STV 1 0.99))','(: r (Implication X A) (STV 1 0.99))'],'(And A B)')
add('assuming',neg,'(Assuming X (And A B C))')
add('assuming-part',pair,'(Assuming A (And A B))')
add('independent',neg+['(: second (Not (And A B C)) (STV 1 0.99))'],'(And A B C)')
add('repeated',neg*2,'(And A B C)')
add('reordered',neg,'(And C A B)')
add('or',['(: report (Or A B) (STV 0.8 0.9))'],'(Or B A)')
add('nested',['(: report (Or (And A B) C) (STV 0.8 0.9))'],'(Or C (And B A))')
for name,fs,q in cases:
 h=PeTTaChainer()
 for f in fs: h.add_atom(f)
 answer=h.query(f'(: $p {q} $tv)',steps=400,timeout_sec=0)
 print(json.dumps(dict(case=name,facts=fs,query=q,answer=answer)),flush=True)
