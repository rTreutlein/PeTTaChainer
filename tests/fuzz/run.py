"""Run a KB through ProbLog and PeTTaChainer and judge the difference.

ProbLog runs in its own interpreter (``PROBLOG_PYTHON``), PeTTaChainer in a
fresh process per KB (``chainer_worker.py``) under an address-space cap, so a
case never sees another case's state.
"""

from __future__ import annotations

import json
import os
import resource
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

from .kb import KB, metta, problog

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


def chainer(kb: KB, settings: Settings, expand: bool = False) -> dict:
    """{budget: [[strength, confidence, proof], ...] per query} or {"error": ...}."""
    program = metta(kb, settings.k)
    job = {
        "k": settings.k,
        "complete": program.complete,
        "refinement": program.refinement,
        "statements": program.statements,
        "base_rates": program.base_rates,
        "queries": program.queries,
        "budgets": list(settings.budgets),
        "expand": expand,
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
        tail = (done.stderr or done.stdout).strip().splitlines()[-3:]
        return {"error": f"exit {done.returncode}: {' | '.join(tail)[:400]}"}
    return {int(budget): rows for budget, rows in json.loads(done.stdout[marker + len("@@RESULT@@"):]).items()}


def strength(answers: list) -> float | None:
    """The strength of the most confident answer (as ChainerGame reads it)."""
    if not answers:
        return None
    best = max(answers, key=lambda answer: answer[1])
    return min(1.0, max(0.0, best[0]))


SEVERITY = ["crash", "no_answer", "wrong_direction", "error", "budget_regression"]
# No answer where the chainer documents none (docs/metta/fuzzing.md): through
# an unobserved root premise with no observation below it, or for such a root
# itself when no rule reads its base rate (a population prior is the base-rate
# fold of an inversion, so a root read only through Or, or by no rule, has none).
EXPECTED = ["gap_latent_premise", "gap_root_prior"]


@dataclass
class Verdict:
    rows: list[dict] = field(default_factory=list)  # per query
    flags: list[tuple[str, int]] = field(default_factory=list)  # (category, query index)
    error: str | None = None

    @property
    def category(self) -> str | None:
        found = {category for category, _ in self.flags}
        return next((c for c in SEVERITY if c in found), None)

    def worst(self, category: str) -> int:
        """The flagged query of ``category`` with the largest error."""
        indices = [i for c, i in self.flags if c == category]
        return max(indices, key=lambda i: self.rows[i]["err"] if self.rows[i]["err"] is not None else 2.0)


def judge(kb: KB, exact: dict, answers: dict, settings: Settings) -> Verdict:
    verdict = Verdict()
    if "error" in answers:
        verdict.error = answers["error"]
        verdict.flags.append(("crash", 0))
        return verdict
    low, high = settings.budgets[0], settings.budgets[-1]
    for i, (pred, ind) in enumerate(kb.queries):
        p, prior = exact["exact"][i], exact["prior"][i]
        s_high, s_low = strength(answers[high][i]), strength(answers[low][i])
        err = None if s_high is None else abs(s_high - p)
        err_low = None if s_low is None else abs(s_low - p)
        verdict.rows.append({"atom": f"({pred} {ind})", "exact": p, "prior": prior, "pln": s_high, "pln_low": s_low, "err": err, "err_low": err_low})
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


def evaluate(kbs: list[KB], settings: Settings, jobs: int = 2, expand: bool = False) -> list[tuple[dict, dict, Verdict | None]]:
    """Run every KB on both sides; a KB whose ProbLog program fails (impossible
    evidence) gets no verdict."""
    from concurrent.futures import ThreadPoolExecutor

    exact = oracle(kbs)
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        answers = list(pool.map(lambda pair: chainer(pair[0], settings, expand) if "error" not in pair[1] else {}, zip(kbs, exact)))
    return [(e, a, None if "error" in e else judge(kb, e, a, settings)) for kb, e, a in zip(kbs, exact, answers)]


def in_bench_slice() -> bool:
    return "bench.slice" in Path("/proc/self/cgroup").read_text()


def reexec_capped() -> None:
    """Run the calling script inside bench.slice (docs/agent_workflow.md)."""
    if not in_bench_slice() and subprocess.run(["systemctl", "--user", "cat", "bench.slice"], capture_output=True).returncode == 0:
        os.execvp("systemd-run", ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=bench.slice", "-p", "OOMPolicy=continue", "--", sys.executable, *sys.argv])
