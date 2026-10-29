"""Inert MeTTa terms shared by source validation, diagnostics and proof output.

Parsing keeps tokens as strings, including quotes; it never evaluates source.
Rendering also accepts native numbers returned by the runtime.
"""

import re

_TOKEN = re.compile(r'\s+|;[^\n]*|"(?:\\.|[^"\\])*"|\(|\)|[^\s()";]+')


def parse_source(text: str):
    """The top-level expressions of MeTTa source as nested lists of tokens,
    or None when it does not read as balanced expressions."""
    stack = [[]]
    position = 0
    for match in _TOKEN.finditer(text):
        if match.start() != position:
            return None
        position = match.end()
        token = match.group()
        if token == "(":
            stack.append([])
        elif token == ")":
            if len(stack) == 1:
                return None
            item = stack.pop()
            stack[-1].append(item)
        elif not token.isspace() and not token.startswith(";"):
            stack[-1].append(token)
    return stack[0] if len(stack) == 1 and position == len(text) else None


def parse_term(text: str):
    """One complete term; reject malformed source and multiple terms."""
    forms = parse_source(text)
    if forms is None or len(forms) != 1:
        raise RuntimeError("Malformed MeTTa term")
    return forms[0]


def render(term) -> str:
    """MeTTa source for a parsed term or a native ``Answer`` term."""
    if isinstance(term, list):
        return "(" + " ".join(render(item) for item in term) + ")"
    if isinstance(term, float):
        mantissa, exponent, power = repr(term).partition("e")
        return mantissa + (".0" if exponent and "." not in mantissa else "") + exponent + power
    return str(term)
