"""Diagnostic copies print posterior pins without changing validation tests.

The actual acceptance suite is still scripts/test_metta.sh. Copies are kept
under scratch/confvar/pins and use the repository-pinned executable/runtime cwd.
"""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from pettachainer.metta_syntax import parse_source, render

target = ROOT/'scratch/confvar/pins'
target.mkdir(parents=True, exist_ok=True)
helper = target/'posterior_assertions.metta'
helper.write_text('''(: posterior-tv-near? (-[det]-> Number Number TV Bool))
(= (posterior-tv-near? $expected-s $expected-c $tv)
   (let $_ (println! (confvar-pin $expected-s $expected-c $tv)) true))
''')


def capture(path):
    forms = parse_source(path.read_text())
    assert forms is not None, path
    for i, form in enumerate(forms):
        if not isinstance(form, list):
            continue
        if form[0] in ('import!', 'cached-import!'):
            imported = (path.parent/form[2]).resolve()
            form[2] = str(helper.with_suffix('') if imported.name == 'posterior_assertions' else imported)
        elif form[0] == 'test':
            forms[i] = ['println!', ['confvar-test', str(i), form[1], ['quote', form[2]]]]
        elif form[0] == '=' and isinstance(form[1], list) and form[1][0] == 'exists-answer-matches':
            form[2] = ['let', '$_trace', ['println!', ['confvar-exists', '$strength', '$confidence', '$answer']], form[2]]
    copied = target/path.name
    copied.write_text('\n'.join(map(render, forms)).replace('!\n(', '!(')+'\n')
    result = subprocess.run([str(ROOT/'.venv/bin/petta'), str(copied), '--silent'],
                            cwd=ROOT/'pettachainer/metta', stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (target/(path.stem+'.log')).write_text(result.stdout)
    return dict(file=str(path.relative_to(ROOT)), exit=result.returncode,
                pins=[parse_source(line)[0] for line in result.stdout.splitlines()
                      if line.startswith('(confvar-')])


if __name__ == '__main__':
    paths = [ROOT/p for p in sys.argv[1:]] if sys.argv[1:] else [p for p in sorted((ROOT/'tests/metta').glob('test*.metta'))
             if 'posterior_assertions' in p.read_text() or p.name == 'test_double_negation_evidence.metta']
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(capture, paths))
    (target/'captured.json').write_text(json.dumps(results, indent=2)+'\n')
    print([(r['file'], r['exit'], len(r['pins'])) for r in results])
    assert all(r['exit'] == 0 for r in results)
