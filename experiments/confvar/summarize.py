"""Summarize the committed measurements and candidate widening failures."""
import json
from pathlib import Path

import numpy as np

base = Path(__file__).resolve().parent
rows = [json.loads(line) for line in (base/'measurements.jsonl').read_text().splitlines()]


def confidence(s, v):
    if v == 0:
        return .9999
    if v >= s*(1-s):
        return 0.
    clipped = min(max(s, 1e-6), 1-1e-6)
    n = clipped*(1-clipped)/v-1
    return n/(n+800)


groups = {
    'D0': lambda r:r['case'].startswith('D0/'),
    'D0 within 12 parameters': lambda r:r['case'].startswith('D0/') and r['parameters'] <= 12,
    'D0 broad': lambda r:r['case'].startswith('D0/') and r['broad'],
    'D0 narrow': lambda r:r['case'].startswith('D0/') and not r['broad'],
    'posterior fixtures': lambda r:r['case'].startswith('fixture/'),
    'captured units': lambda r:r['case'].startswith('capture/') and '/unit.' in r['case'],
    'captured benchmarks': lambda r:r['case'].startswith('capture/') and '/benchmark.' in r['case'],
    'near endpoint': lambda r:r['near_endpoint'],
    'many parameters (8+)': lambda r:r['parameters']>=8,
    'analytic': lambda r:r['case'].startswith('analytic/'),
}
summary = {}
for name, pick in groups.items():
    subset = [r for r in rows if pick(r)]
    positive = [r for r in subset if r['reference'] > 0]
    ratios = [r['ratio'] for r in positive]
    summary[name] = dict(
        goals=len(subset), positive_variance=len(positive),
        understated=sum(r['ratio'] < 1-1e-9 for r in positive),
        understated_with_reference_gap_le_1pct=sum(r['ratio'] < 1-1e-9 and
                                                  r['refinement_relative_gap'] <= .01 for r in positive),
        understated_by_more_than_1pct=sum(r['ratio'] < .99 for r in positive),
        overconfident_after_conversion=sum(confidence(r['strength'],r['first_order']) >
                                         confidence(r['strength'],r['reference'])+1e-12 for r in positive),
        ratio_quantiles=dict(zip(['min','p05','median','p95','max'],
                                 map(float,np.quantile(ratios,[0,.05,.5,.95,1])))) if ratios else {},
        reference_gap_over_1pct=sum(r['refinement_relative_gap'] > .01 for r in subset),
        worst=sorted(positive,key=lambda r:r['ratio'])[:5])

widenings = {
    '2x': lambda r:2*r['first_order'],
    '64x': lambda r:64*r['first_order'],
    'broad 64x, narrow 1.05x': lambda r:(64 if r['broad'] else 1.05)*r['first_order'],
    'broad Bernoulli bound, narrow 1.05x': lambda r:r['strength']*(1-r['strength']) if r['broad'] else 1.05*r['first_order'],
}
summary['widenings'] = {}
for name, widen in widenings.items():
    failed = [r for r in rows if r['reference'] > 0 and widen(r) < (1-1e-9)*r['reference']]
    summary['widenings'][name] = dict(understated=len(failed),
                                    analytic_failures=[r['case'] for r in failed if r['case'].startswith('analytic/')])
(base/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
for name, value in summary.items():
    if name != 'widenings':
        print(name,{k:v for k,v in value.items() if k!='worst'})
print('widenings',summary['widenings'])
