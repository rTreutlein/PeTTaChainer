"""Shared PLN syntax validation helpers for NL2PLN-style commands."""

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
        f"(if (= {tv_var} (PointMass $123x)) 1.0 "
        f"(if (= {tv_var} (ParticleFromNormal $123mu $123sigma)) 1.0 "
        f"(if (= {tv_var} (ParticleFromPairs $123pairs)) 1.0 0.0)))))))"
    )


def _split_top_level(expr: str) -> list[str]:
    tokens: list[str] = []
    token_start = None
    depth = 0

    for i, ch in enumerate(expr):
        if ch == "(":
            if token_start is None:
                token_start = i
            depth += 1
            continue
        if ch == ")":
            depth -= 1
            if depth < 0:
                return []
            continue
        if ch.isspace() and depth == 0:
            if token_start is not None:
                tokens.append(expr[token_start:i])
                token_start = None
            continue
        if token_start is None:
            token_start = i

    if depth != 0:
        return []
    if token_start is not None:
        tokens.append(expr[token_start:])
    return tokens


def _unwrap_command(expr: str) -> str:
    stripped = expr.strip()
    if not stripped.startswith("!(") or not stripped.endswith(")"):
        return stripped

    body = stripped[2:-1].strip()
    tokens = _split_top_level(body)
    if len(tokens) == 3 and tokens[0] == "compileadd":
        return tokens[2]
    if len(tokens) == 4 and tokens[0] == "query":
        return tokens[3]
    return stripped


def check_stmt(text: str) -> float:
    """Return 1.0 for valid statement-like forms, else 0.0.

    Accepted wrappers:
    - (: ...)
    - !(compileadd kb (: ...))
    - !(query <steps> kb (: ...))
    """

    expr = _unwrap_command(text)
    tv_check = _tv_supported_expr()
    code = (
        f"!(if (= {expr} (: $123prf $123stmt $123tv)) "
        f"(if (== (get-metatype $123prf) Variable) 0.0 "
        f"(if (== (get-metatype $123tv) Variable) 0.0 {tv_check})) "
        f"0.0)"
    )
    return _run_check(code)


def check_query(text: str) -> float:
    """Return 1.0 for valid query-like forms, else 0.0.

    Accepted wrappers:
    - (: ...)
    - !(compileadd kb (: ...))
    - !(query <steps> kb (: ...))
    """

    expr = _unwrap_command(text)
    code = (
        f"!(if (= {expr} (: $123prf $123stmt $123tv)) "
        f"(if (== (get-metatype $123prf) Variable) 1.0 0.0) "
        f"0.0)"
    )
    return _run_check(code)
