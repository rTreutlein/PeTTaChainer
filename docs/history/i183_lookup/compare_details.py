"""Extract every changed belief and calibration summary from standard stores.

No benchmarks are run here. Inputs are compare.json files produced by compare.sh.
The public confidence decoder uses each capture's evidence K and clipped strength.
"""
import argparse
import base64
import gzip
import json
import math
from pathlib import Path
import statistics

BENCH=Path('/nexus/Dev/OpenCog/bench/results')


def capture(key):
    path=BENCH/'store'/key[:2]/(key+'.jsonl')
    for text in reversed(path.read_text().splitlines()):
        r=json.loads(text)
        if r.get('exit')==0 and 'calibration' in r:
            data=json.loads(gzip.decompress(base64.b64decode(r['calibration']['data'])))
            out={}
            for block in data['rounds']:
                for index,(statement,tv,reference,outcome) in enumerate(block['rows']):
                    out[(block['round'],json.dumps(statement,separators=(',',':')))]=dict(
                        tv=tv,reference=reference,outcome=outcome,k=block['k'])
            return out
    return {}


def score(row):
    if not row or row['tv'] is None or row['reference'] is None:return None
    s,c=row['tv'];ref=row['reference'];x=min(1-1e-6,max(1e-6,s))
    v=0 if c>=1 else x*(1-x)/(row['k']*c/(1-c)+1)
    z=abs(s-ref)/math.sqrt(v) if v>0 else 0 if s==ref else math.inf
    return dict(variance=v,z=z,error=abs(s-ref),brier=(s-row['outcome'])**2 if row['outcome'] is not None else None)


def stats(rows):
    scores=[s for row in rows.values() if (s:=score(row)) is not None]
    if not scores:return {}
    zs=sorted(s['z'] for s in scores)
    return dict(n=len(scores),mae=statistics.mean(s['error'] for s in scores),
        brier=statistics.mean(s['brier'] for s in scores if s['brier'] is not None) if any(s['brier'] is not None for s in scores) else None,outside_2sd=sum(z>2 for z in zs),
        outside_2sd_fraction=sum(z>2 for z in zs)/len(zs),z_median=statistics.median(zs),
        z_p95=zs[min(len(zs)-1,int(.95*len(zs)))],z_max=zs[-1])


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('comparisons',nargs='+')
    ap.add_argument('--out',required=True);a=ap.parse_args();summary=[];moved=[];seen=set()
    for file in a.comparisons:
        data=json.loads(Path(file).read_text())
        if 'curves' in data:
            records=[]
            for name,curve in data['curves'].items():
                base_points={p['x']:p for p in curve['base']};candidate_points={p['x']:p for p in curve['candidate']}
                for x in sorted(base_points.keys()&candidate_points.keys()):
                    records.append(dict(suite='curves',case=f'{name} budget {x}',keys=dict(base=base_points[x]['key'],candidate=candidate_points[x]['key']),
                        base=dict(metrics={k:base_points[x][k] for k in ('error','seconds')}),
                        candidate=dict(metrics={k:candidate_points[x][k] for k in ('error','seconds')})))
            data['records']=records;data['profile']='curves'
        base_label=data['base'][0] if isinstance(data['base'],list) else data['base']
        candidate_label=data['candidate'][0] if isinstance(data['candidate'],list) else data['candidate']
        for r in data['records']:
            keys=r['keys'];base=keys.get('base');cand=keys.get('candidate')
            if not base or not cand or (base,cand) in seen:continue
            seen.add((base,cand));bs,cs=capture(base),capture(cand)
            changes=0
            for key in sorted(bs.keys()|cs.keys()):
                b,c=bs.get(key),cs.get(key)
                if b and c and b['tv']==c['tv']:continue
                changes+=1
                moved.append(dict(base_label=base_label,candidate_label=candidate_label,profile=data['profile'],suite=r['suite'],case=r['case'],round=key[0],statement=key[1],
                                  base=b,candidate=c,base_score=score(b),candidate_score=score(c)))
            summary.append(dict(suite=r['suite'],case=r['case'],source=str(file),base_key=base,candidate_key=cand,
                base=stats(bs),candidate=stats(cs),changed_values=changes,
                metrics_base=r.get('base',{}).get('metrics'),metrics_candidate=r.get('candidate',{}).get('metrics')))
    target=Path(a.out);target.mkdir(exist_ok=True,parents=True)
    (target/'calibration.json').write_text(json.dumps(summary,indent=2)+'\n')
    (target/'moved-values.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in moved))
    print(len(summary),'cases;',len(moved),'changed value rows')
    for r in summary:
        if r['changed_values']:
            print(r['suite'],r['case'],r['changed_values'],r['base'],r['candidate'])


if __name__=='__main__':main()
