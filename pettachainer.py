import logging
import os
import threading
import uuid
from typing import List

from petta import PeTTa

logging.basicConfig(
    format="%(asctime)s [%(levelname)s] %(message)s",
    level=logging.INFO
)
logger = logging.getLogger(__name__)

LOADEDLIB = False
LOADED_LOCK = threading.Lock()

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

    def query(self, atom: str) -> List[str]:
        atoms = self.handler.process_metta_string(f"!(query (S (S Z)) {self.kb} {atom})")
        return atoms

if __name__ == '__main__':
    handler = PeTTaChainer()

    data = [
        "(: st1 (Implication (type $x whale) (And (type $x mammal) (attribute $x lives_in_ocean))) (STV 1.0 1.0))",
        "(: st2 (Implication (And (type $x animal) (attribute $x lives_in_ocean)) (type $x marine_animal)) (STV 1.0 1.0))",
        "(: st3 (Implication (And (type $x marine_animal) (type $x mammal)) (attribute $x exposed_to_pollutant_P)) (STV 1.0 1.0))",
        "(: st4 (Implication (attribute $x exposed_to_pollutant_P) (attribute $x increased_risk_disease_Z)) (STV 1.0 1.0))",
        "(: st5 (Implication (type $x mammal) (type $x animal)) (STV 1.0 1.0))"]

    query = "(: $prf (Implication (type $x whale) (attribute $x lives_in_ocean)) $tv)"

    data1 = ["(: a_b (Implication A B) (STV 1.0 1.0))", "(: a A (STV 1.0 1.0))"]
    query1 = "(: $prf B $tv)"

    data2 = ["(: prf (Implication (And A B) C) (STV 1.0 1.0))"]
    query2 = "(: $prf (Implication (And A B) C) $tv)"

    statements=['(: fact1 (Reaches RiverA Bay-1) (STV 1.0 1.0))',
                '(: fact2 (Implication (Reaches $r $b) (HasRiverRunoff $b)) (STV 1.0 1.0))',
                '(: fact3 (Implication (HasRiverRunoff $b) (And (HighLevelPollutantP $b) (Implication (LivesIn $a $b) (ExposedTo $a PollutantP)))) (STV 1.0 1.0))',
                '(: fact4 (Implication (And (MarineAnimal $a) (ExposedTo $a PollutantP)) (IncreasedRisk $a DiseaseZ)) (STV 1.0 1.0))',
                '(: fact5 (Implication (Dolphin $x) (And (MarineMammal $x) (LivesIn $x CoastalBays))) (STV 1.0  1.0))',
                '(: fact6 (LivesIn Dolphin Bay-1) (STV 1.0 1.0))',
                '(: fact7 (Implication (Mollusk $x) (Contains $x SubstanceS)) (STV 1.0 1.0))',
                '(: fact8 (Implication (Eats $a SubstanceS) (EliminatesRisk $a DiseaseZ)) (STV 1.0 1.0))',
                '(: fact9 (Implication (And (Dolphin $d) (LivesIn $d Bay-1)) (PredatorOf $d Mollusk)) (STV 1.0 1.0))',
                '(: fact10 (Implication (PredatorOf $p $y) (Eats $p $y)) (STV 1.0 1.0))',
                '(: fact11 (Implication (Mammal $x) (Animal $x)) (STV 1.0 1.0))',
                '(: fact12 (Implication (And (MarineMammal $x) (Animal $x)) (MarineAnimal $x)) (STV 1.0 1.0))']
    queries='(: $prf (LikelierThan (And (IncreasedRisk $d DiseaseZ) (Dolphin $d) (LivesIn $d Bay-1)) (And (IncreasedRisk $t DiseaseZ) (Tuna $t) (LivesIn $t Bay-1))) $tv)'


    data4=['(: st2 (Implication (attribute meeting_1 happening) (agrees everyone)) (STV 1.0 1.0))']
    query4='(: $prf (Implication (attribute meeting_1 happening) (agrees $x)) $tv)'

    for elem in data4:
        print(f"Adding {elem}")
        print(handler.add_atom(elem))

    print(handler.query(query4))
