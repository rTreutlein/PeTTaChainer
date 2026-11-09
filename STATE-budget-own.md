# STATE budget-own-A (slice A: budget ownership, #175/#176/#177)

Worktree /nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer-budget-own, branch budget-own-A from master 13c6c9c5.
Brief: /nexus/Dev/OpenCog/bench/results/codex-logs/budget-own-A.brief

## Milestones
- [x] worktree + repointed .venv
- [x] repro fixtures in scratch/bo (repro.py, run.sh, batch.sh; logs in scratch/bo/logs)
- [x] #175 pinned replay ownership
- [x] #176 open-root metering + payload charge (row-cost: 1 + stored row words // 1600)
- [x] #177 conditioning fairness (sk-claims-held)
- [x] regression tests tests/test_budget_ownership.py
- [x] docs runtime_design_assumptions.md
- [ ] gates: verify (running, WIP 3), compare quick/full/canary/curves
- [ ] squash WIP commits, report

## Baseline (master 13c6c9c5, issue VM cap 3.5 GB; scratch/bo/logs/base-*)
- i175-1: stack overflow at 54.6 s, 2.8 GB. i175-2/3: (STV 0.0 0.969004...) in 0.04/0.08 s.
- i176 (+defined, nocompute): memory failure ~10-12 s, 2.8-3.1 GB.
- i177 cold: [] 3.4 s 1.27 GB; seq: class/theme answer, both [] (4.1 s, 1.98 GB); case2 0.03 s (1.0 0.97397); certain (1.0 0.98020).

## Design so far (WIP commit e19b52f1 + uncommitted)
- #175: sk-claim-charge! owes (no free) pinned rows outside a claim; sk-replay-turn!/sk-replay-done!/sk-owe-replay!
  (allowances.metta) at the two pin-introducing sites (closed read replay, completion sibling fallback): granted
  turn or branch frame opens a claim (depth 0), else owed (sk_deferred debt, branch_unpaid, ran_out).
  sk-conditioning? = claim open and depth>0 keeps replay reads in out-of-claim mode. Old out-of-claim branch of
  sk-conditioned replaced by "first conditioning in a replay claim deepens".
- #176: sk-scaffold? (root owner and (local rule or ground root)) replaces sk-root? exemption for rows/joins;
  term-cost now counts stored (unshared) words with a limit (bounded walk), all callers pass their budget.
- #177: sk-claims-held: an allowance-paid row deeper than waiting claims must leave their est. cost/2 (capped by
  sk_root_claim_cap); sk-waiting-claims extracted from sk-pay-conditions!.
- After: i175-1 3.2 s ~210 MB; i176 ~5.9 s, 182 answers incl. e1_past; i177 all cases correct.
- Moved: test_nested_conditioning conditioned-evaluations 0 -> 5 (pinned replays now paid in claims).

## Update (WIP 3)
- Early-pay variant of #177 (pay nearer claim at first deeper pop) REJECTED: conditioned on inputs not yet
  computed (compound negation implication 0.14 vs 0.1). Replaced by holding allowance (sk-claims-held).
- sk-owe-replay! no longer bumps sk_ran_out (debt is reported via conditions_unpaid); exhausted replay claim does.
- Row cost moved from statement words to whole stored row (row-cost, unit 1600 words ~ 4x statement).
- Moved tests: nested_conditioning 0->5; deep_conditioning three_period work [0,0,0]->[5,0,0];
  pin_rebuilds test now sets sk_claim_depth 1 (cutset pass, not replay claim). larger_root_slice stays 150.
- #176 incremental RSS (VmHWM reset) ~566 MB vs 512 target; test bound 1024.

## Update (commit f9177b99, squashed)
- Replays now run inline in their own claim whenever the allowance >= 1 (grant-wait variant lost SupplyNet
  stage 3 untimed b50 s4 coverage 0.96). Nested conditioning inside an ungranted replay claim defers
  (sk_deferred debt) as before (#106 test needs this).
- verify PASS (key f5408d26abf9 at WIP 5, same tree as f9177b99).
- quick: REGRESSIONS (1): supplynet stage 3 untimed b50 s4 producing_unstocked error 0 -> 0.002305
  (closed-read replays now charged; with closed reads free it passes). stage 3 timed b100 improved.
- Moved tests: nested_conditioning 0->10; four_period 308->318; larger_root_slice 150->160;
  pin_rebuilds test sets sk_claim_depth 1. three_period stays [0,0,0].
- Running: compare --full (scratch/bo/full.log); then canary, curves, report.

## Update (commit 85c97282, squashed, final code)
- Replays near the root pay from the near-root reserve (reserve-slice), others from the allowance.
- Hold = sum of needed, ungranted pending targets nearer the root, only while 0 < allowance <= cap.
- verify PASS (key 0943fa4c1f69); quick PASS; full PASS (13c6c9c5_vs_85c97282_full).
- Running: canary then curves (scratch/bo/canary.log, curves.log; bench.pid). Then commit report + state.

## Review round (Codex review budget-own-A-review/RESULT.md), commit 545d06a0
- P1: term-cost/row-cost report Units+1 when the walk stops; sk-pay-cost! (cost 1 takes positive balance, dearer
  must fit). Refused row closes sk_row_budget. Need-walk extra requires exact fit.
- P1: sk-scaffold? = root owner and local (query) rule only.
- P2: sk-claims-held $item $cost tests balance after payment.
- Tests added: affordability, fan-out, interrupted #175, plant8 ownerless, fairness boundary.
- verify PASS key 484f8a1822e1; quick/full/canary PASS; curves same deltas as before.

## Second review round (budget-own-A-review2), code commit 3d667f63
- Refusals keep no payload: sk-refuse! counter; innermost owner keeps (sk-join waiter) or (sk-deferred owner rule);
  join digest unstored on refusal (sk-unstore-join!); gate also defers compact join; CPU premises stop once the
  row allowance is closed. Resume re-reads premise keys (sk-read-answers!) or restarts the rule.
- verify PASS key ab05f1d23c36; quick/full/canary PASS; curves unchanged deltas.

## Third review round (budget-own-A-review3), code commit 8536df04
- Deferred joins hold (sk-join owner rule wait-handle); functional waiters held by a deferred join are not retired.
- Forward takes own refusals: key carried as seed (sk-forward-retained!).
- Rule starts with ground computations deferred once the row allowance is closed (sk-computes-now?).
- verify PASS b86e48795f69; quick/full/canary PASS; curves: conflict m s1 low-budget losses grew (b1 0.1050).

## Fourth review round (budget-own-A-review4), code commit 3866b58d
- Waiter identity: sk_wait_id/sk_wait_id_of allocated per stored payload (flag), removed on retraction; handle =
  identity, hash only collision-checked lookup; functional hold by identity. Collision regression added.
- verify PASS 335f3d8808ea; quick PASS (13c6c9c5_vs_3866b58d_quick). Full/canary/curves from round 3.

## Fifth review round (budget-own-A-review5), code commit 335f0057
- Deferred dedup by exact record; sk-settled?/sk-start-deferred! compare node via sk-same-node?; audit in report.
- verify PASS 1a2686a3a796; quick PASS (13c6c9c5_vs_335f0057_quick).
