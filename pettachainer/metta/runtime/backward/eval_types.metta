;; Evaluator datatypes. Loaded before their users.

;; --- Values -----------------------------------------------------------------

;; A view as updates of a prior: an inversion or an antecedent completion, or
;; a factored merge of several, updates its prior; any other view is its own
;; prior, updated by nothing. A rule of `$kb` stated as a certain equivalence,
;; ((1, 1), (0, 1)), applied to one update is that update over the same prior:
;; its conclusion is its premise (equivalence-rule?). So the bi-backward
;; application of an inversion over Problem updates (Or L D) by the alarm's
;; likelihood ratio, as it updates Problem (test_or_inversion_conditioned_merge:
;; 0.907, not the 0.520 a revision with the parts' prior gave; the atom case
;; was revised on master too).
(datatype SkeletonPriorUpdate (sk-prior-update Proof Proof (List Proof)))

;; Registered as truth rows are built, rather than walking all producer rows
;; at every sensor read. Ambiguous producer folds cannot certify independence.
(datatype RuleFold (rule-fold SkeletonKey) no-rule-fold ambiguous-rule-fold)

(datatype SkeletonReadPolicy
   sk-greedy-read
   sk-facts-read
   sk-representative-read
   sk-independent-read
   sk-reference-read)

(datatype SkeletonRowState
   ;; fold proofs (newest first), evidence, dependency hashes
   (sk-acc (List Proof) EvidenceSet (List Number))
   sk-fail
   ;; A premise had values, all overlapping the evidence the row already used:
   ;; shared fact statements, and one more than the clashing dependency count,
   ;; the rows one conditioned branch evaluates at most.
   (sk-clash (List SkeletonKey) Number)
   ;; Shared uncertain statements, one more than their dependency count,
   ;; the row read as independent, and its approximate value.
   (sk-entangled (List SkeletonKey) Number SkeletonRowState))

(datatype CompletionInputs no-completion-inputs (completion-inputs SkeletonKey (List SkPattern) SkFact (List SkPattern) Bool))

(datatype LikelihoodContext (likelihood-context (List Number) EvidenceSet))

;; --- Learned combination modes (docs/metta/combination_modes.md) -------------

;; Per consequent predicate: the outcomes counted, their sum, and the log score
;; of each mode on the outcomes several disjoint forward views met on.
(datatype CombinationTally (combination-tally Number Number Number Number Number))

;; --- Overlapping views (docs/metta/overlap_conditioning.md) ------------------

;; A statement both views depend on, with the size of its dependency set,
;; negated so the largest sorts first, that set, its spread: the largest
;; variance s (1 - s) of its facts' and views' strengths, and whether stored
;; facts supply its probability.
(datatype SkeletonShared (sk-shared-key Number SkeletonKey Number Number Bool))
;; A statement to condition on with its expected impact, negated so the
;; largest sorts first.
(datatype SkeletonRanked (sk-ranked Number SkeletonKey))

;; A fold over a key's values: merge so far, and the first overlap's
;; statements and dependencies.
(datatype SkeletonMerging (sk-merging SkeletonValue (List SkeletonKey) Number))

(datatype SkeletonDigest (sk-digest Number Number))

;; Reference classes are compared before any views are combined. Otherwise
;; a learned combination can hide a contained condition.
(datatype ReferenceClass
   no-class
   (sk-class Bool (List Atom))
   (sk-mixture-class (List Atom))
   (sk-combined-class (List Atom)))
(datatype SkeletonReference (sk-reference ReferenceClass SkeletonValue))

(datatype ClassCentre (class-centre Number Number Number (List Proof) EvidenceSet Number))

(datatype SkeletonClassGroup (sk-class-group ReferenceClass (List SkeletonValue)))

(datatype SkeletonSampleView (sk-sample-view (List SkeletonDigest) SkeletonValue))
(datatype SkeletonSampleGrouping (sk-sample-grouping (List SkeletonDigest) SkeletonValue (List SkeletonSampleView)))

;; An unpaid overlap must not discard evidence independent of it. Keep the
;; full dependencies and evidence of each connected component, including its
;; dominated views, and merge its pairs by sk-dependent-merge.
;; Shared rule truths, population priors and given premises do not connect
;; components, just as they do not make the pairwise merge dependent.
;; Direct views and prior updates (inversions, completions) form components
;; apart: an update applies to the merge of the direct views it shares
;; statements with, by the same pair rule: over deeper shared statements it
;; updates them; a near-shared update competes with them by count while its
;; claim waits.
(datatype SkeletonComponent (sk-component SkeletonValue Number EvidenceSet (List SkeletonValue)))
(datatype SkeletonConnecting (sk-connecting SkeletonComponent (List SkeletonComponent)))

(datatype SkeletonComponentOrder (sk-component-order Number SkeletonValue))

;; A member's sample: its segment in each branch and its contribution.
(datatype InstanceSample (instance-sample Number Number InstanceEvidenceState))

;; --- Folds ------------------------------------------------------------------

(datatype SkeletonFold
   ;; accumulator, member proofs (newest first), evidence, dependency hashes
   (sk-fold-state Atom (List Proof) (List EvidenceSet) (List Number)))

(datatype SkeletonExistentialFold (sk-exists-state STVType SkeletonValue Bool (List Proof) EvidenceSet (List Number)))

;; A fold's digest sums a signature of each member's sample: the observation
;; of its consequent, the facts of the sample's evidence other than its
;; antecedent's stored facts, and the antecedent's strength, the share of the
;; sample's mass in the positive branch (to six places, so the confidence the
;; consequent is read with does not part samples of one observation). Two
;; folds have equal digests when their samples weigh the same instances alike
;; and observe them through the same facts, whatever statement each sample
;; reads as its consequent: a consequent a deterministic rule derives from a
;; stored outcome observes that outcome (sk-sample-twins?). A member that is
;; no sample adds nothing. The signature a member was taken with is kept, so a
;; changed member replaces its own.
(datatype SkeletonSampleSig (sk-sample-sig Number Number))

;; covered members, members still to come
(datatype SkeletonCover (sk-cover Number Number))

(datatype SkeletonGroup (sk-group-found SkPattern (List SkeletonKey)) sk-group-missing)

;; What conditioning evaluates: a row (exclusions, key hash, key, row hash,
;; row) or a key's merge (hash, key, reader's filter and exclusions).
(datatype SkeletonTarget
   (sk-row-target (List Number) Number SkeletonKey Number SkeletonRow)
   (sk-key-target Number SkeletonKey SkeletonFilter (List Number)))

(datatype TokenReplacement (token-state Atom (List Proof)))

;; this pass's remaining items and the next pass's, by their order
(datatype SkeletonWork (sk-work (Heap SkeletonItem) (Heap SkeletonItem)))

;; What changed for a key's readers: a new row view with its dependencies,
;; the same with the key's open merged value unchanged and the dependencies of
;; that value before and after, or a change from outside the rows (a fact, a
;; removed query-local row, fold members), with the dependencies of the new
;; view. View-only notifications retain incoming causes too: a proof-only
;; refresh does not force ordinary readers, but must not start a fresh cause
;; if it reaches a fold. Empty causes identify an unforced supported change.
(datatype SkeletonChange
   (sk-view-change Number (List Number))
   (sk-value-same Number Number (List Number))
   (sk-outside-change (List Number) Number))

;; A key is needed at the fewest steps from a root it is reached by. The keys
;; are visited breadth first, a level of keys one step further than the last
;; at a time, so each is reached first at that depth and visited once: a
;; deeper visit first, then a closer one passing the smaller depth on, walked
;; a chain of inverted rules once per key below it (ChainerGame
;; benchmarks/ona/repros/term_growing_rule.metta: 90% of the query).
;;
;; The members a base-rate or instance fold has yet to take are visited after
;; every key reached otherwise, one level past the deepest. Such a fold
;; estimates a population, so a member moves what its readers read by one
;; member's share, and a member reached otherwise keeps the depth of that
;; path: a fold one step from a root otherwise puts its whole population,
;; every past observation of the pattern, two steps from it, where its rows
;; take the allowance before the rows of the paths the roots read through
;; (SupplyNet stage 2 b100 s2: the history rows reading the base rate took the
;; allowance from the periods nearest the present, error 0 to 0.0004).
;; keys one level further, members of statistical folds
(datatype SkeletonNeed (sk-need-next (List SkeletonKey) (List SkeletonKey)))

;; Waiting targets get turns nearest a root first, then by estimated cost,
;; then oldest. Actual conditioned rows spend the remaining allowance as
;; they run; no estimate gates admission. Each target gets at most one
;; ordinary turn per evaluation, and an exhausted target stays pending.
(datatype SkeletonWaiting (sk-row-waiting SkeletonItem) (sk-key-waiting Number SkeletonKey))
(datatype SkeletonClaim (sk-claim Number Number Number SkeletonWaiting))

(datatype BackwardQueryMetric (query-metric Atom Number))

;; Nominal capabilities keep reads lazy across the compiler specialization boundary.
(datatype SkeletonValueReader (sk-value-reader (-[semidet]-> SkeletonKey SkeletonFilter (List Number) SkeletonValue)))
(datatype SkeletonModeReader (sk-mode-reader (-[semidet]-> KB Statement Atom)))
(datatype SkeletonRowReader (sk-row-reader (-[semidet]-> (List SkeletonGiven) (List Number) Number SkeletonKey Number SkeletonRow SkeletonValue)))
(datatype SkeletonPremiseReader (sk-premise-reader (-[semidet]-> (List SkeletonGiven) (List SkeletonGiven) (List Number) Bool Bool SkeletonReadPolicy SkeletonRowState SkPattern SkeletonRowState)))
