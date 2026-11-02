"""Static name-resolved reference graph; no project code is loaded.

Scope: tracked metta/*.metta and *.pl. MeTTa equation bodies: expression
heads and named collection callbacks; Prolog clauses: body calls and common
meta-call callbacks. Names resolve across languages (arity is deliberately
ignored, matching the structural analysis). Imports, stores, dynamic calls,
generated predicates, type declarations and execution frequencies are excluded.
"""
import argparse
import collections
import json
from pathlib import Path
import re
import subprocess
import tempfile


def forms(source):
    tokens = re.findall(r';[^\n]*|"(?:\\.|[^"\\])*"|[()]|[^\s();]+', source)
    stack = []
    for token in tokens:
        if token.startswith(';'):
            continue
        if token == '(':
            stack.append([])
        elif token == ')':
            form = stack.pop()
            if stack:
                stack[-1].append(form)
            else:
                yield form
        elif stack:
            stack[-1].append(token)


def references(term):
    if not isinstance(term, list) or not term:
        return
    if isinstance(term[0], str):
        yield term[0]
        if re.match(r'(?:map|fold|foldr|filter|foreach|any|all|sort|partition|include|exclude)', term[0]):
            for arg in term[1:]:
                if isinstance(arg, str):
                    yield arg
    for child in term:
        yield from references(child)


def measure(root, revision=None):
    command = ['ls-tree', '-r', '--name-only', revision, '--', 'pettachainer/metta'] if revision else ['ls-files', 'pettachainer/metta']
    files = subprocess.check_output(['git', '-C', str(root), *command], text=True).splitlines()
    files = sorted(f for f in files if Path(f).suffix in ('.metta', '.pl'))
    rows = []
    for file in files:
        if not file.endswith('.metta'):
            continue
        source = subprocess.check_output(['git', '-C', str(root), 'show', f'{revision}:{file}'], text=True) if revision else (root / file).read_text()
        for form in forms(source):
            if len(form) == 3 and form[0] == '=' and isinstance(form[1], list) and form[1] and isinstance(form[1][0], str):
                rows.append(dict(file=file, name=form[1][0], refs=list(references(form[2]))))
    # Parse historical native files from a temporary snapshot, without consulting
    # project code or changing another checkout.
    native = [f for f in files if f.endswith('.pl')]
    with tempfile.TemporaryDirectory(prefix='reference-native-') as tmp:
        parse_root = Path(tmp) if revision else root
        if revision:
            for f in native:
                target = parse_root / f
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(subprocess.check_output(['git', '-C', str(root), 'show', f'{revision}:{f}']))
        native_rows = json.loads(subprocess.check_output(['swipl', '-q', '-f', str(Path(__file__).with_name('reference_terms.pl')), '--', *[str(parse_root / f) for f in native]], text=True))
        for row in native_rows:
            row['file'] = str(Path(row['file']).relative_to(parse_root))
    rows += native_rows
    owners = collections.defaultdict(set)
    for row in rows:
        owners[row['name']].add(row['file'])
    edges = collections.defaultdict(set)
    for row in rows:
        for name in row['refs']:
            for owner in owners.get(name, set()) - {row['file']}:
                edges[row['file'], owner].add(name)
    graph = {f: set() for f in files}
    for a, b in edges:
        graph[a].add(b)
    index, low, stack, active, components = {}, {}, [], set(), []
    def visit(v):
        index[v] = low[v] = len(index)
        stack.append(v)
        active.add(v)
        for w in sorted(graph[v]):
            if w not in index:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in active:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            component = []
            while True:
                w = stack.pop()
                active.remove(w)
                component.append(w)
                if w == v:
                    break
            components.append(sorted(component))
    for v in graph:
        if v not in index:
            visit(v)
    upward = {(a,b): names for (a,b), names in edges.items() if '/compiler/' in b and ('/runtime/' in a or '/prolog/' in a)}
    return dict(files=len(files), names=len(owners), file_edges=len(edges), external_references=sum(map(len,edges.values())), reciprocal_pairs=sum((b,a) in edges for a,b in edges)//2, largest_scc=max(map(len,components)), sccs=sorted(components,key=lambda c:(-len(c),c)), runtime_native_compiler_edges=len(upward), runtime_native_compiler_references=sum(map(len,upward.values())), upward=[dict(caller=a,callee=b,names=sorted(ns)) for (a,b),ns in sorted(upward.items())], edges=[dict(caller=a,callee=b,names=sorted(ns)) for (a,b),ns in sorted(edges.items())])

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--revision')
    args = parser.parse_args()
    print(json.dumps(measure(Path.cwd(), args.revision), indent=2))
