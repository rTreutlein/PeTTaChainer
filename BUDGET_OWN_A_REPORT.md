# Slice A: the budget owns every unit of work (#175, #176, #177)

Branch `budget-own-A`, worktree `/nexus/Dev/OpenCog/NL2PLN_Project/PeTTaChainer-budget-own`, from master
`13c6c9c5`. Brief: `/nexus/Dev/OpenCog/bench/results/codex-logs/budget-own-A.brief`. The diagnoses it builds on
are `PeTTaChainer-i175/I175_REPORT.md`, `PeTTaChainer-i176/I176_REPORT.md` and
`PeTTaChainer-i177/RESULT-i177.md`; nothing was cherry-picked from their branches.

## What changed

**#175, pinned replays.** `sk-claim-charge!` let every row read under pins run free while no claim was open.
Now such a read is owed, never free. The two readers that bring pins outside a claim are a closed read that
replays a complete key's rows under its unfounded pin, and an antecedent completion's sibling read under its
completed pin. Both call `sk-replay-turn!`:

- The replay runs in a claim of its own, paid the way its row is paid. If the reading row (the outermost
  active reader) is within the free depth, the claim draws on the near-root reserve while that lasts,
  through a new `reserve-slice` tier of `execution-open-slice!`/`execution-close-slice!`. Otherwise it draws
  on the allowance. Either way the tariff is the usual two conditioned rows per unit.
- When neither can pay, the reader owes the replay (`sk-owe-replay!`). Its row keeps its incumbent and waits for a turn
  through `sk_deferred`, and the unpaid replay settles no branch.
- When a replay exhausts its claim, `sk-replay-done!` drops the partial pass and marks the reader as owing.

A replay's claim has depth 0, and `sk-conditioning?` (claim open and depth > 0) separates a cutset pass from
a replay. That keeps the replay's reads exactly as they were outside a claim. A conditioning inside a replay
deepens only on its row's granted turn and otherwise takes its approximation, as before. #106's test depends
on this: one inline pinned claim over 29 statements used to take the whole allowance. The old out-of-claim
branch of nested `sk-conditioned` could no longer be reached, so it was replaced by this one.

**#176, root rows and payload.** A row whose owner was a root used to be exempt (`sk-root?`). Now only the
query's scaffold is exempt (`sk-scaffold?`): rows of the query's own compiled rules. A root's applications of
KB rules, open or ground, spend the row allowance and the join gate like any other row (review finding 2: a
ground `(Q a)` over 1,000 facts got 1,000 free rows at one step). Rows are charged by `row-cost`: one unit, plus one for each 1,600 words of the row as stored, paid
before `add-atom` copies it. The unit is calibrated because a row holds its statement about four times: a
row of a 900-word statement has 4,040 words (measured on `(Num $x) → (Num (succ $x))`). So 1,600 row words
equal the 400 statement words of `term-cost`, and an ordinary row of a few hundred words still costs 1.
`term-cost` (and `row-cost`) now count stored, unshared words, so shared subterms count again, and they walk
a term only as far as the allowance left can pay. A count stopped there reports one more than the limit,
i.e. "over", never the part counted (review finding 1: a 76-unit row was paid 12). Every caller pays through
`sk-pay-cost!`: a cost of one takes a positive balance as before, a dearer one must fit whole. A refused node
expansion stays on the frontier, a refused evaluation stays stale, a refused rebuild keeps its request. The
need walk's extra-size charge requires its exact cost to fit.

**Unpaid work keeps no payload (second and third reviews).** A refused row closes the row allowance (sets
it to 0). Once it is closed, no ground user computation runs: not in the prefilter at a rule start
(`sk-start-rule-step` defers a rule with such a premise before prefiltering; `sk-computes-now?` is the shared
test) and not in `sk-advance!`. The refusal (`sk-refuse!`) is owned by the innermost application in progress,
which keeps only how to rebuild the row:
- a join extension forgets that it extended by that key (`sk-unstore-join!` drops its join digest) and keeps
  `(sk-join owner rule handle)` in `&sk_deferred_joins`, where the handle is its stored waiter's identity: a
  number allocated once per stored waiter payload, never reused, indexed both ways with the payload's clause
  reference and removed when the payload is retired (`sk_wait_id`, `sk-wait-handle`, `sk-waiter-at`). The
  variant hash stays only a collision-checked lookup (fourth review: as the handle, two colliding waiters of
  one owner and rule shared one deferred record and a retired waiter's handle redirected to the other);
  neither the key nor the terms its
  earlier premises bound are copied. The closed-allowance gate in `sk-extend-current!` keeps the same record.
  A functional waiter that a deferred join holds is not retired on delivery until that join is read again.
  Deduplication of deferred records compares the whole record (`=alpha`); the owner's node hash and the
  record's hash only find candidates (fifth review: a hash-only presence test merged two rules' records
  whose hashes met, and one continuation was lost).
- a rule started at a node keeps `(sk-deferred owner rule)` in `&sk_deferred` (`sk-defer-rule!`), deduplicated
  the same way;
- a forward run's joins never wait (no stored waiter, no handle), so its take owns the refusal: the taken key
  is put on the carried agenda as a seed (`sk-forward-retained!`), and a later run, even with no facts of its
  own, takes it again. A take that builds the row leaves no item.

A later walk that reaches the node, with rows allowed, reads the join's premise keys again or starts the rule
again at its owner. Measured with the review probes (words of the physically stored deferred records):

| Probe, one step | review 2 / 3 found | now |
|---|---:|---:|
| four 10,000-atom facts, one-premise rule | 90,450 (row) / 321 (join) | 39 per join |
| four 10,000-atom facts, then `(Tag $y)` premise | 361,644 (bound waiters) | 168 for four joins |
| 32 Compute-only rules | 2,372,832 | 1,152 (32 × 36); 0 user computations after the allowance closed (was 31) |
| forward `(P big) → (Q)`, seeded 1-step run then empty 200-step run | no Q (master: Q) | Q returned and stored, as a cold run; agenda empty after |

Retries complete: the single and two-premise probes, with a late fifth fact, return 5 and 10 answers whose
digests equal the cold controls, and withdrawing the rule clears its deferred join.

**#177, fairness.** Conditioning still takes its turns after the ordinary rows, so it reads their values.
But a payment for a row deeper than a waiting target that would leave less than the root-claim share is made
only if the waiting targets nearer a root keep their estimated cost: cost/2 units summed over needed,
ungranted targets, capped at `sk_root_claim_cap` (`sk-claims-held $item $cost`). The test is on the balance
after the payment, so one large row cannot step from above the share to nothing (review finding 3). Queries
only; a forward run orders its rows by creation. `sk-pay-conditions!` is unchanged from master.

## Rejected alternatives (measured)

- **Paying the nearest waiting target as soon as a deeper row came up.** It conditioned the target on inputs
  that had not been computed yet. A compound-negation implication read 0.14 where the answer is 0.1
  (`test_compound_not_judgments`).
- **Running owed replays only on the row's granted turn**, the same deferral conditioning uses. It answered
  #175, but on SupplyNet stage 3 untimed b50 s4 coverage fell from 1 to 0.963 and error rose from 0.0004 to
  0.032: the turns come after the ordinary rows, and those had already spent the allowance.
- **Paying every replay from the allowance.** Near the roots, closed reads of complete predicates found the
  allowance already spent. In `--full`, stage 3 untimed b25 s4 coverage fell to 0.971 and error rose from
  0.0004 to 0.024; soft0.9 b100 lost coverage too; stage 3 timed b25 s3 error rose from 0.0038 to 0.0080.
  Paying near-root replays from the reserve brings all of these back to PASS.
- **Computing the hold from the full ordered claim list** (`sk-needed?`, `sk-readable-row?`, sort) on every
  allowance-paid row. Conflict pln-sources m spq4 s2 went from 10.6 s to 12.1 s (paired rerun). The hold now
  sums the pending targets that are needed and not granted, and is computed only when the balance is
  positive and the payment would leave at most the cap. A first version reused the variable names `$khash`/`$key` from the item pattern
  inside the scan; MeTTa variables are clause-wide, so the scan matched only the item's own key and held
  nothing.
- **Charging rows by their statement only, counted unshared.** #176 still added about 1.5 GB: rows averaged
  25,000 words on statements of about 3,000.
- **Charging the whole row at 400 words per unit.** Every ordinary row (about 444 words) cost 2.

## Issue measurements

Fresh process per case, `ulimit -v 3500000`, warm library cache (load 130 MB), 400 steps. "Added" is the
peak RSS during the query (VmHWM reset with `clear_refs`) minus the RSS before it. The bench pool was busy
with other work while these ran. Script: `scratch/bo/repro.py` (not committed).

| Case | master | branch | Target (reports) |
|---|---|---|---|
| #175 case 1 | stack overflow at 54.6 s, 2.8 GB | 9.0–9.4 s, +330–385 MB, one answer `(STV 6.33e-11 0.000564)` | < 10 s, < 1 GiB: met (barely on time) |
| #175 case 2 / 3 | `(STV 0.0 0.9690040722935537)` | same, 0.03 / 0.07 s | unchanged: met |
| #176 (undefined Compute) | memory error at 10.3 s, 3.1 GB | 3.4 s, +557 MB, 128 answers incl. `e1_past (STV 1.0 0.99)` | 15 s met; < 512 MiB added: not met (557) |
| #176 defined function | stack overflow at 10.3 s, 2.8 GB | 3.4 s, +557 MB, same | as above |
| #176 no Compute | stack overflow at 11.7 s, 3.1 GB | 3.0 s, +577 MB, 106 answers incl. `e1_past` | as above |
| #177 case 1 cold | `[]`, 3.4 s, 1.27 GB peak | `(conditioned s1 ...)` `(STV 1.0 0.9739695489836424)`, 2.4 s, +513 MB | < 2 s, < 256 MiB: not met |
| #177 after single queries | class, theme answer; both `[]` (4.1 s, 2.0 GB peak) | all three answer; both 2.5 s, +192 MB | |
| #177 case 2 | `(STV 1.0 0.9739695489836424)` 0.03 s | same | unchanged: met |
| #177 certain fact | `(STV 1.0 0.9801977747248122)` | same | unchanged: met |

#175 case 1 still has the low-confidence value; per the brief it is recorded, not asserted. It moved from
master's successful-run value `(6.18e-11, 0.000576)` to `(6.33e-11, 0.000564)`, because the replays are now
bounded by the reserve and the allowance. The #176 and #177 memory that remains is eager structural
storage: rows and their copies in `&sk_new`, readers, latest views and answers (for #176: 384 rows of 6.9 M
words, 2.9 M words of readers, 2.1 M of latest views). That is slice B's work: queueing row identities
instead of payloads.

## Regression tests

`tests/test_budget_ownership.py` runs each case in a fresh subprocess under a 3.5 GB `RLIMIT_AS` and a
180 s deadline, and measures the query's added RSS with the peak reset:

- #175 case 1: one answer for the root, < 30 s, < 1 GiB added. The value is not asserted. **The time bound
  is relaxed from the report's 10 s target** (measured 9.0 s, too close for a test bound).
- #175 cases 2 and 3: proof and `(0, 0.9690040722935537)` at 1e-12.
- #176 (undefined Compute, defined function, no Compute): contains `(: e1_past (Past sk_manage_1) (STV 1.0 0.99))`,
  < 15 s, < 1 GiB added. **The memory bound is relaxed from the report's 512 MiB target**, which is not met
  (measured ~557–577 MB).
- #177 cold, and after the single queries: one `(conditioned s1 ...)` answer, strength 1, confidence
  0.9739695489836424 at 1e-12, every query < 10 s.
- #177 case 2: the same value. Certain-fact control: the unconditioned conjunction proof and
  `(1.0, 0.9801977747248122)`. #177's memory is not asserted (target 256 MiB not met).
- Affordability and unpaid retained size: four facts of 10,000 atoms under `(no_inverse r) (P $x) → (Q $x)`:
  at 1 step, twice, the open query gets no answer and the deferred stores hold under 2,000 words; a
  200-step query on the same KB answers all four and leaves nothing deferred.
- Applications without a join: eight rules whose only premise computes a 4,096-leaf term: at 1 step no
  answer and under 1,000 deferred words; at 200 steps the merged answer and nothing deferred.
- Fan-out: one rule over 1,000 facts concluding ground `(Q a)`: at 1 step the query takes < 5 s (it was
  16.5 s with 1,000 free rows), and at 3 steps the answer's confidence is higher.
- Bound waiter: the two-premise rule `(And (P $x) (Tag $y))` over four 10,000-atom facts: at 1 step, twice,
  no answer and under 2,000 deferred words; at 400 steps all eight answers and nothing deferred.
- Forward continuation: a seeded 1-step `forward_chain` refuses the large row and keeps under 2,000 words; an
  empty 200-step run returns what a cold 200-step run returns (kb ids aside), a further run returns nothing
  new, and nothing stays deferred.
- The Compute-only test also counts the user function's calls while the allowance is closed: zero.
- Colliding deferred records (in-process): waiters of one open owner under two rules are stored, alternating
  the rule, until two `(sk-join owner rule identity)` records' index hashes meet; both are kept, a repeated
  deferral adds none, and one resume reads each waiter once and clears both.
- Colliding waiters (in-process, production `sk-store-wait!`; waiters stored until a variant-hash bucket
  holds two of one owner and rule): two distinct identities, two deferred records, one resume reads each
  waiter exactly once and clears both, a deferred join on one does not hold the other's functional
  retirement, and retiring one leaves its handle resolving to nothing and the other's to itself.
- Interrupted/retried replays: #175 case 1 at 25 steps reports `ran-out` and still answers; at 400 and
  400 again it keeps answering.
- Ownerless owes (branch rebuilds with no reading row; the review saw them in the eight-period plant and the
  #106 prefix): the eight-period plant at 3000 steps three times answers both roots each time; the first
  answer is coarse, the second differs (the owed branch requests were paid), the third equals the second.
- Fairness boundary (in-process, constructed scheduler state as in the review's probe): a depth-0 target of
  estimated cost 6, cap 10, a depth-3 row of exact cost 12: at balance 12 the row must leave 3 held units, at
  balance 30 nothing is held, at balance 10 a cost-1 row also leaves 3.

No internal row counts are asserted.

## Moved test values

- `tests/metta/test_nested_conditioning.metta`, conditioned evaluations 0 → 10. The antecedent completions'
  sibling replays under their pins used to run free outside any claim; now a claim pays for them and counts
  them. The answer `(STV 0.0 0.983052335327906)` is unchanged.
- `tests/test_deep_conditioning.py::test_four_period_root_matches_branched_product_filter`, first-query
  conditioned evaluations 308 → 318: the 308-row cut plus 10 completion-replay rows. The value is unchanged
  (bk_t8(4) at 1e-8).
- `test_larger_root_slice_can_retry_an_exhausted_smaller_slice`, 150 → 160: the root's 75-unit slice plus the
  same 10 replay rows.
- `test_pin_rebuilds_latest_view_before_selecting_an_older_compatible_view` now also sets
  `sk_claim_depth` to 1 after `sk-open-claim!`. The test drives a cutset pass by hand, and a claim at depth 0
  is now a replay's claim, which keeps the outside-claim reading. Expected value (23/34) unchanged.

## Gates and benchmarks

Accuracy numbers are deterministic, so every change below is real; "negligible" means a difference in the
last digits, not statistical noise.

- `scripts/verify.sh`: PASS, recorded under key `1a2686a3a796` (the tree of the code commit). Quick rerun on it; full, canary and
  curves below are from round 3 (`8536df04`), whose behaviour differs only in the deferred-join handle.
- Fixture-shape change, not a value move: `tests/metta/test_withdrawn_rules.metta` builds deferred records by
  hand; they now use the compact shapes `(sk-join $node 999800 999806)` (owner, rule, waiter identity) and
  `(sk-deferred $node 999800)`.
- `compare.sh master <wt> --quick`: **PASS**, accuracy changed in 2 cases
  (`bench/results/compare/13c6c9c5_vs_335f0057_quick/report.md`).
- `compare.sh master <wt> --full --no-fail-fast`: **PASS**, accuracy changed in 5 of 22 cases, no timing flag
  (`bench/results/compare/13c6c9c5_vs_8536df04_full/report.md`):
  - stage 3 timed b100 s3 error: 0.00134 → 0.00078 (better)
  - conflict pln-sources m spq4 s3 error: 0.184 → 0.178 (better), but Brier 0.1299 → 0.1352 (worse, below
    the flag threshold)
  - conflict pln-sources m spq4 s2 error: 0.07546 → 0.07541 (negligible)
  - stage 3 untimed soft0.9 b100 s4 error: 0.01483 → 0.01481 (negligible)
  - stage 3 untimed b100 s4: error differs by about 5e-20 (floating point)
- `compare.sh anchor <wt> --canary`: **PASS** under the comparator's master-relative policy, accuracy changed in
  4 of 6 cases (`bench/results/compare/anchor-b4065459_vs_8536df04_canary/report.md`). It lists nine existing
  deficits versus the anchor, shared with master, and no progress toward it; this is not anchor parity.
- `compare.sh master <wt> --curves` (`bench/results/compare/13c6c9c5_vs_8536df04_curves/curves.md`). Most ladder
  points are identical and the candidate is faster at most low budgets. Measured quality losses:
  - conflict m s1: the ladder now runs to budget 16. Worse at low budgets: b0.5 0.1313 → 0.1386, b1
    0.09519 → 0.1050, b2 0.09534 → 0.09748, b4 0.09706 → 0.09955; b8 0.0893 → 0.0896; b16 0.09298 → 0.09237.
    **Best error 0.0893 on master vs 0.0896 on the branch.** The b0.5/b1 losses grew this round (round 2:
    0.1327 / 0.09739); the likely cause is the new gate that defers rule starts with a ground computation once
    the row allowance is closed. Not isolated.
  - stage 3 timed s2: **best error 0.001653 vs 0.001693** (at b200).
  - stage 3 timed soft0.9 s3, b25: 0.02323 → 0.02411.
  - stage 4 extend s2, b10: 0.02485 → 0.02491 (negligible); its best error is equal.
- An earlier `--full` of the intermediate design, which paid all replays from the allowance, flagged 16
  regressions (`bench/results/compare/13c6c9c5_vs_f9177b99_full/report.md`). That design was replaced.

## Limits and what is left for the next slices

- Hash-for-equality audit (fifth review) of the deferred, join, wait and agenda code:
  - fixed: deferred-join and deferred-rule deduplication (exact record); `sk-settled?` counts a live deferred
    record only for its own node (`sk-same-node?`: same statement and context, or same fold arguments),
    where any record under the node hash counted; `sk-start-deferred!` starts only the node's own deferred
    inversions, where every inversion under the node hash started.
  - already exact: `sk_wait_ref` (variant check), waiter identities, the functional hold, `sk-resume!` (owner
    `=alpha`), the forward carried seed (`=alpha`), forgetting's deferred-inversion removal (owner `=alpha`),
    `&sk_forward_stored` reads (fact compared), the pending-work index (`pw_known` variant check).
  - left as designed: join digests (`&sk_join_link`, `link-digest`) are the existing 60-bit join identity
    contract used by thawing and retirement on master, and `sk-unstore-join!` removes by that digest;
    `holds_work`/`pw_drop_unused` test a node hash only to decide whether to keep pending state, so a
    collision keeps state longer, never drops it.

- #176 item 3 and #177 storage items 1–2 (queueing row identities instead of payloads, incremental
  structural delivery) are not done. That remaining eager storage is why #176 adds about 570 MB (target
  512 MiB) and #177 adds about 515 MB and takes 2.5 s (target < 2 s, < 256 MiB). Admitted rows are now
  paid for at their stored size, but each paid row is still copied into several stores (`&sk_new`,
  readers, latest views) whose copies are not charged separately.
- #175 item 4 (pruning residual choice points at a verified functional boundary) is not done; no test of
  functional output was written.
- Deferred records are compact but not charged, and their number is not budget-bounded: one per refused
  (owner, rule) or join. A deferred join's owner is the expanded node itself (already paid when expanded).
- A deferred join is only as durable as the waiter its handle names: if the waiter is retired (its rule
  withdrawn, its conclusion known), the join resolves to nothing, as the join itself would have been retired.
- A join that extends again on resume reads all its premise's keys; those it already took stop at their
  digests, which costs a lookup each.
- conflict m s1's extra low-budget loss this round (b0.5 0.1386, b1 0.1050) was isolated by the fourth
  review to the gate that defers rule starts with a ground computation once the row allowance is closed;
  restoring the old prefilter path alone gives 0.1327 / 0.0974. Accepted as the cost of stopping
  post-closure computation.
- The forward continuation is the carried agenda's seed item, which holds the key as the agenda always does
  (the key is a stored fact or a key a paid row derived); agenda items by identity are slice B.
- Already-paid queues (`&sk_new`, rows, readers) still hold payload copies; that is slice B.
- At budgets where a ground root has more applications than the allowance, it now builds fewer rows per
  query; the benchmark profiles show no flag for this, but the fan-out regression test is the only direct
  check.
- Owed replays outside any row computation happen inside branch rebuilds (`sk-build-wanted!` →
  `sk-rebuild-view`), with no reading row: one in the deep-conditioning debt test and 27 in the #106 prefix,
  per the review. They record no row debt. The unpaid generation keeps the branch request unsettled, and the
  eight-period plant regression shows the next query paying them. Root and representative reads were not
  seen owing.
- The hold uses the targets' cost estimate, which the contract calls "for ordering only", capped at the root
  claims' share. It does not check readability, so an unreadable pending target can hold a few units that
  nobody spends.
- Repeated #175 queries (400, 400, 4,000 steps, per the review) keep the same answer and retain conditioning
  debt; no convergence or quiescence is claimed for that fixture.
- The #175 case 1 value awaits the semantic decision about generalised bridge priors and is not asserted.
- The memory numbers come from single runs on a shared, loaded machine.
