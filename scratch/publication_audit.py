"""Literal publication writers; dynamic temp references are owned separately."""
import argparse
import json
from pathlib import Path
import subprocess
from reference_graph import forms

STORES = {'&kb', '&kb_prefix', '&kb_open', '&materialized_facts', '&sk_forward_stored', '&sk_summary'}
MUTATIONS = {'add-atom', 'remove-atom', 'chainer-add-atom', 'kb-add-atom', 'add-space-atom!', 'remove-data-rows!'}


def mutations(form):
    if not isinstance(form, list):
        return
    if form and isinstance(form[0], str) and form[0] in MUTATIONS:
        # kb-add-atom has a backend before its target space.
        pos = 2 if form[0] == 'kb-add-atom' else 1
        if len(form) > pos and isinstance(form[pos], str) and form[pos] in STORES:
            yield form[pos]
    for child in form:
        yield from mutations(child)


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--revision')
args = parser.parse_args()
files = subprocess.check_output(['git', 'ls-files', 'pettachainer/metta'], text=True).splitlines()
if args.revision:
    files = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', args.revision, 'pettachainer/metta'], text=True).splitlines()
counts = {store: {} for store in sorted(STORES)}
for file in files:
    if not file.endswith('.metta'):
        continue
    source = subprocess.check_output(['git', 'show', f'{args.revision}:{file}'], text=True) if args.revision else Path(file).read_text()
    for form in forms(source):
        for store in mutations(form):
            counts[store][file] = counts[store].get(file, 0) + 1
print(json.dumps(counts, indent=2))
