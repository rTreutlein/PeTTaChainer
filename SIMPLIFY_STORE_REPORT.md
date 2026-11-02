# simplify-store report (Proofs, Fact store, Runtime terms)

Commit: see `git log 39e41c5e..` (one behaviour-preserving step).

## Tokens (o200k, coupling.py groups)
| Subsystem | before | after | delta |
|---|---|---|---|
| Proofs | 8603 | 8454 | -149 |
| Fact store | 6976 | 6965 | -11 |
| Runtime terms | 2577 | 2548 | -29 |
| Search state (caller inlining) | 13546 | 13561 | +15 |
| core_count.py core | 325939 | 325765 | -174 |

Coupling: 117 edges (=), cross-boundary functions 637 -> 636, Proofs interface
28 -> 27, largest function SCC 74 (=), functions in cycles 181 (=).

## Moves kept
- `proof-term-negated?` deleted; its five uses read `(head-is? p negated)`.
- `shared-evidence-frontier-proof?` deleted; its one caller (application read
  plan) reads `(head-is? $proof total-implication-frontier)`.
- `checked-stored-tv` delegates the likelihood/no-evidence/other cases to
  `expected-tv` instead of repeating them.
- `typed-runtime-fact` destructures in its head instead of a one-branch case.
- `set-context-polymorphic-facts` staged as `let*`, like `set-rule-refinement`.

## Tried and reverted (each broke a test or a gate; recorded as traps)
- `space-row-present?` for `($name $kb)` presence rows (rule identity,
  positive-only, complete predicates): the row argument is evaluated, so a rule
  named like a function (`empty`, `flip`) is called. test_pettachainer,
  test_specificity, test_conditional_world_facts failed.
- `|->` lambdas over proof names / evidence entries (`any-flat?` for
  leaf-names?, all-members?, uncertain-evidence-step): same argument-evaluation
  hazard; named steps with Atom params keep names as data.
- Building child lists with `(cons $a (cons $b ()))` to fold the five binary
  `evidence-union` cases of `proof-term-evidence`: cons evaluates proof terms.
- Constructing `(fact-ev ...)` to reuse the fact-ev case for not-fact-ev: same.
- Passing `(data ...)` or `(car-atom ...)` straight into a Prolog native
  (`source-catalog-unindex!`, `atom_concat`): natives get the unevaluated call.
- Merging register-given-name!/register-given-branches!: the strict determinism
  checker rejects the folds in every merged shape tried.
- `chainer-first-or` in proof-ref-evidence: adds a Proofs -> Runtime terms edge.

## Limits
- `proof-term-evidence` keeps a `$mode` parameter whose only production value is
  `proof-walk-in-kb`; removing it needs edits in runtime/evaluator/versions.metta
  and statistics/aggregates.metta, both outside this round.
- Most remaining code in these subsystems is held in place by evaluation
  boundaries (Atom-typed steps, typing boundaries, det-checker parameter folds).
