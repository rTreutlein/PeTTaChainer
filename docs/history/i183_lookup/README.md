Current hand-back: [November 10 review fix](../ISSUE183_LOOKUP_REVIEW_REPORT.md), with final probes and gates in [review/](review/). The original files below preserve the first-round measurements.

# #183 lookup measurements

`cases-before.jsonl` and `cases-after.jsonl` contain 21 fresh-engine queries,
with every input and expanded answer. `candidate-i.jsonl` measures the
no-additional-information admission candidate on 20 of those queries.
`ke-before.jsonl` and `ke-after.jsonl` contain 46 KE configurations, cold and
warm (92 reads); `ke-moved-values.jsonl` contains all 64 changed TVs and proofs.
No answer was lost in those paired KE reads.

Run the probes from the repository root through `bench/capped`, with DISPLAY
unset, `ulimit -v 16000000`, stdin redirected and an external timeout, as in
`docs/agent_workflow.md`. They use the private pinned `.venv/bin/python`.

- Current cases: `docs/history/i183_lookup/cases.py`.
- KE fixtures: `docs/history/i183_lookup/ke_cases.py`.
- Before values: extract `8538013b:pettachainer/metta/prolog/event_graph.pl`
  with `git show` to a worktree scratch file and pass its absolute filename
  as the probe's optional first argument. Both probes load the ordinary
  library first and then consult the baseline in that process only. The
  production change is entirely in that Prolog file, plus a MeTTa comment;
  this does not alter production files or the shared PeTTa library-load cache.
- Candidate (i): after loading that baseline, the process-local `graph_model/5`
  clause additionally rejects its completed plan when every model is
  `model(_,root,[])`, factors are nonempty, and every factor's statement is
  identical to the queried goal. The ordinary merge then supplies the answer.
  A part with a report or a conditional producer prevents that rejection.
- `compare_details.py <compare.json> ... --out <directory>` decodes the
  standard benchmark store's belief captures; it runs no benchmarks and
  modifies no stored results. Its ledger records **all** moved TVs, including
  strength-only changes and missing answers. Every row retains the capture's
  own K, reference probability, outcome, variance and z score. Curve inputs
  may be the standard `curves.json` instead.

The benchmark decoder is `n=K*c/(1-c)`,
`V=clip(s,1e-6,1-1e-6)*(1-clip(s,1e-6,1-1e-6))/(n+1)`,
`z=abs(s-reference)/sqrt(V)` (c>=1 is a point). Its outside-2-SD count
compares reference probabilities, not binary realized outcomes. Reported
calibration totals are diagnostic rows, not independent statistical samples.
The full benchmark has existing calibration failures; this patch adds none
in its captured paired rows.

## Midpoint review fix

The final [midpoint report](../ISSUE183_LOOKUP_MIDPOINT_REPORT.md) records the
second review fix. `midpoint/` holds the five graded rows and supplementary
fixtures, the byte-identical 58-row review rerun, the original cases, gate log
and standard benchmark exports. Replay the supplementary fixtures with
`review/probes.py midpoint/fixtures.json` from this directory using the pinned
venv and the capped, time-limited wrapper described in the report.
