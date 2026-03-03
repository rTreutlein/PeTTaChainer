"""Shared PLN syntax validation helpers for evaluated PLN expressions."""

from petta import PeTTa

TV_PATTERNS = (
    "STV $123s $123c",
    "NatDist $123pairs",
    "FloatDist $123pairs",
    "ParticleDist $123ref",
    "ParticleDist $123ref $123scale",
    "PointMass $123x",
    "ParticleFromNormal $123mu $123sigma",
    "ParticleFromPairs $123pairs",
)


def _run_check(code: str) -> float:
    try:
        return float(PeTTa().process_metta_string(code)[0])
    except Exception:
        return 0.0


def _tv_supported_expr(tv_var: str = "$123tv") -> str:
    expr = "0.0"
    for pattern in reversed(TV_PATTERNS):
        expr = f"(if (= {tv_var} ({pattern})) 1.0 {expr})"
    return expr


def _check_shape(expr: str, body: str) -> float:
    return _run_check(f"!(if (= {expr} (: $123prf $123stmt $123tv)) {body} 0.0)")


def check_stmt(text: str) -> float:
    """Return 1.0 for valid evaluated statement forms, else 0.0."""

    return _check_shape(
        text.strip(),
        "(if (== (get-metatype $123prf) Variable) 0.0 "
        f"(if (== (get-metatype $123tv) Variable) 0.0 {_tv_supported_expr()}))",
    )


def check_query(text: str) -> float:
    """Return 1.0 for valid evaluated query forms, else 0.0."""

    return _check_shape(
        text.strip(),
        "(if (== (get-metatype $123prf) Variable) 1.0 0.0)",
    )
