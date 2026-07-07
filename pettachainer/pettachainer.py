import logging
import multiprocessing as mp
from pathlib import Path
import sys
import threading
import traceback
import uuid
from typing import List, Optional, Sequence, Tuple
import __main__

from petta import PeTTa

if __package__:
    from .pln_validator import check_query, check_stmt
else:  # Allow direct script execution: python pettachainer/pettachainer.py
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from pettachainer.pln_validator import check_query, check_stmt

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

LOADEDLIB = False
LOADED_LOCK = threading.Lock()


def get_language_spec(llm_focused: bool = True) -> str:
    return (Path(__file__).resolve().parent / ("LLM_RULE_SPEC.md" if llm_focused else "LANGUAGE_SPEC.md")).read_text(encoding="utf-8")


def _query_worker(
    added_atoms: List[Tuple[str, bool]],
    kb: str,
    steps: int,
    atom: str,
    logic_config_path: Optional[str],
    conn,
):
    try:
        handler = PeTTaChainer(logic_config=logic_config_path)
        handler.kb = kb
        if added_atoms:
            handler.add_atoms_no_check(added_atoms)
        atoms = handler.handler.process_metta_string(f"!(query {steps} {kb} {atom})")
        conn.send(("ok", atoms))
    except Exception as exc:  # pragma: no cover
        conn.send(("err", (exc.__class__.__name__, str(exc), traceback.format_exc())))
    finally:
        conn.close()


def _as_list(value) -> List[str]:
    return [value] if isinstance(value, str) else value


class PeTTaChainer:
    def __init__(self, logic_config: Optional[str] = None):
        global LOADEDLIB
        self.handler = PeTTa()
        self.kb = f"kb{uuid.uuid4().hex}"
        self._added_atoms: List[Tuple[str, bool]] = []
        self._pattern_mining_on_add = False
        self._logic_config_path: Optional[Path] = None
        base_dir = Path(__file__).resolve().parent

        if not LOADEDLIB:
            with LOADED_LOCK:
                if not LOADEDLIB:
                    metta_path = base_dir / "metta" / "petta_chainer.metta"
                    logger.info("Loading MeTTa library from %s", metta_path)
                    self.handler.load_metta_file(str(metta_path))
                    LOADEDLIB = True

        self.load_logic_config(logic_config or "pln")

    def load_logic_config(self, logic_config: str) -> str:
        path = Path(logic_config)
        if not path.suffix and len(path.parts) == 1:
            path = Path(__file__).resolve().parent / "metta" / "logic_configs" / f"{logic_config}.metta"
        else:
            path = path.expanduser()
            if not path.is_absolute():
                path = path.resolve()
        self._logic_config_path = path
        return self.handler.load_metta_file(str(path))

    def _evaluate(self, atom: str) -> str:
        result = self.handler.process_metta_string(f"!(eval {atom})")
        if isinstance(result, list):
            if not result:
                raise ValueError("PeTTa returned no results")
            result = result[0]
        return str(result).strip()

    @staticmethod
    def _validate(kind: str, raw_atom: str, evaluated_atom: str, checker) -> None:
        if checker(evaluated_atom) == 0.0:
            raise ValueError(
                f"Invalid evaluated PLN {kind}. input={raw_atom} evaluated={evaluated_atom}"
            )

    def set_backward_premise_prefilter(self, enabled: bool) -> None:
        """Toggle the backward chainer's premise pre-filter (default off).

        When enabled, candidate rules whose ground premises provably cannot be
        satisfied (no matching fact and no rule concluding that head) are
        skipped before any search state is created. Semantics-preserving:
        results are unchanged, only unprovable rule expansions are avoided.
        Performance-only, so it is intentionally not replayed by the
        multiprocessing query-timeout worker.
        """
        value = "true" if enabled else "false"
        self.handler.process_metta_string(f"!(set-backward-premise-prefilter {value})")

    def set_pattern_mining_on_add(self, enabled: bool) -> None:
        value = "true" if enabled else "false"
        self.handler.process_metta_string(f"!(set-pattern-mining-on-add {self.kb} {value})")
        self._pattern_mining_on_add = enabled

    def enable_pattern_mining_on_add(self) -> None:
        self.set_pattern_mining_on_add(True)

    def disable_pattern_mining_on_add(self) -> None:
        self.set_pattern_mining_on_add(False)

    def materialize_mined_implications(self) -> str:
        return self.handler.process_metta_string(f"!(materialize-mined-implications {self.kb})")

    def add_atom(self, atom: str, mine_patterns: Optional[bool] = None) -> str:
        evaluated_atom = self._evaluate(atom)
        self._validate("statement", atom, evaluated_atom, check_stmt)
        effective_mining = self._pattern_mining_on_add if mine_patterns is None else mine_patterns
        compile_fun = "compileadd-mine" if effective_mining else "compileadd"
        result = self.handler.process_metta_string(f"!({compile_fun} {self.kb} {evaluated_atom})")
        self._added_atoms.append((evaluated_atom, effective_mining))
        return result

    def remove_statement(self, atom_name: str) -> str:
        """Remove a previously compiled statement by its name.

        Retracts the kb facts and rules that compileadd produced for
        ``(: <atom_name> ...)``, including their index rows and cached
        expected scores. Statements whose compiled rules carry no
        extractable name (e.g. negated outputs) are not covered.
        """
        result = self.handler.process_metta_string(f"!(remove-compiled-statement {atom_name})")
        prefix = f"(: {atom_name} "
        self._added_atoms = [
            (atom, mined) for atom, mined in self._added_atoms
            if not atom.strip().startswith(prefix)
        ]
        return result

    def add_atoms_no_check(self, atoms: List[str] | List[Tuple[str, bool]], mine_patterns: Optional[bool] = None) -> str:
        if atoms and isinstance(atoms[0], tuple):
            entries = atoms
        else:
            effective_mining = self._pattern_mining_on_add if mine_patterns is None else mine_patterns
            entries = [(atom, effective_mining) for atom in atoms]
        adds = [f"({'compileadd-mine' if use_mining else 'compileadd'} {self.kb} {atom})" for atom, use_mining in entries]
        result = self.handler.process_metta_string(
            f"!(superpose ({' '.join(adds)}))"
        )
        self._added_atoms.extend(entries)
        return result

    evaluate_statement = _evaluate
    evaluate_query = _evaluate

    def print_kb(self):
        for atom in _as_list(self.handler.process_metta_string(f"!(match &kb $a (pretty $a))")):
            print(atom)

    def _select_forward_fact(self, term: str) -> Optional[str]:
        evaluated_term = self._evaluate(term)
        facts = _as_list(
            self.handler.process_metta_string(f"!(forward-select-fact {self.kb} {evaluated_term})")
        )
        if not facts:
            return None
        fact = str(facts[0]).strip()
        return None if fact == "()" else fact

    def forward_chain_from_facts(self, terms: Sequence[str], steps: int = 100):
        selected_facts: List[str] = []
        for term in terms:
            fact = self._select_forward_fact(term)
            if fact is None:
                return ["false"]
            selected_facts.append(fact)
        if not selected_facts:
            return ["false"]
        facts_expr = f"({' '.join(selected_facts)})"
        return self.handler.process_metta_string(
            f"!(forward-chain-from-facts {steps} {self.kb} {facts_expr})"
        )

    def forward_chain(self, steps: int = 100, term: Optional[str | Sequence[str]] = None):
        if term is None:
            return self.handler.process_metta_string(f"!(forward-chain {steps} {self.kb})")
        if not isinstance(term, str):
            return self.forward_chain_from_facts(term, steps=steps)
        evaluated_term = self._evaluate(term)
        return self.handler.process_metta_string(
            f"!(forward-chain-from {steps} {self.kb} {evaluated_term})"
        )

    def query(self, atom: str, steps: int = 100, timeout_sec: Optional[float] = 10) -> List[str]:
        evaluated_query = self._evaluate(atom)
        self._validate("query", atom, evaluated_query, check_query)

        if timeout_sec is None or timeout_sec <= 0:
            return _as_list(
                self.handler.process_metta_string(f"!(query {steps} {self.kb} {evaluated_query})")
            )

        main_file = getattr(__main__, "__file__", None)
        if not main_file or main_file == "<stdin>":
            logger.warning(
                "Multiprocessing query timeout is unavailable from %s; running query without a timeout",
                main_file or "interactive __main__",
            )
            return _as_list(
                self.handler.process_metta_string(f"!(query {steps} {self.kb} {evaluated_query})")
            )

        # Use a fresh spawned process so we don't inherit a live SWI/Janus runtime.
        ctx = mp.get_context("spawn")
        parent_conn, child_conn = ctx.Pipe(duplex=False)
        worker = ctx.Process(
            target=_query_worker,
            args=(
                self._added_atoms,
                self.kb,
                steps,
                evaluated_query,
                str(self._logic_config_path) if self._logic_config_path else None,
                child_conn,
            ),
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

    language_spec = staticmethod(get_language_spec)


if __name__ == "__main__":
    handler = PeTTaChainer()
    atom = "(: fact_a (Count A 1) (STV 1.0 1.0))"
    print(f"Adding {atom}")
    print(handler.add_atom(atom))
    print("Query result:")
    print(handler.query("(: $prf (Count A 1) $tv)", timeout_sec=0))
