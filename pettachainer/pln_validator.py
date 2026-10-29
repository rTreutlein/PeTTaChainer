"""Shared PLN syntax validation helpers for evaluated PLN expressions.

The checks are syntactic, so they read the text in Python: a query costs no
round trip through the MeTTa runtime to be validated.
"""

from .metta_syntax import parse_source

# Truth-value heads and their accepted argument counts; a CTV holds two STVs.
# PTV and FTV are an STV's two kinds written explicitly (LANGUAGE_SPEC).
TV_ARITIES = {
    "STV": {2},
    "PTV": {2},
    "FTV": {2},
    "CTV": {2},
    "NatDist": {1},
    "FloatDist": {1},
    "ParticleDist": {1, 2},
    "PointMass": {1},
    "ParticleFromNormal": {2},
    "ParticleFromPairs": {1},
}


def _annotation(text: str):
    """The parts ``(proof statement tv)`` of ``(: proof statement tv)``, or None."""
    forms = parse_source(text.strip())
    if not forms or len(forms) != 1:
        return None
    form = forms[0]
    if not isinstance(form, list) or len(form) != 4 or form[0] != ":":
        return None
    return form[1:]


def _is_var(term) -> bool:
    return isinstance(term, str) and term.startswith("$")


def _tv_supported(tv) -> bool:
    if not isinstance(tv, list) or not tv or not isinstance(tv[0], str):
        return False
    if len(tv) - 1 not in TV_ARITIES.get(tv[0], ()):
        return False
    if tv[0] == "CTV":
        return all(_is_var(part) or (isinstance(part, list) and len(part) == 3 and part[0] == "STV")
                   for part in tv[1:])
    return True


def check_stmt(text: str) -> float:
    """Return 1.0 for valid evaluated statement forms, else 0.0."""
    parts = _annotation(text)
    if parts is None:
        return 0.0
    proof, _statement, tv = parts
    return 1.0 if not _is_var(proof) and not _is_var(tv) and _tv_supported(tv) else 0.0


def check_query(text: str) -> float:
    """Return 1.0 for valid evaluated query forms, else 0.0."""
    parts = _annotation(text)
    return 1.0 if parts is not None and _is_var(parts[0]) else 0.0
