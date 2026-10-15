# Existential queries and premises

Trackers #48 and #51 (October 2026) support bare `Exists` queries, stored and
derived rule judgments with `Exists` on a complete side, and existential facts
and goals in `Assuming`. Stage 2 retains stage 1's floor, unknown-on-empty,
correlated-witness lower bound, and shared premise/query lowering.

## Judgment

For `(Exists ($x ...) body)`, the compiler reads two nested propositions:

* E: the canonical `ExistentialClaim` for the body. Ordinary evidence merging
  combines its proofs, including non-constructive conclusions of stored rules.
* D: the disjunction of distinct matching witness tuples. Multiple rule paths
  to one tuple merge at its existing statement key before entering the fold.

The answer is the stronger of E and D, retaining that judgment's confidence and
proof. These channels never revise against one another. Strength selects first. On an exact strength tie, higher confidence represents
more evidence and wins without revision. If both TV components tie, the
alpha-normalized statement-key order chooses the source; allocation and
discovery order do not. This same ordering chooses among correlated witnesses.
For example, direct (1, 0.5) and witness (1, 0.9) return (1, 0.9) in either order.
Confidence cannot defeat a higher strength.
Thus E=0.9 and independent witnesses 0.8, 0.6 yield D=0.92 and answer 0.92.
A certain witness suffices without a separate settling rule.

For independent witnesses, D uses the existing `OrFormula`, with strength
`1 - product(1 - p_i)` and its propagated evidence confidence. The first witness
keeps its TV unchanged; it is not combined with a synthetic zero observation.
Sharing an uncertain rule parameter does not correlate two instances: two
certain Birds through a 0.9 rule yield existential strength 0.99, consistent
with conjunction strength 0.81. Shared uncertain **fact** dependencies use the
same overlap test as `And`. If any such overlap occurs, stage 1 conservatively
uses the strongest individual witness TV across the **whole population**. Two
correlated witnesses at 0.5 plus an independent P(c)=0.4 still give 0.5, not
0.7. The result carries only the selected witness's proof and evidence. The
scan unions all evidence only to detect overlap; all member dependencies remain
to invalidate the result when any member changes. This is a lower bound, not
component-wise OR; combining independent components of an overlapping
population is stage 3.

Only positive-strength, positive-confidence witnesses contribute. An empty fold
has no value. Neither exhaustion, a budget cut, all known witnesses being false,
nor `set-complete-predicate` makes an open existential false. Explicit
`Not (Exists ...)` support is deferred to stage 3; completion is stage 4.
`ExistentialClaim` remains a direct-claim view, not a witness aggregate.

`KnownExistential` also has no value when empty. `ExistentialResidual` is
different: its witness contribution D defaults to (0,1), so E=0.9 and no known
witnesses gives residual strength U=0.9. The direct claim binds outer arguments
before the residual's scalar witness fold, including groups with no witnesses.
A later witness refines D and U through the existing formula. The empty identity
does not assert that Exists is false or that its population is complete.

`lower-source-premise-with-existentials` is shared by bare queries and rule
premises. Applying a rule then uses the existing modus-ponens formula, including
its usual confidence propagation. A claim and concrete witness derived from
the same Seed are compared by the floor, never counted twice.

## Scope and public terms

`canonical-existential-side` validates a complete side, then replaces its bound
variables with `(exists-slot 0)`, `(exists-slot 1)`, etc., in binder order.
Slots are local to the enclosing `ExistentialClaim`. Free outer variables remain
shared with the other side of a rule or identify independent answer groups.
Multiple variables may denote the same concrete witness; slots do not assert
inequality. Nested binders and binders with unused variables are rejected.

Stored-rule lookup indexes the canonical structure in the existing private
implication namespace. Its shape hash and scoped slots preserve alpha matching;
source binder variables never participate in runtime unification. It works at
budget zero. This is **syntactic matching up to variable renaming**:
`(And A B)` differs from `(And B A)`, and `(Exists ($x) (P $x $x))` cannot match
`(Exists ($f) (P $f $s))`. Lookup never unifies source binder variables.

Public results keep `(: proof statement (STV strength confidence))`. Bound
variables are freshly reconstructed from slots, independently on each rule side;
outer sharing and co-reference are preserved. An existential returns one answer
per outer binding, without exposing a witness substitution or an `exists-slot`
as an outer argument. Proofs use the claim's own proof, an independent-witness `disjunction`, or the
selected witness's proof for the correlated lower bound. Source IDs remain available to app-side grading, including
through `query-many-refs` and `expand-proof`.

No witness object or categorical body fact is made from a non-constructive
claim. Quantified query compilation prepares a positive judgment context;
a stated fact still answers at budget zero without expanding that context.
The internal `ExistsJudgment` and `ExistentialAlternatives` adapters are excluded
from fact materialization. No stores, overlay registrations, status pair,
closure certificate, or diagnostic fields are added.

## Private judgments and Assuming

A quantified implication assumes one canonical claim when its antecedent is
existential, and proves its consequent using ordinary rules. It returns the
positive-branch STV, with a `conditional-implication` proof containing those
rules. It never assumes or projects the existential body. Existential
consequents call the same premise lowering as bare queries. Exact stated rules
retain their rule-evidence identity, so applying a rule under its own antecedent
cannot boost its confidence by revising its axiom with itself.

`Assuming` accepts an existential fact directly or among its `And` facts, and
a bare existential goal. Its usual world-reading behavior is unchanged. It
freshens local binders before goal bindings can affect the displayed statement.
No assumed claims or categorical consequences leak to MAIN. Source withdrawal
invalidates conditional results through the existing rule-provenance machinery.

Private judgments route scalar and grouped existential folds into their
hypothetical scope, preserving free-variable links when reading cached members.
Assuming instead shares MAIN fold and member identities and overlays dependent
values. An assumed `Exists` supplies only an `ExistentialClaim`; existing reader
edges propagate its change to the direct channel and floor. Concrete assumed
facts propagate through the witness channel. MAIN-scoped existential compilation
inside ContextQuery therefore reads the overlay during C evaluation. Binder
freshening and public reconstruction also apply to existential Assuming answers.

Nested quantifiers, binders with unused variables, quantified nested implication
export, quantified implications supplied as Assuming facts or goals, and existential
terms inside an implication-side connective remain unsupported. Negation,
completion, and overlap-aware OR remain separate stages.

## Runtime and cost

The compiler builds a witness `FoldAll` (or grouped fold) and an outer
`ExistentialFloor` fold over at most two channel members per group. Their normal
skeleton keys, dependency subscriptions, and durable fold views handle reuse and
late evidence. A cached empty fold remains subscribed: a newly valued member
must wake its readers even though its previous value was `sk-none`. This
empty-view exception is restricted to OrFormula/ExistentialFloor folds; ordinary
fold invalidation keeps its previous behavior.

Forward premise indexes include the claim and witness-body triggers. A trigger
wakes the full fold judgment; it is not an extra evidential premise. The forward
wave drains newly exposed **existential** folds within the same search
allowance and includes those fold roots' readers. Ordinary folds retain their
previous first-wave search and reader scheduling. The wave grounds its conclusion
context to the taken fact. Internal channel adapters remain in the skeleton and
are excluded from forward results and stored facts.

A changed population recomputes D in O(m) member reads plus the existing cost of
merging values and evidence sets. The floor adds at most two reads per group.
There is no update tree and no claim of constant cost in population size.
Compilation and canonicalization also traverse the source term. Search and
recomputation use the existing budgets; unfinished work returns no answer or an
evidence-supported partial lower bound, never synthetic false. Existence folds
do not require exact-population coverage or wrap proofs in `partial-fold`.

## Validation and moved expectations

`tests/metta/test_exists_queries.metta` covers the stage-1 design acceptance
cases, including the issue's saved KE rules, both channels, confidence,
correlated facts versus shared rules, duplicate derivation paths, grouped outer
variables, local binders, slots, stored-rule scope traps, budget ladders, late
witnesses, wrong entity/shift, and absence of fabricated witnesses. The original
`test_explicit_exists.metta` continues to cover residuals and durable groups.

Stage-1 changes relative to its pre-implementation master:

| Expectation | Before | Stage 1 |
|---|---|---|
| Bare `Exists` | empty | supported by E or D |
| Empty existential premise | zero-valued fold could feed a conclusion | no value |
| Empty KnownExistential | false-valued conclusion (roughly 0/0.9998) | no value: absence is not negative evidence |
| Empty ExistentialResidual | U=E | U=E, restored after the initial stage-1 regression |
| Mixed E=0.9, witnesses 0.8/0.6 | alternative paths could revise | 0.92, witness confidence |
| Overlapping witnesses from one uncertain fact | ordinary OR could inflate | strongest witness lower bound |
| Stored quantified rule query | empty | stated STV at budget zero |
| Grouped runtime views | one witness fold per group | witness and floor views per group |

Skipping the artificial zero fold member also moves floating-point confidence
snapshots (strengths and source proofs unchanged):

| Test/value | Master confidence | Stage-1 confidence |
|---|---:|---:|
| Explicit/existing P-to-T | 0.7123799943249737 | 0.7123799943294165 |
| Known cats, two | 0.9010944415002473 | 0.9010944430631548 |
| Residual, two cats | 0.8948358186906257 | 0.8948358186950726 |
| Known cats, three | 0.9043600864574071 | 0.9043600865076092 |
| Residual, three cats | 0.7430346472921185 | 0.7430346473004866 |
| `examples/metta/direct.metta`, Old a | 0.9230240245003262 | 0.923024024755821 |

Review corrections to the first stage-1 commit (`f71e3d67`):

| Expectation | Initial stage 1 | Corrected |
|---|---|---|
| Direct (1,.5), witness (1,.9) tie | first found, often (1,.5) | (1,.9) in either order; no revision |
| Correlated .5/.5 plus independent .4 | .5 with all witnesses in proof/evidence | .5 with only the selected witness's proof/evidence |
| Empty residual | no answer (regression) | U=E, e.g. .9 |

The grouped-view test now counts witness (`OrFormula`) views specifically;
public answers still number two, then three after adding a group.


Stage-2 changes relative to master `8aee6eea`:

| Expectation | Stage 1 | Stage 2 |
|---|---|---|
| `derived_rule` (cold and warm in `test_exists_queries`) | no answer | strength 1, confidence 0.9997000897981131; both source rules in one conditional proof |
| `assuming_exists` (cold and warm) | no answer | (1,1), through the contextual direct claim |
| New composed flood-to-pause judgment | no answer | strength 1, confidence 0.999700089598233; both source rules in one conditional proof |

`tests/metta/test_quantified_judgments.metta` checks the issue #51 chain without
witness facts or a composed rule; alpha renaming and outer sharing; co-reference
traps; missing rules, shift and facility controls; no leaks before/after warm
queries; budget rungs 0–15; late rule addition and withdrawal/replacement;
existential consequents and intermediate claims (general and ground); Assuming;
private simple and compound witnesses; and actual view evidence for uncertain
rules and a shared-source diamond. A stored uncertain quantified axiom still
returns (0.8,0.9) at budgets 0 and 500, rather than revising itself with its own
conditional application. Canonical source slots and dependency-set cycle
exclusions are unchanged.

A private compound witness fold installs the same query-local connective
adapters as a compound goal. They leave through the existing temporary-addition
cleanup and never assert witnesses. In an open implication context, routing
preserves the hypothetical individual's sharing; a fixed other entity cannot
bind it. Ground judgment contexts have no such individual and retain their
intermediate existential folds in the same context.
