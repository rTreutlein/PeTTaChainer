"""Literal writer files/sites, including native writes, for ledger-owned stores."""
import argparse
import collections
import json
from pathlib import Path
import re
import subprocess
from reference_graph import forms

STORES = ['&sk_instance_tally', '&sk_instance_member', '&sk_instance_regime',
          '&sk_instance_digest', '&sk_instance_sig', '&sk_instance_read',
          '&sk_rate_dirty', '&sk_instance_changed', '&base_rate_cache']
MUTATIONS = {'context-add!', 'context-remove!', 'remove-data-rows!',
             'remove-variant-row!', 'add-atom', 'remove-atom', 'change-atom!'}

def walk(term):
    if isinstance(term, list):
        yield term
        for child in term:
            yield from walk(child)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--revision')
args = parser.parse_args()
cmd = ['ls-tree', '-r', '--name-only', args.revision, '--', 'pettachainer/metta'] if args.revision else ['ls-files', 'pettachainer/metta']
files = subprocess.check_output(['git', *cmd], text=True).splitlines()
rows = {s: collections.Counter() for s in STORES}
for name in files:
    p = Path(name)
    if p.suffix not in ('.metta', '.pl'):
        continue
    s = subprocess.check_output(['git', 'show', f'{args.revision}:{name}'], text=True) if args.revision else p.read_text()
    if p.suffix == '.metta':
        for form in forms(s):
            for node in walk(form):
                if len(node) >= 2 and isinstance(node[0],str) and node[0] in MUTATIONS and isinstance(node[1],str) and node[1] in rows:
                    rows[node[1]][name] += 1
    else:
        for store in STORES:
            rows[store][name] += len(re.findall(r"'(?:"+'|'.join(re.escape(op) for op in MUTATIONS)+r")'\s*\(\s*'"+re.escape(store)+"'", s))
            if not rows[store][name]:
                del rows[store][name]
print(json.dumps({'writer_pairs':sum(len(v) for v in rows.values()), 'stores':{s:dict(v) for s,v in rows.items()}}, indent=2))
