"""Exact marginals of ProbLog programs, run with ProbLog's own interpreter.

Reads a JSON list of programs on stdin and writes, per program, a JSON object
``{"marginals": {query: p}}`` or ``{"error": message}``. It imports nothing
from PeTTaChainer: ProbLog lives in another virtual environment."""

import json
import sys

from problog import get_evaluatable
from problog.engine import DefaultEngine, ground
from problog.program import PrologString


def marginals(text):
    formula = ground(PrologString(text), unknown=DefaultEngine.UNKNOWN_FAIL)
    result = get_evaluatable("ddnnf").create_from(formula).evaluate()
    return {str(term): float(p) for term, p in result.items()}


out = []
for text in json.load(sys.stdin):
    try:
        out.append({"marginals": marginals(text)})
    except Exception as error:  # inconsistent evidence, a malformed program
        out.append({"error": f"{type(error).__name__}: {str(error)[:300]}"})
json.dump(out, sys.stdout)
