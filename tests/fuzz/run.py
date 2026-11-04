"""Run a KB through ProbLog and PeTTaChainer and judge the difference.

ProbLog runs in its own interpreter (``PROBLOG_PYTHON``), PeTTaChainer in a
fresh process per KB (``chainer_worker.py``) under an address-space cap, so a
case never sees another case's state.
"""

from __future__ import annotations

import json
import os
import re
import resource
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .kb import KB, EventKB, MettaProgram, metta, problog

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PROBLOG_PYTHON = os.environ.get("PROBLOG_PYTHON", "/nexus/Dev/OpenCog/ChainerGame-problog/.venv-problog/bin/python")
CHAINER_PYTHON = os.environ.get("CHAINER_PYTHON", str(REPO / ".venv" / "bin" / "python"))
ADDRESS_LIMIT = 16_000_000 * 1024  # ulimit -v 16000000


@dataclass
class Settings:
    budgets: tuple[int, ...] = (100, 2000)  # the last one is judged; the first checks that more budget is no worse
    k: float = 5.0  # evidence confidence k, as SupplyNet runs the chainer
    threshold: float = 0.05
    timeout: float = 300.0


def oracle(kbs: list[KB]) -> list[dict]:
    """Per KB: {"exact": {atom: p}, "prior": {atom: p}} or {"error": ...}.
    "prior" is the marginal without the observations."""
    texts = []
    for kb in kbs:
        texts += [problog(kb), problog(kb, evidence=False)]
    done = subprocess.run([PROBLOG_PYTHON, str(HERE / "problog_worker.py")], input=json.dumps(texts), capture_output=True, text=True, check=True)
    results = json.loads(done.stdout)
    out = []
    for kb, exact, prior in zip(kbs, results[::2], results[1::2]):
        if "error" in exact or "error" in prior:
            out.append({"error": exact.get("error") or prior.get("error")})
            continue
        atoms = [f"{pred.lower()}({ind})" for pred, ind in kb.queries]
        out.append({"exact": [exact["marginals"][a] for a in atoms], "prior": [prior["marginals"][a] for a in atoms]})
    return out


def _limit() -> None:
    resource.setrlimit(resource.RLIMIT_AS, (ADDRESS_LIMIT, ADDRESS_LIMIT))


def chainer(kb: KB, settings: Settings) -> dict:
    """Budget/query answers, {"unsupported": feature/stage label}, or {"error": ...}."""
    event = isinstance(kb, (EventKB, MettaProgram))
    program = kb if isinstance(kb, MettaProgram) else kb.program() if event else metta(kb, settings.k)
    job = {
        "event": event,
        "probe": kb.probe if isinstance(kb, EventKB) else [],
        "target": os.environ.get("FUZZ_CHAINER_REPO"),
        "k": settings.k,
        "complete": program.complete,
        "refinement": program.refinement,
        "statements": program.statements,
        "base_rates": program.base_rates,
        "queries": program.queries,
        "budgets": list(settings.budgets),
    }
    env = {key: value for key, value in os.environ.items() if key != "DISPLAY"}
    try:
        done = subprocess.run(
            [CHAINER_PYTHON, str(HERE / "chainer_worker.py")],
            input=json.dumps(job), capture_output=True, text=True, timeout=settings.timeout,
            preexec_fn=_limit, env=env, cwd="/tmp",
        )
    except subprocess.TimeoutExpired:
        return {"error": f"timeout after {settings.timeout:.0f} s"}
    marker = done.stdout.rfind("@@RESULT@@")
    if done.returncode != 0 or marker < 0:
        # Workers can be supplied by another backend via CHAINER_PYTHON.
        # Read the terminal exception, not an earlier chained exception or
        # a mention of an unsupported feature in an ordinary crash message.
        lines = (done.stderr or done.stdout).strip().splitlines()
        if done.returncode > 0 and lines:
            missing = re.fullmatch(r"(?:\w+\.)*(NotImplementedError|UnsupportedCompilation)(?::\s*(.*))?", lines[-1])
            if missing:
                return {"unsupported": missing[2] or missing[1]}
        tail = (done.stderr or done.stdout).strip().splitlines()[-3:]
        return {"error": f"exit {done.returncode}: {' | '.join(tail)[:400]}"}
    result = json.loads(done.stdout[marker + len("@@RESULT@@"):])
    if event:
        if "answers" in result:
            result["answers"] = {int(b): rows for b, rows in result["answers"].items()}
        return result
    return result if "unsupported" in result else {int(budget): rows for budget, rows in result.items()}


def best(answers: list) -> tuple[float, str] | None:
    """The strength (clipped to [0, 1]) and proof of the most confident
    answer, as ChainerGame reads it."""
    if not answers:
        return None
    strength, _confidence, proof = max(answers, key=lambda answer: answer[1])
    return min(1.0, max(0.0, strength)), proof


SEVERITY = ["crash", "no_answer", "wrong_direction", "error", "budget_regression"]
# No answer where the chainer documents none (docs/metta/fuzzing.md): through
# an unobserved root premise with no observation below it (a derivation reads
# no population prior), or for such a root itself when no rule reads its base
# rate (a population prior is the base-rate fold of an inversion or a
# completion, so a root read by no rule has none).
# A derived atom whose premises are such roots is answered by its predicate's
# population prior, the rate of its stored facts, where ProbLog derives it from
# the model: sampling noise of a history, or one observation of another
# individual, not a defect.
EXPECTED = ["gap_latent_premise", "gap_root_prior", "gap_derived_population_prior"]


@dataclass
class Verdict:
    rows: list[dict] = field(default_factory=list)  # per query
    flags: list[tuple[str, int]] = field(default_factory=list)  # (category, query index)
    error: str | None = None
    unsupported: str | None = None

    @property
    def category(self) -> str | None:
        if self.unsupported is not None:
            return "unsupported"
        found = {category for category, _ in self.flags}
        return next((c for c in SEVERITY if c in found), None)


def judge(kb: KB, exact: dict, answers: dict, settings: Settings) -> Verdict:
    verdict = Verdict()
    if "unsupported" in answers:
        verdict.unsupported = answers["unsupported"]
        return verdict
    if "error" in answers:
        verdict.error = answers["error"]
        verdict.flags.append(("crash", 0))
        return verdict
    low, high = settings.budgets[0], settings.budgets[-1]
    for i, (pred, ind) in enumerate(kb.queries):
        p, prior = exact["exact"][i], exact["prior"][i]
        judged, low_answer = best(answers[high][i]), best(answers[low][i])
        s_high, proof = judged or (None, None)
        s_low = low_answer[0] if low_answer else None
        err = None if s_high is None else abs(s_high - p)
        err_low = None if s_low is None else abs(s_low - p)
        verdict.rows.append({"atom": f"({pred} {ind})", "exact": p, "prior": prior, "pln": s_high, "pln_low": s_low, "err": err, "err_low": err_low, "proof": proof})
        if pred not in kb.roots and kb.latent_premise(pred, ind) and proof and proof.startswith("(population-prior"):
            verdict.flags.append(("gap_derived_population_prior", i))
            continue
        if s_high is None:
            root_prior = pred in kb.roots and not kb.latent_premise(pred, ind) and kb.unobserved_below(pred, ind)
            verdict.flags.append(("gap_root_prior" if root_prior else "gap_latent_premise" if kb.latent_premise(pred, ind) else "no_answer", i))
            continue
        if abs(p - prior) > settings.threshold and (s_high - prior) * (p - prior) < 0 and abs(s_high - prior) > 0.02:
            verdict.flags.append(("wrong_direction", i))
        elif err > settings.threshold:
            verdict.flags.append(("error", i))
        if err_low is not None and err > err_low + settings.threshold:
            verdict.flags.append(("budget_regression", i))
    return verdict


def evaluate(kbs: list[KB], settings: Settings, jobs: int = 2) -> list[tuple[dict, dict, Verdict | None]]:
    """Run every KB on both sides; a KB whose ProbLog program fails (impossible
    evidence) gets no verdict."""
    from concurrent.futures import ThreadPoolExecutor

    exact = oracle(kbs)
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        answers = list(pool.map(lambda pair: chainer(pair[0], settings) if "error" not in pair[1] else {}, zip(kbs, exact)))
    return [(e, a, None if "error" in e else judge(kb, e, a, settings)) for kb, e, a in zip(kbs, exact, answers)]


def reexec_capped() -> None:
    """Run the calling script inside bench.slice (docs/agent_workflow.md)."""
    if "bench.slice" not in Path("/proc/self/cgroup").read_text():
        slots = "2"
        if "--jobs" in sys.argv:
            slots = sys.argv[sys.argv.index("--jobs") + 1]
        os.environ.pop("DISPLAY", None)
        _limit()
        os.execv("/nexus/Dev/OpenCog/bench/capped", ["capped", "--slots", slots,
                   sys.executable, *sys.argv])


def event_judge(kb, exact, result, settings):
    """Severity gate: a wrong, lost or overconfident answer is a BLOCKER."""
    import math
    flags = []
    rows = []
    if 'error' in result or 'unsupported' in result:
        return [{'severity': 'BLOCKER', 'invariant': 'lost_answer', 'query': 0,
                 'detail': result.get('error', result.get('unsupported'))}], rows
    if kb.probe:
        work = result['probe']
        ratios = [b['inferences']/a['inferences'] for a, b in zip(work, work[1:])]
        if len(ratios) >= 2 and min(ratios[-2:]) > 3:
            flags.append({'severity': 'BLOCKER', 'invariant': 'bounded_work', 'query': 0,
                          'expected': 'doubling producers must not repeatedly quadruple catalog work',
                          'actual': work})
        return flags, rows
    answers = result['answers']
    high, low = settings.budgets[-1], settings.budgets[0]
    for i, q in enumerate(kb.queries):
        choices = answers[high][i]
        answer = max(choices, key=lambda r: r[1]) if choices else None
        row = {'query': i, 'answer': answer, 'reference': exact.get('rows', [None]*len(kb.queries))[i]}
        rows.append(row)
        if 'subset' in exact and answer is not None and answer[0] > exact['subset']['s']+1e-6:
            flags.append({'severity': 'BLOCKER', 'invariant': 'identity-subset', 'query': i,
                          'expected': {'at_most': exact['subset']['s']}, 'actual': answer[0]})
        if answer is None and answers[low][i]:
            flags.append({'severity': 'BLOCKER', 'invariant': 'budget_regression', 'query': i,
                          'expected': 'higher budget retains an answer', 'actual': None})
        if row['reference'] is None:
            continue
        target = row['reference']
        if answer is None:
            flags.append({'severity': 'BLOCKER', 'invariant': 'lost_answer', 'query': i, 'expected': target['s']})
            continue
        s, c, _ = answer
        err = abs(s-target['s'])
        if not math.isfinite(s) or not 0 <= s <= 1 or not math.isfinite(c) or not 0 <= c <= 1:
            flags.append({'severity': 'BLOCKER', 'invariant': 'invalid_tv', 'query': i, 'actual': answer})
            continue
        clipped = min(max(s, 1e-6), 1-1e-6)
        variance = clipped*(1-clipped)/(settings.k*c/(1-c)+1) if c < 1 else 0
        row.update(error=err, variance=variance)
        if err > settings.threshold:
            flags.append({'severity': 'BLOCKER', 'invariant': 'wrong_strength', 'query': i, 'expected': target['s'], 'actual': s})
        # Two standard deviations cover the stated error, as in the event
        # contract's unknown-coupling interval. Ignore sub-tolerance rounding.
        if err > settings.threshold and err > 2*math.sqrt(variance)+settings.threshold:
            flags.append({'severity': 'BLOCKER', 'invariant': 'overconfident_error', 'query': i,
                          'expected': target['s'], 'actual': s, 'claimed_sd': math.sqrt(variance)})
        lower = target['variance_lower']
        if variance + 1e-10 < .8*lower:
            flags.append({'severity': 'BLOCKER', 'invariant': 'overconfident_variance', 'query': i,
                          'expected_at_least': lower, 'actual': variance, 'reference_status': 'certified-lower-bound'})
        elif target['variance'] is not None and target['variance_delta'] < 1e-7 and variance+1e-10 < .8*target['variance']:
            # Numerical integration alone cannot certify a blocker.
            flags.append({'severity': 'FOLLOW-UP', 'invariant': 'variance_numerical', 'query': i,
                          'expected': target['variance'], 'actual': variance, 'delta': target['variance_delta']})
        low_answer = best(answers[low][i])
        if low_answer and err > abs(low_answer[0]-target['s'])+settings.threshold:
            flags.append({'severity': 'BLOCKER', 'invariant': 'budget_regression', 'query': i,
                          'expected': 'higher budget has no larger error', 'actual': [low_answer[0], s]})
    return flags, rows


def event_evaluate(kb, settings, execute):
    from .event_oracle import reference
    from .generator import mutate_event
    exact = reference(kb, settings.k)
    if 'identity-subset' in kb.checks:
        # Q = I and judgment implies Q <= I, without inventing a probability
        # for the judgment. Unobserved identity parts have uniform count laws.
        identity = kb.reports[0][0]
        control = EventKB('identity-bound', dict.fromkeys(identity[1:], (.5, 0, 'count')),
                          [], kb.reports, [identity])
        exact['subset'] = reference(control, settings.k)['rows'][0]
    result = execute(kb)
    flags, rows = event_judge(kb, exact, result, settings)
    variants = {}
    if 'answers' not in result or kb.probe:
        return {'kb': kb.to_json(), 'exact': exact, 'result': result, 'rows': rows, 'flags': flags, 'variants': variants}
    high = settings.budgets[-1]
    base = [best(a) for a in result['answers'][high]]
    for check in kb.checks:
        if check in ('bounds', 'budget', 'identity-subset'):
            continue
        variant = mutate_event(kb, check)
        other = execute(variant)
        variants[check] = other
        if 'answers' not in other:
            flags.append({'severity': 'BLOCKER', 'invariant': check, 'query': 0, 'detail': other})
            continue
        if kb.reference and check in ('neutral', 'inactive'):
            numeric_flags, _ = event_judge(kb, exact, other, settings)
            for f in numeric_flags:
                f['variant'] = check
            flags.extend(numeric_flags)
        changed = [best(a) for a in other['answers'][high]]
        for i, (before, after) in enumerate(zip(base, changed)):
            # No-answer is an absence, not the probability zero. False
            # constraints permit either absence or a zero-strength answer.
            broken = False
            expected = 'same strength and answer availability'
            actual = [before[0] if before else None, after[0] if after else None]
            if check == 'false':
                broken = after is not None and after[0] > 1e-6
                expected = 0
            elif check == 'flip':
                control = kb.copy()
                control.reference = True
                flipped = mutate_event(control, check)
                e0, e1 = reference(control, settings.k), reference(flipped, settings.k)
                if e0['status'] == 'enumerated' and e1['status'] == 'enumerated':
                    delta = e1['rows'][i]['s']-e0['rows'][i]['s']
                    if abs(delta) > settings.threshold:
                        broken = before is None or after is None or (after[0]-before[0])*delta <= 1e-8
                        expected = 'observation flip changes strength ' + ('up' if delta > 0 else 'down')
            elif check == 'class-rule':
                broken = before is not None and (after is None or abs(after[0]-before[0]) > 1e-6)
                expected = 'inactive derived link preserves an existing classification'
            elif check == 'redundant':
                actual = [max(choices, key=lambda r: r[1])[:2] if choices else None
                          for choices in (result['answers'][high][i], other['answers'][high][i])]
                broken = (before is None) != (after is None) or (before is not None and
                          any(abs(x-y) > 1e-6 for x, y in zip(*actual)))
                expected = 'same strength, confidence and answer availability'
            else:
                broken = (before is None) != (after is None) or (before is not None and abs(before[0]-after[0]) > 1e-6)
            if broken:
                flags.append({'severity': 'BLOCKER', 'invariant': check, 'query': i,
                              'expected': expected, 'actual': actual})
    if 'bounds' in kb.checks and len(base) == 3 and all(base):
        a, b, joint = [v[0] for v in base]
        if joint > min(a, b)+1e-6 or joint < max(0, a+b-1)-1e-6:
            flags.append({'severity': 'BLOCKER', 'invariant': 'frechet', 'query': 2,
                          'expected': [max(0, a+b-1), min(a, b)], 'actual': joint})
    return {'kb': kb.to_json(), 'exact': exact, 'result': result, 'rows': rows, 'flags': flags, 'variants': variants}


def event_campaign(args):
    """The event mode of the existing fuzzer; same worker and shrink module."""
    import time
    import threading
    from concurrent.futures import ThreadPoolExecutor, Future
    from .generator import event_cases, mutate_event
    from .shrink import shrink_event
    started = time.monotonic()
    inputs = {p: p.read_bytes() for p in sorted(HERE.glob('*.py')) +
              [REPO/'scripts/fuzz_vs_problog.py', REPO/'tests/tv_calibration_oracles.py']}
    out = args.out
    (out/'repros').mkdir(parents=True, exist_ok=True)
    settings = Settings((100, 500) if args.budgets == '100,2000' else tuple(map(int, args.budgets.split(','))),
                        args.k if args.k is not None else 800, args.threshold if args.threshold is not None else .001, 45)
    cache, lock = {}, threading.Lock()

    def execute(kb):
        program = kb.program() if isinstance(kb, EventKB) else kb
        key = json.dumps({'program': vars(program), 'probe': kb.probe if isinstance(kb, EventKB) else []}, sort_keys=True)
        with lock:
            owner = key not in cache
            if owner:
                cache[key] = Future()
            future = cache[key]
        if owner:
            try:
                future.set_result(chainer(kb, settings))
            except BaseException as exc:
                future.set_exception(exc)
                raise
        return future.result()

    seeds = range(args.seed, args.seed+(20 if args.long else 1))
    kbs = [kb for seed in seeds for kb in event_cases(seed, args.long)]
    # Warm the load cache in one process before admitting parallel workers.
    execute(kbs[0])
    def process(kb):
        case = event_evaluate(kb, settings, execute)
        for index, flag in enumerate(case['flags']):
            small, detail, attempts, minimal = shrink_event(kb, flag, settings, execute, 80 if args.long else 24)
            name = f'{kb.name}-{index}-{flag["invariant"]}'
            payload = {'kb': small.to_json(), 'flag': detail, 'attempts': attempts, 'one_minimal': minimal,
                       'settings': vars(settings), 'original': kb.name}
            (out/'repros'/f'{name}.json').write_text(json.dumps(payload, indent=2))
            header = f';; {flag["severity"]}: {flag["invariant"]}\n;; {json.dumps(detail)}\n;; deletion minimal: {minimal}, trials: {attempts}\n'
            repo = os.environ.get('FUZZ_CHAINER_REPO', str(REPO))
            (out/'repros'/f'{name}.metta').write_text(header+small.metta_file(settings.budgets[-1], settings.k, repo))
            variant_check = flag.get('variant', flag['invariant'])
            if variant_check in small.checks and variant_check != 'identity-subset':
                variant = mutate_event(small, variant_check)
                if isinstance(variant, EventKB):
                    (out/'repros'/f'{name}-variant.metta').write_text(header+variant.metta_file(settings.budgets[-1], settings.k, repo))
                else:
                    # A transformed program is still a standalone replay.
                    text = [f'!(import! &self {repo}/pettachainer/metta/petta_chainer)', f'!(set-evidence-confidence-k {settings.k})']
                    text += [f'!(compileadd kb {s})' for s in variant.statements]
                    text += [f'!(set-base-rate kb {a} {tv})' for a, tv in variant.base_rates]
                    text += [f'!(query {settings.budgets[-1]} kb {q})' for q in variant.queries]
                    (out/'repros'/f'{name}-variant.metta').write_text(header+'\n'.join(text)+'\n')
            flag['repro'] = name
            flag['one_minimal'] = minimal
        print(f'{kb.name}: {len(case["flags"])} violations ({time.monotonic()-started:.1f}s)', flush=True)
        return case
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        cases = list(pool.map(process, kbs))
    # Retain the existing ProbLog differential as a small part of this gate.
    from .generator import generate
    pl_kbs = [generate(args.seed*1_000_003+i, ['chain', 'shared', 'observe']) for i in range(3 if not args.long else 50)]
    differential = evaluate(pl_kbs, settings, args.jobs)
    pl_results = [{'kb': kb.to_json(), 'exact': e, 'answers': a,
                   'flags': v.flags if v else [], 'error': e.get('error') if v is None else v.error}
                  for kb, (e, a, v) in zip(pl_kbs, differential)]
    from .shrink import shrink
    from .kb import metta_file
    for number, (kb, (_, _, verdict), stored) in enumerate(zip(pl_kbs, differential, pl_results)):
        stored['repros'] = []
        if verdict is None:
            continue
        for category, index in verdict.flags:
            if category not in SEVERITY:
                continue
            small, found, trials = shrink(kb, category, kb.queries[index], settings, limit=24)
            if found is None:
                continue
            name = f'problog-{number}-{category}-{index}'
            data = {'kb': small.to_json(), 'category': category, 'rows': found.rows, 'runs': trials}
            (out/'repros'/f'{name}.json').write_text(json.dumps(data, indent=2))
            (out/'repros'/f'{name}.pl').write_text(problog(small))
            (out/'repros'/f'{name}.metta').write_text(metta_file(small, settings.budgets[-1], settings.k,
                                                   os.environ.get('FUZZ_CHAINER_REPO', str(REPO))))
            stored['repros'].append(name)
    counts = {}
    for case in cases:
        for f in case['flags']:
            key = f'{f["severity"]}:{f["invariant"]}'
            counts[key] = counts.get(key, 0)+1
    pl_bad = sum(any(c in SEVERITY for c, _ in r['flags']) or bool(r['error']) for r in pl_results)
    seconds = time.monotonic()-started
    runtime_paths = sorted({c['result'].get('runtime', '') for c in cases} - {''})
    runtime_commits = {p: subprocess.check_output(['git', '-C', str(Path(p).parent.parent), 'rev-parse', 'HEAD'], text=True).strip()
                       for p in runtime_paths}
    import hashlib
    source_hash = hashlib.sha256()
    for path, content in inputs.items():
        source_hash.update(path.name.encode()+content)
    inputs_changed = any(p.read_bytes() != content for p, content in inputs.items())
    summary = {'seconds': round(seconds, 2), 'mode': 'long' if args.long else 'quick',
               'target': os.environ.get('FUZZ_CHAINER_REPO', CHAINER_PYTHON),
               'runtime_paths': runtime_paths, 'runtime_commits': runtime_commits,
               'fuzzer_sha256': source_hash.hexdigest(), 'inputs_changed': inputs_changed, 'seed': args.seed,
               'cases': len(cases), 'worker_runs': len(cache), 'violations': counts,
               'problog_cases': len(pl_results), 'problog_flagged': pl_bad,
               'settings': vars(settings), 'under_ten_minutes': seconds <= 600}
    (out/'cases.jsonl').write_text(''.join(json.dumps(c)+'\n' for c in cases))
    (out/'problog.json').write_text(json.dumps(pl_results, indent=1))
    (out/'summary.json').write_text(json.dumps(summary, indent=2))
    lines = ['# Event differential + metamorphic fuzzing', '', '```json', json.dumps(summary, indent=2), '```', '',
             '| case | severity | invariant | expected | actual | repro |', '|---|---|---|---|---|---|']
    for c in cases:
        for f in c['flags']:
            lines.append(f'| {c["kb"]["name"]} | {f["severity"]} | {f["invariant"]} | {f.get("expected", f.get("expected_at_least", ""))} | {f.get("actual", f.get("detail", ""))} | [repro](repros/{f["repro"]}.json) |')
    (out/'summary.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps(summary, indent=2), flush=True)
    return int(inputs_changed or any(f['severity'] == 'BLOCKER' for c in cases for f in c['flags']) or pl_bad > 0)
