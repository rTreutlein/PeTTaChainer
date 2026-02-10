import logging
import multiprocessing as mp
import os
import threading
import traceback
import uuid
from typing import List, Optional

from petta import PeTTa

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

LOADEDLIB = False
LOADED_LOCK = threading.Lock()


def _query_worker(handler: PeTTa, kb: str, depth: int, atom: str, conn):
    try:
        atoms = handler.process_metta_string(f"!(query (fromNumber {depth}) {kb} {atom})")
        conn.send(("ok", atoms))
    except Exception as exc:  # pragma: no cover
        conn.send(("err", (exc.__class__.__name__, str(exc), traceback.format_exc())))
    finally:
        conn.close()

class PeTTaChainer:
    def __init__(self):
        global LOADEDLIB
        self.handler = PeTTa()
        
        self.kb = "kb" + uuid.uuid4().hex
        self._base_dir = os.path.dirname(__file__)

        if not LOADEDLIB:
            with LOADED_LOCK:
                if not LOADEDLIB:
                    metta_path = os.path.join(self._base_dir, "metta", "petta_chainer.metta")
                    logger.info("Loading MeTTa library from %s", metta_path)
                    self.handler.load_metta_file(metta_path)
                    LOADEDLIB = True

    def add_atom(self, atom: str) -> str:
        return self.handler.process_metta_string(f"!(compileadd {self.kb} {atom})")

    def query(self, atom: str, depth: int = 10, timeout_sec: Optional[float] = 10) -> List[str]:
        if timeout_sec is None or timeout_sec <= 0:
            return self.handler.process_metta_string(f"!(query (fromNumber {depth}) {self.kb} {atom})")

        # Use a forked process so timeout can actually stop CPU-bound query work.
        ctx = mp.get_context("fork")
        parent_conn, child_conn = ctx.Pipe(duplex=False)
        worker = ctx.Process(
            target=_query_worker,
            args=(self.handler, self.kb, depth, atom, child_conn),
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

        if parent_conn.poll():
            status, payload = parent_conn.recv()
            parent_conn.close()
            if status == "ok":
                return payload
            err_type, err_msg, err_tb = payload
            raise RuntimeError(f"PeTTa query worker failed [{err_type}]: {err_msg}\n{err_tb}")

        parent_conn.close()
        raise RuntimeError("PeTTa query worker exited without returning a result")

if __name__ == '__main__':
    handler = PeTTaChainer()

    data = [
        "(: fact_a (Count A 1) (STV 1.0 1.0))",
        "(: fact_b (Count B 2) (STV 1.0 1.0))",
        "(: sum_rule (Implication (Premises (Count A $a) (Count B $b) (Compute + ($a $b) -> $c)) (Conclusions (Count C $c))) (STV 1.0 1.0))",
    ]
    queries = ["(: $prf (Count C $c) $tv)"]


    data2 = ['(: s1 (Cardinality (CatsIn Park) 3) (STV 1 0.9))',
             '(: s2 (Implication (Premises (And (Cat $x) (In $x Park))) (Conclusions (Cute $x))) (STV 1 0.8))',
             '(: r_allCatsCute (Implication (Premises (And (Implication (Premises (Cat $x)) (Conclusions (In $x Park))) (Implication (Premises (And (Cat $x) (In $x Park))) (Conclusions (Cute $x))))) (Conclusions (Implication (Premises (Cat $x)) (Conclusions (Cute $x))))) (STV 0.6 0.4))', '(: r_cuteCatsAtLeast2 (Implication (Premises (Cardinality (CatsIn Park) $n) (Compute <= (2 $n) -> True)) (Conclusions (AtLeast2 (CuteCatsIn Park)))) (STV 0.9 0.7))']
    queries2=['(: $prf (Implication (Premises (Cat $x)) (Conclusions (Cute $x))) $tv)',
              '(: $prf (And (Cat $x) (In $x Park) (Cute $x)) $tv)',
              '(: $prf (AtLeast2 (CuteCatsIn Park)) $tv)']

    for elem in data:
        print(f"Adding {elem}")
        print(handler.add_atom(elem))

    for q in queries:
        print("Query result:")
        print(handler.query(q))
