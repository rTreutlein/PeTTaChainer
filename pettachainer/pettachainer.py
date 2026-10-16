import functools
import json
import logging
import math
import multiprocessing as mp
import os
from contextlib import contextmanager
from pathlib import Path
import threading
import time
import traceback
import uuid
import warnings
from typing import Iterator, List, NamedTuple, Optional, Sequence, Tuple
import __main__

from petta import PeTTa

from .pln_validator import check_query, check_stmt

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

LOADEDLIB = False
LOADED_LOCK = threading.Lock()


def get_language_spec(llm_focused: bool = True) -> str:
    return (Path(__file__).resolve().parent / ("LLM_RULE_SPEC.md" if llm_focused else "LANGUAGE_SPEC.md")).read_text(encoding="utf-8")


def _query_worker(state: dict, fn: str, source: str, conn):
    """Replay a chainer's settings and accepted inputs, as ``state`` (its
    attributes) holds them, in a fresh process and run one query there."""
    try:
        handler = PeTTaChainer(logic_config=state["_logic_config_path"])
        handler.set_evidence_confidence_k(state["_evidence_confidence_k"])
        handler.set_bayes_prior_count(state["_bayes_prior_count"])
        handler.set_context_reuse_threshold(state["_context_reuse_threshold"])
        handler.kb = state["kb"]
        handler.set_max_term_bytes(state["_replay_max_term_bytes"])
        handler.set_rule_refinement(state["_rule_refinement"])
        if state["_rule_change_hazard"] is not None:
            handler.set_rule_change_hazard(state["_rule_change_hazard"])
        handler.set_base_rate_smoothing(state["_base_rate_smoothing"])
        for head, (arity, positions) in state["_functional_predicates"].items():
            handler.set_functional_predicate(head, arity, positions)
        for head in state["_complete_predicates"]:
            handler.set_complete_predicate(head)
        for head in state["_positive_only_predicates"]:
            handler.set_positive_only_predicate(head)
        if state["_hypothesis_mining"]:
            handler.set_hypothesis_mining(*state["_hypothesis_mining"])
        for head, (position, layer) in state["_predicate_times"].items():
            handler.set_predicate_time(head, position, layer)
        if state["_time_link"]:
            handler.set_time_link(state["_time_link"])
        for head in state["_observed_predicates"]:
            handler.set_observed_predicate(head)
        handler.add_atoms_no_check(state["_added_atoms"])
        handler.set_max_term_bytes(state["_max_term_bytes"])
        conn.send(("ok", handler._call(fn, [source])))
    except Exception as exc:  # pragma: no cover
        conn.send(("err", (exc.__class__.__name__, str(exc), traceback.format_exc())))
    finally:
        conn.close()


# Process-wide wall seconds and count of chainer calls (PeTTaChainer.timing).
_call_wall_seconds = 0.0
_call_count = 0


def _timed(method):
    """Count a chainer call's wall time towards ``PeTTaChainer.timing``."""
    @functools.wraps(method)
    def timed(*args, **kwargs):
        global _call_wall_seconds, _call_count
        started = time.perf_counter()
        try:
            return method(*args, **kwargs)
        finally:
            _call_wall_seconds += time.perf_counter() - started
            _call_count += 1
    return timed


class Answer(NamedTuple):
    """One answer of ``query_many_refs``, ``(: proof statement tv)`` as terms:
    an expression is a list, a symbol or string a ``str``, a number an
    ``int`` or ``float``, and a variable a ``str`` starting with ``$``. The
    proof holds references into the proof store; ``expand_proof`` prints it
    in full."""

    proof: object
    statement: object
    tv: object


def _metta_text(term) -> str:
    """MeTTa source for a term as ``Answer`` holds it."""
    if isinstance(term, list):
        return "(" + " ".join(_metta_text(item) for item in term) + ")"
    if isinstance(term, float):
        mantissa, exponent, power = repr(term).partition("e")
        return mantissa + (".0" if exponent and "." not in mantissa else "") + exponent + power
    return str(term)


def _group_query_many_results(rows: List[str], count: int) -> List[List[str]]:
    """Group ``(query-result index answer)`` rows by root, dropping ``()``."""
    grouped: List[List[str]] = [[] for _ in range(count)]
    for row in rows:
        index, answer = row[len("(query-result "):-1].split(" ", 1)
        if answer != "()":
            grouped[int(index)].append(answer)
    return grouped


class PeTTaChainer:
    def __init__(self, logic_config: str = "pln"):
        global LOADEDLIB
        self.handler = PeTTa()
        self.kb = f"kb{uuid.uuid4().hex}"
        self._added_atoms: List[str] = []
        self._hypothesis_mining: Optional[Tuple[int, int]] = None
        self._predicate_times: dict[str, Tuple[int, int]] = {}
        self._time_link: Optional[str] = None
        self._evidence_confidence_k = 800.0
        self._bayes_prior_count = 0.2
        self._context_reuse_threshold = 0.000001
        self._max_term_bytes = 65536
        self._replay_max_term_bytes = 65536
        self._rule_refinement = False
        self._rule_change_hazard: Optional[float] = None
        self._base_rate_smoothing = False
        self._observed_predicates: List[str] = []
        self._complete_predicates: List[str] = []
        self._functional_predicates: dict[str, Tuple[int, Tuple[int, ...]]] = {}
        self._positive_only_predicates: List[str] = []
        self._query_metrics_enabled = False
        self._query_metrics_path = os.environ.get(
            "PETTACHAINER_QUERY_METRICS_PATH"
        )
        self._last_query_metrics: dict[str, object] = {}
        base_dir = Path(__file__).resolve().parent

        if not LOADEDLIB:
            with LOADED_LOCK:
                if not LOADEDLIB:
                    metta_path = base_dir / "metta" / "petta_chainer.metta"
                    logger.info("Loading MeTTa library from %s", metta_path)
                    self.handler.load_metta_file_cached(str(metta_path))
                    LOADEDLIB = True

        path = Path(logic_config)
        if not path.suffix and len(path.parts) == 1:
            path = base_dir / "metta" / "core" / "logic_configs" / f"{logic_config}.metta"
        self._logic_config_path = str(path.expanduser().resolve())
        self.handler.load_metta_file(self._logic_config_path)
        if self._query_metrics_path:
            self.set_query_metrics(True)

    def load_metta_file(self, path: str | Path) -> str:
        """Load a caller-owned MeTTa module into this runtime."""
        return self.handler.load_metta_file(str(Path(path).expanduser().resolve()))

    @staticmethod
    def _call(fn: str, sources: Sequence[str]) -> List[str]:
        """The results, as MeTTa text, of the chainer function ``fn`` applied
        to the arguments each of ``sources`` reads as, in order: what
        ``!(fn args)`` returns, without compiling a runnable for it."""
        import janus_swi

        return janus_swi.query_once(
            "metta_call_text(Fn, Sources, Results)", {"Fn": fn, "Sources": list(sources)}
        )["Results"]

    @staticmethod
    def timing() -> dict[str, float]:
        """Process-wide seconds of the chainer calls made so far (adding,
        querying, forward chaining, expanding proofs): ``wall`` as the caller
        sees them, the ``inference`` within them (activating what was added,
        search and evaluation of queries, forward runs) and ``overhead``, the
        rest (the Python layer, reading the call, compiling queries, their
        temporary additions, reading and printing results, storing
        statements), with the number of ``calls``. A query run in a timed
        subprocess counts as overhead. Take differences between two readings
        to time a span."""
        import janus_swi

        inference = float(janus_swi.query_once("inference_seconds(S)")["S"])
        return {
            "calls": _call_count,
            "wall": _call_wall_seconds,
            "inference": inference,
            "overhead": _call_wall_seconds - inference,
        }

    def evaluate_statement(self, atom: str) -> str:
        result = self.handler.process_metta_string(f"!(eval {atom})")
        if not result:
            raise ValueError("PeTTa returned no results")
        return result[0]

    evaluate_query = evaluate_statement

    @staticmethod
    def _validate(kind: str, atom: str, checker) -> None:
        if checker(atom) == 0.0:
            raise ValueError(f"Invalid PLN {kind}: {atom}")

    def set_query_metrics(self, enabled: bool) -> None:
        """Enable backward-query diagnostic counters.

        Metrics apply only to queries executed in this live runtime. Timed
        subprocess queries intentionally do not replay this diagnostic state.
        """
        value = "true" if enabled else "false"
        self.handler.process_metta_string(
            f"!(set-backward-query-metrics {value})"
        )
        self._query_metrics_enabled = enabled

    def last_query_metrics(self) -> dict[str, object]:
        """Return a copy of the most recently recorded query metrics."""
        return dict(self._last_query_metrics)

    @contextmanager
    def _query_metrics(
        self,
        *,
        kind: str,
        roots: int,
        steps: int,
        timeout_sec: Optional[float],
    ) -> Iterator[None]:
        record_metrics = self._query_metrics_enabled
        if record_metrics and timeout_sec is not None and timeout_sec > 0:
            warnings.warn(
                "query metrics skipped: timed queries run in a subprocess "
                "that does not replay diagnostic state; pass timeout_sec=0 "
                "to record metrics",
                stacklevel=3,
            )
            record_metrics = False
        if record_metrics:
            self.handler.process_metta_string("!(begin-backward-query-metrics!)")
            inference_before = self.timing()["inference"]
        started = time.perf_counter()
        yield
        if not record_metrics:
            return
        wall_seconds = time.perf_counter() - started
        inference_seconds = self.timing()["inference"] - inference_before
        self.handler.process_metta_string("!(end-backward-query-metrics!)")
        record: dict[str, object] = {
            "kind": kind,
            "roots": roots,
            "steps": steps,
            "wall_seconds": wall_seconds,
            "inference_seconds": inference_seconds,
            "overhead_seconds": wall_seconds - inference_seconds,
        }
        for row in self.handler.process_metta_string(
            "!(let $rows (backward-query-metrics) (superpose $rows))"
        ):
            _, key, raw_value = row[1:-1].split()
            value = float(raw_value)
            record[key.replace("-", "_")] = int(value) if value.is_integer() else value
        self._last_query_metrics = record
        if self._query_metrics_path:
            with Path(self._query_metrics_path).open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(record, sort_keys=True) + "\n")

    def set_evidence_confidence_k(self, k: float) -> None:
        """Set PLN's evidence parameter k: n observations have confidence n/(n+k).

        The setting is process-wide and read when a formula runs, so set it
        before adding knowledge; timed subprocess queries replay it.
        """
        self.handler.process_metta_string(
            f"!(set-evidence-confidence-k {float(k)!r})"
        )
        self._evidence_confidence_k = float(k)

    def set_bayes_prior_count(self, a: float) -> None:
        """Set the heterogeneity count kappa (default 0.2).

        The prior weight also accounts for uncertainty of its centre: it is
        max(0, 1/(1/(n_g+1) + 1/(kappa+1)) - 1), with n_g from the centre's
        confidence and the process-wide k. Certain centres give weight kappa;
        certain likelihoods/rates are unchanged. The method and parameter name
        are retained; a now denotes kappa. Timed queries replay this setting.
        """
        self.handler.process_metta_string(
            f"!(set-bayes-prior-count {float(a)!r})"
        )
        self._bayes_prior_count = float(a)

    def set_context_reuse_threshold(self, threshold: float) -> None:
        """Set Assuming's Beta-divergence propagation threshold (default 1e-6).

        Zero preserves exact value and compatibility changes. MAIN's user
        priors are inherited at every threshold. Timed queries replay this
        process-wide setting in their worker.
        """
        threshold = float(threshold)
        if not math.isfinite(threshold) or threshold < 0:
            raise ValueError("context reuse threshold must be finite and nonnegative")
        self._call("set-context-reuse-threshold", [repr(threshold)])
        self._context_reuse_threshold = threshold

    def set_forward_min_evidence(self, n: float) -> None:
        """Set the least evidence, in observations, a forward-chained result
        needs to start an output of its own (default 1). Process-wide."""
        self.handler.process_metta_string(
            f"!(set-forward-min-evidence {float(n)!r})"
        )

    def set_forward_seed_share(self, share: float) -> None:
        """Set the share of a forward run's steps the chosen facts no run has
        taken yet get before carried derived results compete for the rest
        (default 1). Process-wide."""
        self.handler.process_metta_string(
            f"!(set-forward-seed-share {float(share)!r})"
        )

    def set_forgetting(self, horizon: int, decay: float = 1.0) -> None:
        """Freeze keys idle for ``horizon`` epochs into summaries whose
        observation count is multiplied by ``decay`` (horizon 0: never).
        Process-wide; epochs end with ``advance_epoch``."""
        self.handler.process_metta_string(
            f"!(set-forgetting {int(horizon)} {float(decay)!r})"
        )

    def advance_epoch(self) -> int:
        """End an epoch and freeze the keys idle for the horizon; returns
        the new epoch."""
        return int(self.handler.process_metta_string("!(advance-epoch)")[0])

    def set_rule_refinement(self, enabled: bool) -> None:
        """Refine this KB's rules from their instances; set before adding rules.

        A refined rule applies with the revision of its stated truth and the
        fold of its instances. Timed subprocess queries replay the setting.
        """
        value = "true" if enabled else "false"
        self.handler.process_metta_string(f"!(set-rule-refinement {self.kb} {value})")
        self._rule_refinement = enabled

    def set_rule_change_hazard(self, hazard: float) -> None:
        """Set the prior probability that a sample of a refined rule's branch
        starts a new regime of its rate (default 0.0001; 0 keeps one regime);
        set before adding rules.

        Each branch of a refined rule's instance tally weighs the hypotheses
        of where its rate changed, and its truth is their posterior mixture
        (docs/metta/hypothesis_rules.md, "Regimes"). Timed subprocess queries
        replay the setting.
        """
        self.handler.process_metta_string(
            f"!(set-rule-change-hazard {self.kb} {float(hazard)!r})"
        )
        self._rule_change_hazard = float(hazard)

    def set_base_rate_smoothing(self, enabled: bool) -> None:
        """Read this KB's computed base rates as Beta estimates; set before adding.

        A base rate over n observations gets strength (sum + k/2) / (n + k),
        its evidence plus k pseudo-observations at 0.5; its confidence is
        unchanged. Timed subprocess queries replay the setting.
        """
        value = "true" if enabled else "false"
        self.handler.process_metta_string(f"!(set-base-rate-smoothing {self.kb} {value})")
        self._base_rate_smoothing = enabled

    def set_max_term_bytes(self, limit: int) -> None:
        """Set this KB's ingestion limit in canonical MeTTa UTF-8 bytes.

        The default is 65536. The complete evaluated source annotation is
        measured, including proof and truth value, for facts and rules.
        Timed query workers replay this setting before loading knowledge.
        """
        if not isinstance(limit, int) or isinstance(limit, bool) or limit <= 0:
            raise ValueError("max_term_bytes must be a positive integer")
        self._call("set-max-term-bytes", [f"{self.kb} {limit}"])
        self._max_term_bytes = limit
        self._replay_max_term_bytes = max(self._replay_max_term_bytes, limit)

    def set_functional_predicate(self, head: str, arity: int, key_positions: Sequence[int]) -> None:
        """Declare an immutable, single-valued input relation before its knowledge.

        Positions count from 1; all remaining arguments form the value. Facts
        must be ground and certain true. Another value, a probabilistic or
        negative fact, or any rule deriving this predicate raises an
        error. Unassigned keys remain open. This also declares the predicate
        positive-only. Timed subprocess queries replay the declaration.
        """
        positions = tuple(key_positions)
        if (not isinstance(arity, int) or isinstance(arity, bool) or arity < 2
                or not positions or len(positions) >= arity
                or any(not isinstance(p, int) or isinstance(p, bool) or not 1 <= p <= arity for p in positions)
                or tuple(sorted(set(positions))) != positions):
            raise ValueError("key_positions must be sorted, unique argument positions leaving a value")
        self.handler.process_metta_string(
            f"!(set-functional-predicate {self.kb} {head} {arity} ({' '.join(map(str, positions))}))"
        )
        self._functional_predicates[head] = (arity, positions)
        if head not in self._positive_only_predicates:
            self._positive_only_predicates.append(head)

    def set_complete_predicate(self, head: str) -> None:
        """Declare that the rules and facts of predicate ``head`` are the only
        ways one of its statements becomes true; declare before adding
        knowledge.

        A statement of it whose every derivation is circular or blocked is
        then false (docs/metta/complete_predicates.md). Timed subprocess
        queries replay the declaration.
        """
        self.handler.process_metta_string(f"!(set-complete-predicate {self.kb} {head})")
        if head not in self._complete_predicates:
            self._complete_predicates.append(head)

    def set_positive_only_predicate(self, head: str) -> None:
        """Declare that the KB stores only the true instances of predicate
        ``head``; declare before adding the rules that would be inverted onto
        it.

        Its stored instances are then no sample of its population: it has no
        population prior, nothing is inverted or completed onto it, and an STV
        rule with it in the antecedent applies as stated rather than
        reconciled with a rate of 1 (docs/metta/prior_factored_merge.md).
        Timed subprocess queries replay the declaration.
        """
        self.handler.process_metta_string(f"!(set-positive-only-predicate {self.kb} {head})")
        if head not in self._positive_only_predicates:
            self._positive_only_predicates.append(head)

    def set_hypothesis_mining(self, max_new: int, max_live: int) -> None:
        """Let the KB propose hypotheses from the facts added to it
        (``max_new`` 0 turns it off; docs/metta/hypothesis_rules.md).

        Each added true fact of a predicate with a declared place in time
        (``set_predicate_time``) may propose up to ``max_new`` refined rules
        with a weak prior between it and recent true facts sharing a
        constant with it, the cause being the fact at the earlier time point
        or, at one time point, of the lower layer: from pairs at once, from
        one fact once it recurs in another context; a consequent pattern
        keeps at most ``max_live`` live ones. Turns rule refinement on. Timed subprocess queries replay the
        setting, not the reviews.
        """
        self.handler.process_metta_string(
            f"!(set-hypothesis-mining {self.kb} {int(max_new)} {int(max_live)})"
        )
        self._hypothesis_mining = (int(max_new), int(max_live)) if max_new > 0 else None
        if max_new > 0:
            self._rule_refinement = True

    def set_predicate_time(self, head: str, position: int, layer: int) -> None:
        """Declare where predicate ``head`` sits in time for hypothesis
        mining: its facts refer to the time point at argument ``position``
        (counted from 1), and within a time point a fact of a lower ``layer``
        may cause one of a higher layer, never the reverse; equal layers are
        not related. Only declared predicates are mined
        (docs/metta/hypothesis_rules.md). Timed subprocess queries replay the
        declaration.
        """
        self.handler.process_metta_string(
            f"!(set-predicate-time {self.kb} {head} {int(position)} {int(layer)})"
        )
        self._predicate_times[head] = (int(position), int(layer))

    def set_time_link(self, head: str) -> None:
        """Declare that ``(head earlier later)`` facts link a time point to
        the next one, so hypothesis mining relates facts of adjacent time
        points, the earlier as the cause (docs/metta/hypothesis_rules.md).
        Timed subprocess queries replay the declaration.
        """
        self.handler.process_metta_string(f"!(set-time-link {self.kb} {head})")
        self._time_link = head

    def set_observed_predicate(self, head: str) -> None:
        """Declare that the statements of predicate ``head`` are observed:
        once a true ``set_time_link`` fact reaches a time point (state its
        observations before), each statement of ``head`` at it that a rule
        concludes and that has no stored fact is stored false, so a rule whose
        prediction did not come gets a negative sample
        (docs/metta/observed_predicates.md). Needs
        ``set_predicate_time`` for ``head`` and ``set_time_link``; declare
        before adding knowledge. Timed subprocess queries replay the
        declaration.
        """
        self.handler.process_metta_string(f"!(set-observed-predicate {self.kb} {head})")
        if head not in self._observed_predicates:
            self._observed_predicates.append(head)

    def review_hypotheses(self, goal: str = "$goal", steps: int = 200) -> List[str]:
        """Review the live mined hypotheses that apply to ``goal`` (all for a
        variable): read their truths, with ``steps`` for each one never read
        before, and drop the ones that do not predict. Returns one
        ``(hypothesis name implication truth kept|dropped)`` per hypothesis.
        """
        return self.handler.process_metta_string(
            f"!(review-hypotheses {int(steps)} {self.kb} {goal})"
        )

    @_timed
    def add_atom(self, atom: str) -> List[str]:
        self._validate("statement", atom, check_stmt)
        result = self._call("compileadd", [f"{self.kb} {atom}"])
        self._added_atoms.append(atom)
        return result

    def remove_statement(self, atom_name: str) -> str:
        """Deprecated: remove compiled KB/index rows for a named statement.

        Retracts the kb facts and rules that compileadd produced for
        ``(: <atom_name> ...)``, including their index rows and cached
        expected scores. Durable backward proofs are not forgotten, so this
        operation is outside the monotonic query contract. Statements whose
        compiled rules carry no extractable name (e.g. negated outputs) are
        not covered.
        """
        warnings.warn(
            "remove_statement() is deprecated and does not forget durable proofs",
            DeprecationWarning,
            stacklevel=2,
        )
        result = self.handler.process_metta_string(f"!(remove-compiled-statement {atom_name})")
        prefix = f"(: {atom_name} "
        self._added_atoms = [
            atom for atom in self._added_atoms
            if not atom.strip().startswith(prefix)
        ]
        return result

    @_timed
    def add_atoms_no_check(self, atoms: List[str]) -> List[str]:
        # Journal only successfully ingested inputs: a later rejection must
        # leave timed workers with the same accepted prefix as the live KB.
        result = []
        for atom in atoms:
            result.extend(self._call("compileadd", [f"{self.kb} {atom}"]))
            self._added_atoms.append(atom)
        return result

    def select_facts(self, terms: str | Sequence[str]) -> List[str]:
        """Return the KB facts matching one or more surface terms.

        Selection belongs to inference control, not to forward chaining. All
        requested terms are evaluated and selected in one PeTTa call so a
        controller can cheaply construct an initial seed set.
        """
        raw_terms = [terms] if isinstance(terms, str) else list(terms)
        if not raw_terms:
            return []
        selectors = [
            "(let* "
            f"(($type (eval {term})) "
            "($matches (collapse (once (match &kb "
            f"($type ({self.kb} MAIN Nil) $prf $tv) "
            f"($type ({self.kb} MAIN Nil) $prf $tv)))))) "
            "(if (== $matches ()) missing-selected-fact (car-atom $matches)))"
            for term in raw_terms
        ]
        results = self.handler.process_metta_string(f"!(superpose ({' '.join(selectors)}))")
        if len(results) != len(raw_terms) or "missing-selected-fact" in results:
            raise ValueError(f"No KB fact matches every requested term: {raw_terms}")
        return results

    def all_facts(self) -> List[str]:
        """Return every current KB fact for caller-directed saturation."""
        return self.handler.process_metta_string(
            "!(match &kb "
            f"($type ({self.kb} MAIN Nil) $prf $tv) "
            f"($type ({self.kb} MAIN Nil) $prf $tv))"
        )

    @_timed
    def forward_chain(self, facts: str | Sequence[str], steps: int = 100) -> List[str]:
        """Forward-chain from KB facts and return the derived facts it built on.

        ``steps`` counts row computations. The run works ``facts`` and the
        facts earlier runs queued first, then the agenda earlier runs left;
        with no facts it continues that agenda only, and with ``steps=0`` it
        only queues ``facts``. The returned facts are stored in the KB and are valid input to a
        later run. Use ``select_facts`` to choose initial seeds by surface
        term, or ``all_facts`` to request the full-KB saturation special case.
        """
        facts_expr = facts if isinstance(facts, str) else " ".join(facts)
        return self.handler.process_metta_string(
            f"!(let $changed (forward-chain {steps} {self.kb} ({facts_expr})) "
            "(superpose $changed))"
        )

    def _run_query(
        self, fn: str, source: str, timeout_sec: Optional[float]
    ) -> List[str]:
        if timeout_sec is None or timeout_sec <= 0:
            return self._call(fn, [source])

        main_file = getattr(__main__, "__file__", None)
        if not main_file or main_file == "<stdin>":
            logger.warning(
                "Multiprocessing query timeout is unavailable from %s; running query without a timeout",
                main_file or "interactive __main__",
            )
            return self._call(fn, [source])

        # Use a fresh spawned process so we don't inherit a live SWI/Janus runtime.
        ctx = mp.get_context("spawn")
        parent_conn, child_conn = ctx.Pipe(duplex=False)
        worker = ctx.Process(
            target=_query_worker,
            args=({k: v for k, v in vars(self).items() if k != "handler"}, fn, source, child_conn),
            daemon=True,
        )
        worker.start()
        child_conn.close()
        worker.join(timeout_sec)

        if worker.is_alive():
            worker.terminate()
            worker.join()
            parent_conn.close()
            raise TimeoutError(f"PeTTa query timed out after {timeout_sec} seconds")

        try:
            if not parent_conn.poll():
                raise RuntimeError("PeTTa query worker exited without returning a result")
            status, payload = parent_conn.recv()
            if status == "ok":
                return payload
            err_type, err_msg, err_tb = payload
            raise RuntimeError(f"PeTTa query worker failed [{err_type}]: {err_msg}\n{err_tb}")
        finally:
            parent_conn.close()

    @_timed
    def query(self, atom: str, steps: int = 100, timeout_sec: Optional[float] = 10) -> List[str]:
        self._validate("query", atom, check_query)
        with self._query_metrics(
            kind="query",
            roots=1,
            steps=steps,
            timeout_sec=timeout_sec,
        ):
            return self._run_query("query", f"{steps} {self.kb} {atom}", timeout_sec)

    def query_with_diagnostics(
        self, atom: str, steps: int = 100, *, max_goals: int = 32,
        max_routes: int = 32, max_bytes: int = 32768,
    ) -> dict:
        """Run one query in this live runtime and return its proofs with a
        bounded snapshot of what its search observed (query_diagnostics).

        No subprocess timeout: callers needing a deadline must bound the owning
        process. The query metrics setting is restored afterwards.
        """
        from .query_diagnostics import snapshot

        for name, value, low, high in (
            ("steps", steps, 0, 1000000), ("max_goals", max_goals, 1, 512),
            ("max_routes", max_routes, 0, 512), ("max_bytes", max_bytes, 2048, 1000000),
        ):
            if type(value) is not int or not low <= value <= high:
                raise ValueError(f"{name} must be an integer between {low} and {high}")
        enabled = self._query_metrics_enabled
        self.set_query_metrics(True)
        try:
            proofs = self.query(atom, steps=steps, timeout_sec=0)
            diagnostics = snapshot(self, self.last_query_metrics(), max_goals, max_routes, max_bytes)
            return {"proofs": proofs, "diagnostics": diagnostics}
        finally:
            self.set_query_metrics(enabled)

    def _batch_source(self, queries: List[str], steps: int) -> str:
        """The arguments of a batch query function, each root validated."""
        for atom in queries:
            self._validate("query", atom, check_query)
        return f"{steps} {self.kb} ({' '.join(queries)})"

    @_timed
    def query_many(
        self,
        atoms: Sequence[str],
        steps: int = 100,
        timeout_sec: Optional[float] = 10,
    ) -> List[List[str]]:
        """Answer several roots in one shared backward-search arena.

        ``steps`` is one total expansion budget for the batch. Results stay
        aligned with ``atoms``; an unproved root has an empty result list.
        """
        queries = list(atoms)
        if not queries:
            return []
        source = self._batch_source(queries, steps)
        with self._query_metrics(
            kind="query_many",
            roots=len(queries),
            steps=steps,
            timeout_sec=timeout_sec,
        ):
            return _group_query_many_results(
                self._run_query("query-many", source, timeout_sec),
                len(queries),
            )

    @_timed
    def query_many_refs(
        self,
        atoms: Sequence[str],
        steps: int = 100,
    ) -> List[List[Answer]]:
        """As ``query_many``, but each answer is an ``Answer`` passed as terms,
        and its proof is left as references into the proof store, so no proof
        is expanded or printed; ``expand_proof`` prints one in full.

        It runs in the caller's live process, which holds the proofs the
        references point to; it has no subprocess timeout.
        """
        queries = list(atoms)
        if not queries:
            return []
        source = self._batch_source(queries, steps)
        import janus_swi
        with self._query_metrics(
            kind="query_many",
            roots=len(queries),
            steps=steps,
            timeout_sec=None,
        ):
            rows = janus_swi.query_once(
                "metta_call_terms(Fn, Sources, Results)",
                {"Fn": "query-many-refs", "Sources": [source]},
            )["Results"]
        grouped: List[List[Answer]] = [[] for _ in queries]
        for _, index, (_, proof, statement, tv) in rows:
            grouped[index].append(Answer(proof, statement, tv))
        return grouped

    @_timed
    def expand_proof(self, proof) -> str:
        """The full proof of an ``Answer``'s proof, each shared subproof
        printed once."""
        return self._call("expand-proof", [_metta_text(proof)])[0]

    @_timed
    def query_many_materialization(
        self,
        atoms: Sequence[str],
        steps: int = 100,
    ) -> List[List[str]]:
        """Answer several roots and save their derived proof trees in the KB.

        ``steps`` is one total expansion budget for the batch. Results stay
        aligned with ``atoms``; an unproved root has an empty result list.

        This state-changing operation runs in the current process. Unlike
        ``query_many``, it cannot use the subprocess timeout path because KB
        changes made by a timed worker would not persist in this instance.
        """
        queries = list(atoms)
        if not queries:
            return []
        rows = self._call("query-many-materialize", [self._batch_source(queries, steps)])
        return _group_query_many_results(rows, len(queries))
