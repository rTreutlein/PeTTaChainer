"""Count route constructors in semantic MeTTa patterns, not output constructors.

The native ledger is explicit because Prolog uses guarded head comparisons,
not only literal list patterns. Its records name every original decoder.
"""
import collections
import json
from pathlib import Path
import subprocess
import sys
from reference_graph import forms

revision = sys.argv[1] if len(sys.argv) > 1 else None
root = Path(__file__).resolve().parent.parent
command = ['ls-tree', '-r', '--name-only', revision, '--', 'pettachainer/metta'] if revision else ['ls-files', 'pettachainer/metta']
files = subprocess.check_output(['git', '-C', str(root), *command], text=True).splitlines()
targets = {'by', 'inverted', 'antecedent-completion', 'node-message', 'node-jeffrey', 'node-joint'}

def walk(term):
    if isinstance(term, list):
        yield term
        for child in term:
            yield from walk(child)

def constructors(pattern):
    for node in walk(pattern):
        if node and isinstance(node[0], str) and node[0] in targets:
            yield node[0]
        if len(node) > 1 and node[0] == 'cons' and isinstance(node[1], str) and node[1] in targets:
            yield node[1]

rows = []
for filename in files:
    if not filename.endswith('.metta') or '/runtime/' not in filename or filename.endswith('/proofs.metta'):
        continue
    source = subprocess.check_output(['git', '-C', str(root), 'show', f'{revision}:{filename}'], text=True) if revision else (root / filename).read_text()
    for form in forms(source):
        if len(form) != 3 or form[0] != '=':
            continue
        name = form[1][0]
        patterns = [form[1]]
        for node in walk(form[2]):
            if len(node) == 3 and node[0] == 'case' and isinstance(node[2], list):
                patterns.extend(alternative[0] for alternative in node[2] if isinstance(alternative,list) and len(alternative) == 2)
            elif len(node) == 4 and node[0] == 'let':
                patterns.append(node[1])
            elif len(node) == 3 and node[0] == 'let*' and isinstance(node[1],list):
                patterns.extend(binding[0] for binding in node[1] if isinstance(binding,list) and len(binding) == 2)
            elif len(node) == 4 and node[0] == 'match':
                patterns.append(node[2])
        for pattern in patterns:
            for constructor in constructors(pattern):
                rows.append(dict(file=filename, function=name, constructor=constructor))
native_file = 'pettachainer/metta/prolog/runtime_helpers.pl'
native = subprocess.check_output(['git', '-C', str(root), 'show', f'{revision}:{native_file}'], text=True) if revision else (root / native_file).read_text()
ledger = {
    'jeffrey_order_key': "[['node-jeffrey', Index, _KProof, Prediction, Conditionals]|_]",
    'proof_given_evidence': "Completion == 'antecedent-completion'",
    'dormancy_premise_supported': "Proof = [['antecedent-completion'|_]|_]",
    'dormancy_derived_positive': "Proof = [by|_]",
    'dormancy_derived_negative': "Proof = [negated, [by|_]]",
    'stored_proof_fact': "Stored = ['fact-source', _, _]",
    'stored_proof_wrapper': "Stored = ['@', _, Merge]",
    'stored_proof_revision': "Stored = ['merge/revision', Left, Right]",
}
native_sites = [name for name, code in ledger.items() if code in native]
print(json.dumps({'metta_patterns': len(rows), 'by_file': dict(collections.Counter(row['file'] for row in rows)), 'sites': rows, 'native_decoder_sites': native_sites}, indent=2))
