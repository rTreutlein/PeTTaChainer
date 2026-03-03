"""Shared PLN syntax validation helpers for evaluated PLN expressions."""

from petta import PeTTa


def _run_check(code: str) -> float:
    try:
        result = PeTTa().process_metta_string(code)[0]
        return float(result)
    except Exception:
        return 0.0


def _tv_supported_expr(tv_var: str = "$123tv") -> str:
    return (
        f"(if (= {tv_var} (STV $123s $123c)) 1.0 "
        f"(if (= {tv_var} (NatDist $123pairs)) 1.0 "
        f"(if (= {tv_var} (FloatDist $123pairs)) 1.0 "
        f"(if (= {tv_var} (ParticleDist $123ref)) 1.0 "
        f"(if (= {tv_var} (ParticleDist $123ref $123scale)) 1.0 "
        f"(if (= {tv_var} (PointMass $123x)) 1.0 "
        f"(if (= {tv_var} (ParticleFromNormal $123mu $123sigma)) 1.0 "
        f"(if (= {tv_var} (ParticleFromPairs $123pairs)) 1.0 0.0))))))))"
    )


def check_stmt(text: str) -> float:
    """Return 1.0 for valid evaluated statement forms, else 0.0."""

    expr = text.strip()
    tv_check = _tv_supported_expr()
    code = (
        f"!(if (= {expr} (: $123prf $123stmt $123tv)) "
        f"(if (== (get-metatype $123prf) Variable) 0.0 "
        f"(if (== (get-metatype $123tv) Variable) 0.0 {tv_check})) "
        f"0.0)"
    )
    return _run_check(code)


def check_query(text: str) -> float:
    """Return 1.0 for valid evaluated query forms, else 0.0."""

    expr = text.strip()
    code = (
        f"!(if (= {expr} (: $123prf $123stmt $123tv)) "
        f"(if (== (get-metatype $123prf) Variable) 1.0 0.0) "
        f"0.0)"
    )
    return _run_check(code)
