# Issue 183 lookup — state

- 2026-11-10: Read both predecessor reports, workflow and runtime assumptions.
- Created `i183-lookup` at required master `8538013b`; predecessor branch untouched.
- Existing private venv maps to this worktree; corrected its petta shebang to this worktree too.
- Measuring canonical stored-source reads versus graph precedence. Baseline case probe running via capped, bounded timeout, PID waiter, no DISPLAY/stdin.
- Candidate (i) cannot fix partially known cases 8/9 by definition; investigating (ii), ordinary evidence-aware merge with graph decomposition retained for other keys.
- Candidate (ii): four-line admission exclusion; case 4–9 source confidence .99; part/shared-compound graph values unchanged; conflicting independent parts revise to (.3333305275, .9933110088).
- Initial quick/full PASS: zero accuracy changes. Initial verify found 39 Python failures and one MeTTa file, all old graph-precedence expectations; rewired the plan invalidation test to a different compound and updated source-read expectations. Focused 34-test suite now passes.
- Important discovered limit: `canon` retains child order. Reordered compounds are NOT the same canonical key in master. Kept the change scoped to existing canonical keys rather than silently altering pattern matching/index identity; documented this correction to the brief's premise. Reordered aliases retain their pre-existing graph behavior.
- First complete verify: MeTTa 164/0 and Python 1151 tests pass; fuzzer caught its own old identity-posterior upper bound. Updated that reference to the stated source strength; changed identity-soft source strength 1 -> .8 to keep Q <= I nontrivial, and retained a rejection test below the ordinary strength tolerance. Targeted fuzzer gate now PASS; final verify rerunning.
- Final-runtime quick/full/canary PASS; full has zero accuracy changes, canary differences are historical versus anchor with unchanged candidate/master results. Curves running. Initial full capture analysis: zero changed TVs, including all displayed-confidence calibration counts.
- Final verify PASS, key 56e97c56002e, 156 s: 164 MeTTa passed; 1151 Python tests, 23 expected failures/4 skips; all tail gates pass and available abort counts zero.
- Code/tests/contracts committed as 0a1152648fafa0c5e79c9fcf701d02abaf511c55 with requested trailers. Report commit pending curves and final harness comparison.
- All required comparisons finished: final full PASS (22 comparable cases unchanged); anchor canary PASS and explicit master canary unchanged; curves exit 0, all 56 paired error points across 10 families identical.
- Captured benchmark audit: 90 unique pairs, all 84 master/candidate pairs have identical TVs/calibration; 1015 moved rows are historical anchor differences only. Full calibration unchanged at 1028/7010 outside two displayed SD. KE ledger has 64/92 changed reads, no lost answers.
- Hand-back result: docs/history/ISSUE183_LOOKUP_REPORT.md, with complete case/proof and moved-value ledgers under docs/history/i183_lookup/. Explicit limit: child-order permutations are not the same canonical key today, and this branch does not add Boolean key normalization.
- Every captured job PID is finished and its shell waiter reaped it. Final git diff check passes. No main-checkout/master/predecessor-branch edit and no push, merge or GitHub write.

## November 10 review fix

- The accepted graph admission exclusion remains. Stored compounds install a partial producer at ingestion; optional cavity reads exclude the report's key.
- Bound formula: d=L+(1-U); TV=((L+U)/2,d*min(cL,cU)); no proof at d=0, and the complete producer handles all-known inputs.
- Four blocker values: weak And .01/.990099, equal-confidence And and Or .5/.994975, late evidence 1/.5→.01/.990099.
- Restored exact KE pins. Added decisive, graded/late, Not/pattern, shared-report, derived-source, duplicate-source and native determinism regressions.
- Final hand-back and gates: docs/history/ISSUE183_LOOKUP_REVIEW_REPORT.md. The first-round results above are historical.

## November 10 midpoint review fix

- Replaced the partial strength with the interval midpoint; endpoint confidence and width discount are unchanged.
- All 58 prior review outputs are exactly unchanged, including proofs. Cases 4–9 retain .99; the derived graded CTV case moves as required by the new midpoint.
- Five requested graded rows, derivation, gates and final unposted reply: docs/history/ISSUE183_LOOKUP_MIDPOINT_REPORT.md.
- Final code commit: dcdc890646dccfe6add7d57e327de416dafc9f84. Verify PASS (164 MeTTa files, 1160 Python tests, all tail gates); quick/full/canary PASS; curves complete with 56/56 errors unchanged. Capture audit: 85 pairs, all master TVs unchanged; 1015 anchor changes identical to the prior round.
