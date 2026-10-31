"""Replay every round-1 model through the replacement production kernel."""
import math
import measure
import round2
from tests.test_event_node import moments


def model(label, variables, terms, goals, truth=None, production=None):
    rows = round2.model(label, variables, terms, goals, truth, production)
    if not rows:
        return []
    answers = moments(variables, terms, len(goals))
    assert answers != 'inconsistent', label
    for row, (s, v, kind) in zip(rows, answers):
        assert math.isclose(s, row['strength'], rel_tol=1e-14, abs_tol=1e-15), (label, s, row['strength'])
        row.update(runtime_strength=s, runtime_variance=v, runtime_kind=kind,
                   runtime_ratio=v/row['reference'] if row['reference'] > 0 else None)
        # The independent float pair sums can retain absolute roundoff on
        # algebraically constant goals. Production uses exact rational sums.
        assert math.isclose(v, row['candidate_variance'], rel_tol=1e-6, abs_tol=1e-16), (label, v, row['candidate_variance'])
        if row['reference'] > 1e-28:
            assert v >= row['reference']*(1-1e-9), (label, v, row['reference'])
    return rows


if __name__ == '__main__':
    measure.model = model
    measure.main()
