"""Literal setting writers and native-overlay runtime references."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re
import subprocess
from reference_graph import forms

parser = argparse.ArgumentParser()
parser.add_argument('--revision')
args = parser.parse_args()
settings = ['sk_eval_budget', 'sk_branch_budget', 'sk_branch_at',
            'sk_root_claim_budget', 'sk_near_reserve', 'sk_root_claim_cap']
files = subprocess.check_output(
    ['git', 'ls-tree', '-r', '--name-only', args.revision, '--', 'pettachainer/metta']
    if args.revision else ['git', 'ls-files', 'pettachainer/metta'], text=True).splitlines()
writes = {s: defaultdict(int) for s in settings}

def visit(term, file):
    if not isinstance(term, list) or not term:
        return
    if len(term) >= 3 and term[0] == 'change-state!' and isinstance(term[1], str) and term[1] in writes:
        writes[term[1]][file] += 1
    for child in term:
        visit(child, file)

for file in files:
    if Path(file).suffix not in ('.metta', '.pl'):
        continue
    source = subprocess.check_output(['git', 'show', f'{args.revision}:{file}'], text=True) if args.revision else Path(file).read_text()
    if file.endswith('.metta'):
        for term in forms(source):
            visit(term, file)
    else:
        source = '\n'.join(line.split('%', 1)[0] for line in source.splitlines())
        for setting in settings:
            writes[setting][file] += len(re.findall(r"'change-state!'\(\s*" + setting + r'\s*,', source))
            if not writes[setting][file]:
                del writes[setting][file]
print(json.dumps({s: dict(writer_files=len(rows), sites=sum(rows.values()), writers=dict(rows))
                  for s, rows in writes.items()}, indent=2))
