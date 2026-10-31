"""Summarize round 2 without discarding unresolved numerical references."""
import json
from pathlib import Path
import numpy as np

base = Path(__file__).resolve().parent
rows = list(map(json.loads, (base/'round2-measurements.jsonl').read_text().splitlines()))


def confidence(s, v):
    if v == 0:
        return .9999
    if v >= s*(1-s):
        return 0.
    p = min(1-1e-6, max(1e-6, s))
    n = p*(1-p)/v-1
    return n/(n+800)


groups = {
    'D0': lambda r: r['case'].startswith('D0/'),
    'fixtures': lambda r: r['case'].startswith('fixture/'),
    'units': lambda r: '/unit.' in r['case'],
    'benchmarks': lambda r: '/benchmark.' in r['case'],
    'analytic': lambda r: r['case'].startswith('analytic/'),
}
summary = {}
for label, pick in groups.items():
    subset = [r for r in rows if pick(r)]
    # Numerical integrals of a constant can retain squared roundoff (~1e-32).
    # Keep these rows and expose the count; do not call them positive references.
    positive = [r for r in subset if r['reference'] > 1e-28]
    ratios = [r['candidate_ratio'] for r in positive]
    summary[label] = dict(
        goals=len(subset), constant_z=sum(r['constant_z'] for r in subset),
        varying_z=sum(not r['constant_z'] for r in subset),
        positive_references=len(positive),
        sub_roundoff_references=sum(0 < r['reference'] <= 1e-28 for r in subset),
        understated=sum(r['candidate_ratio'] < 1-1e-9 for r in positive),
        overconfident=sum(confidence(r['strength'], r['candidate_variance']) >
                          confidence(r['strength'], r['reference'])+1e-12 for r in subset),
        zero_confidence=sum(confidence(r['strength'], r['candidate_variance']) == 0 for r in subset),
        reference_gap_over_1pct=sum(r['refinement_relative_gap'] > .01 for r in subset),
        ratio_quantiles=dict(zip(('min', 'p05', 'median', 'p95', 'max'),
                                 map(float, np.quantile(ratios, [0, .05, .5, .95, 1])))) if ratios else {})
(base/'round2-summary.json').write_text(json.dumps(summary, indent=2)+'\n')
print(json.dumps(summary, indent=2))
