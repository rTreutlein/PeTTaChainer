# Forward chaining and learning: smallest retained mechanisms

Baseline: `9102bd1c`. Requirements come from `core_contract.md`,
`runtime_design_assumptions.md` (especially cached rates, folds, lazy reasoning,
and withdrawal), `API.md`, and the forward/learning regression families.

## Required behavior

- Forward runs start caller-selected seeds, continue their carried agenda,
  and construct ordinary skeleton rows. The shared evaluator pays for row
  computations at every depth. Preserve seed share, wave order, divergence
  priorities, rest items, minimum evidence, budgets and returned proof references.
- Publish derived copies separately from authored facts, preserving evidence,
  dependencies and withdrawal provenance. Never count a copy as a new report.
- A population estimate replaces one contribution per statement. Ingestion
  counts merged stored facts; forward and backward reads replace that contribution
  without feedback through the rate. User rates override computed estimates.
  Leave-one-out reads touch indexed sources, in stable statement order.
- Class links use the ordinary implication-instance tally: class changes mark
  subjects dirty, including subjects stored before registration. Stationary
  frequencies, temporal regimes and leave-one-out samples retain their semantics.
- Mining remains opt-in, bounded and ordered by declared time/layers. Review
  reads current learned truths, screens/reconsiders candidates and withdraws
  rules and their exposed copies. Forgetting summarizes historical inference
  but replays aggregate readers and never freezes live RuleTruth parameters.
- Private contexts own their aggregate/cache writes. Public signatures, answer
  TVs, proof/evidence identities and finite-budget behavior must remain intact.

## Current moving parts

o200k tokens, including comments and declarations, using `scripts/core_count.py`:

| File under `pettachainer/metta/runtime/` | Tokens |
| --- | ---: |
| `backward/upward.metta` | 5,701 |
| `forward/aggregates.metta` | 6,012 |
| `forward/schema.metta` | 1,926 |
| `base_rates.metta` | 1,734 |
| `hypothesis_mining.metta` | 4,792 |
| `hypothesis_review.metta` | 2,875 |
| `knowledge_store.metta` | 5,238 |
| `backward/forgetting.metta` | 3,732 |
| **Subtotal** | **32,010** |

The forward agenda has seed, changed-key and unfinished-reader items. Taken
values and physical copies have separate lifetimes. These are distinct states,
not redundant implementations. Mining's constant window, period window,
candidate sightings, live rules and screened rules likewise answer distinct
questions. The native mining/regime/provenance implementation is in the reserved
`runtime_helpers.pl`; rewriting that mechanism belongs to a later coordinated round.

Aggregate state consists of an alpha-identity registry, trigger interests and
their miss directory, numeric totals, member observations, source reverse
edges and links to skeleton folds. These indexes are necessary for incremental,
context-local updates and selective exclusion. In particular, the trigger
directory avoids the documented same-head import scan; deleting it is not a
simplification of the required performance contract.

The avoidable mechanism is the generic forward sampling pipeline. Its only
numeric subscription is exactly `extract-tv`, `BaseRateEvidence`, `BaseRateAcc`,
`base-rate`, `result-tv`. Nevertheless identities/descriptors carry all those
fixed operations, and sampling constructs an intermediate sample, converts
totals back to an accumulator, and dispatches through generic publication.
Class-link subscriptions only mark the existing instance folds; they do not
use this numeric pipeline.

`pettachainer/metta/repos/PLN/` is already absent at this baseline (no tracked
paths). Historical libPLN comparison examples remain, but no vendored libPLN
implementation can be deleted or moved in this checkout. The used generic
formula library already lives in `third_party/pln_formulas/`.

## Replacement design

Keep one direct base-rate tally, keyed by KB and population pattern. Retain
the necessary existing indexes and the evaluator's subscription boundary, but
remove the generic forward accumulator/sampling apparatus:

1. A base-rate identity and descriptor contain only KB and pattern. The fixed
   fold operations are checked once when recognizing the subscription.
2. Updating a contribution matches the population pattern on a fresh copy,
   obtains weighted positive evidence from the fact and replaces its observation.
   Removal selects the same member directly. Keep descriptor variables separate
   from member matching, so publication cannot specialize the population.
3. A single replacement boundary updates numeric totals, member count, source
   edges and the observation. Publish its direct `BaseRateEvidence` result;
   a drained removal clears the computed entry. Preserve arithmetic order.
4. Generic fold finalization remains: exact folds and implication-instance
   folds actually use its other operations. Do not conflate that evaluator
   boundary with the specialized forward tally.

This removes carried configuration and intermediate representations without
adding stores, states, inference paths or compatibility adapters. It leaves
the shared evaluator, join construction and agenda unchanged. More ambitious
store consolidation would require changing the reserved evaluator/native
interfaces; record those limits instead of retaining a second implementation.

Relevant immediate checks: strict MeTTa suite (including incremental rates,
class links, stored-fact merging, forward units, learning and forgetting),
Python fold refresh and context isolation. After each implementation step run
`scripts/verify.sh`; checkpoint with the standard quick comparison, then full
comparison against master and anchor canary. No expected-failure or numerical
expectation changes are planned. Retain only changes whose gates justify them.
