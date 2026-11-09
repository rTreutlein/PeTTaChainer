% One declaration per store: physical predicate, overlay policy, MeTTa row type.
% plain stores have no overlay. main borrows MAIN; local starts empty.
% view is a native read-only relation and must never become a mutable space.
% Each row keeps its original first-argument index and constructor layout.

store_schema('&sk_expanded', plain, '(Number SkPattern)').
% expanded fact patterns by a copy of their statement and context, so
% activation finds the ones a new fact or rule conclusion unifies with in one
% match and gets them back uninstantiated
store_schema('&sk_node_terms', plain, '(Statement KBContext SkPattern)').
% ground nodes and fold member nodes reading any proof and value, by a copy of
% their statement and context, under the hash of the statement's longest
% ground prefix, or of its head when it has none, with the node's hash
store_schema('&sk_node_prefix', plain, '(Number Statement KBContext Number SkPattern)').
% open nodes whose rules were started, under the hash of the statement's
% longest ground prefix, or of its head when it has none, with the node's
% hash; and the open nodes each one subsumes, which read its answers instead
% of starting rules (sk-subsumers), by the general node's hash
store_schema('&sk_open_node', plain, '(Number Number SkPattern)').
store_schema('&sk_subsumed', plain, '(Number SkPattern SkPattern)').
store_schema('&sk_answer', plain, '(Number SkPattern SkeletonKey)').
% A root's key answering its node with its population prior, for the
% antecedent completions waiting on it only (sk-start-prior!).
store_schema('&sk_prior_answer', plain, '(Number SkPattern SkeletonKey)').
% Read-only delivery relation for compact native continuation payloads.
% Write and remove through sk-store-wait! / retirement, never add-atom.
store_schema('&sk_wait', view, '(Number SkPattern SkeletonWaiter)').
% child links: owner hash, owner, child, child hash
store_schema('&sk_fact_watch', plain, '(Number Number SkPattern)').
store_schema('&sk_child', plain, '(Number SkPattern SkPattern Number)').
store_schema('&sk_row', plain, '(Number SkeletonKey Number SkeletonRow)').
% Child links, answers and use edges already recorded, by link hash.
store_schema('&sk_link', plain, '(Number)').
% Direct aggregate readers are replayable on eviction, one mark per row.
store_schema('&sk_aggregate_row', plain, '(Number SkeletonKey Number)').
% Join digests leave with their waiter or when their conclusion thaws.
store_schema('&sk_join_link', plain, '(Number Number)').
% member key -> a fold or group key over it
store_schema('&sk_use', plain, '(Number SkeletonKey SkeletonKey)').
% tally fold (a base rate or an implication instance fold) -> a member that
% joined or changed since the fold last took it, by fold hash and member hash
store_schema('&sk_rate_dirty', main, '(Number Number SkeletonKey SkeletonKey)').
store_schema('&sk_instance_tally', main, '(Number SkeletonKey InstanceRegimeState)').
store_schema('&sk_instance_member', main, '(Number Number SkeletonKey Number Number InstanceEvidenceState)').
store_schema('&sk_instance_regime', main, '(Number Number Number)').
% An implication instance fold's digest of its samples, by fold hash
% (sk-instance-digest!).
store_schema('&sk_instance_digest', main, '(Number Number)').
% the signature each member was taken with, by member hash and fold hash
store_schema('&sk_instance_sig', main, '(Number Number Number)').
store_schema('&sk_instance_read', main, '(Number Number Number SkeletonKey)').
% the rules a link's samples leave out (sk-sample-exclusions), by link and
% rule-id epoch
store_schema('&sk_sample_exclusions', plain, '(Number Atom Atom (List Evidence))').
store_schema('&sk_sample_support', main, '(Number Number Atom Atom SourceList Number Number)').
store_schema('&sk_sample_source', main, '(Number Number Atom Atom Number Number)').
store_schema('&sk_branch_support', main, '(Number Atom SupportCounts)').
store_schema('&sk_truth_fold', main, '(Number Number SkeletonKey)').
store_schema('&sk_instance_changed', local, '(Number SkeletonKey)').
% the instance folds an evaluation already brought current, by fold hash
store_schema('&sk_instance_checked', local, '(Number)').
% base-rate cache pattern hash -> a key reading that pattern's entries
store_schema('&sk_rate_readers', main, '(Number SkeletonKey)').
% key -> a row reading it directly, by row key hash and row hash
store_schema('&sk_reader', main, '(Number SkeletonKey Number Number)').
% key -> the fact a forward run stored for it in &kb, with its value's
% evidence and what that value was derived through
store_schema('&sk_forward_stored', plain, '(Number SkeletonKey SkFact EvidenceSet Number)').
% key -> the summary a frozen key keeps in &kb (see forgetting.metta), with
% its value's evidence and the keys within two steps of it
store_schema('&sk_summary', plain, '(Number SkeletonKey SkFact EvidenceSet Number)').
% key with rows -> the last epoch a row was created for it or it was needed
store_schema('&sk_key_epoch', plain, '(Number SkeletonKey Number)').
% frozen keys, until nothing reads them any more and they are buried
store_schema('&sk_frozen', plain, '(Number SkeletonKey)').
% key -> a node it answers, by node hash, kept while forgetting is on so a
% buried key leaves its nodes' answers
store_schema('&sk_answered', plain, '(Number SkeletonKey Number SkPattern)').
% A refined rule's truth goal, per rule id, and the score factor of that
% goal's current value (docs/metta/hypothesis_rules.md).
store_schema('&sk_rule_truth', plain, '(Number Number Statement KBContext)').
store_schema('&sk_truth_factor', main, '(Number Number)').
% key -> a stale row that read it, by row key hash and row hash
store_schema('&sk_stale_reader', main, '(Number SkeletonKey Number Number)').
% fold node -> member node
store_schema('&sk_fold', plain, '(Number SkPattern SkPattern)').
% member node -> fold node
store_schema('&sk_member_of', plain, '(Number SkPattern SkPattern)').
% group key -> its grouped fold node
store_schema('&sk_group_of', plain, '(Number SkeletonKey SkPattern)').
% each row's and fold's latest view, and the views it replaced
store_schema('&sk_latest', main, '(Number SkeletonKey SkeletonVersion)').
store_schema('&sk_view', main, '(Number SkeletonKey Number SkeletonValue)').
store_schema('&sk_summary_reference', local, '(Number SkeletonKey Number (List SkeletonGiven) (List Number) SkeletonFilter SkeletonValue)').
store_schema('&sk_representative', local, '(Number SkeletonKey Number (List SkeletonGiven) (List Number) SkeletonValue)').
% Exclusion-specific row views: row digest -> owner key, row hash, cuts,
% freshness, value. Owner records keep the direct input keys, once per cached row;
% input-key-indexed readers invalidate only cached branches that read it.
store_schema('&sk_branch', main, '(Number SkeletonKey Number (List Number) Bool SkeletonValue)').
store_schema('&sk_branch_owner', main, '(Number Number SkeletonKey Number (List SkeletonKey))').
store_schema('&sk_branch_dirty', main, '(Number)').
store_schema('&sk_branch_reader', main, '(Number SkeletonKey Number)').
store_schema('&sk_branch_wanted', local, '(Number Number SkeletonKey Number (List Number))').
% Only the current rebuild records cuts; a child propagates its completed
% cuts to its parent. Keep the original exclusions beside the cuts: closed
% reads' local pins must not weaken the enclosing rebuild's exclusions.
% Frames leave when the rebuild returns.
store_schema('&sk_branch_cuts', plain, '(Number (List Number) (List Number))').
% every dependency a row's views ever had, by key hash and row hash
store_schema('&sk_support', main, '(Number Number Number)').
store_schema('&sk_merged', main, '(Number SkeletonKey Number SkeletonValue Bool)').
% rows not evaluated yet, and the rows one evaluation scheduled per pass
store_schema('&sk_new', local, '(sk-row-item Number Number SkeletonKey Number SkeletonRow)').
store_schema('&sk_queued', local, '(Number Number Number)').
% fold key hash -> pending change cause (preserved through forced propagation)
store_schema('&sk_fold_pending', local, '(Number Number)').
% exact folds whose latest view is incomplete, by fold key hash
% (docs/metta/partial_folds.md)
store_schema('&sk_partial', main, '(Number SkeletonKey)').
% Fixed input generation and the allowance already attempted.
store_schema('&sk_input_epoch', main, '(KB Number)').
store_schema('&sk_root_exhausted', local, '(Number SkeletonKey SkeletonRootLimit)').
% Work is shared across all exclusion reads of a queried key in one evaluation.
store_schema('&sk_root_spent', local, '(Number SkeletonKey Number)').
store_schema('&sk_given_pending', local, '(Number Number Number)').
store_schema('&sk_given_granted', local, '(Number Number)').
% rows and keys being conditioned, by key and row hash: a read of one inside
% its own conditioning keeps its approximate value
store_schema('&sk_conditioning', local, '(Number Number)').
% keys whose value changed outside evaluation, once each, by key hash
store_schema('&sk_dirty', local, '(Number SkeletonKey)').
% rules and facts added since the last activation
store_schema('&sk_pending_rules', plain, '(sk-pending-rule Number)').
store_schema('&sk_pending_facts', plain, '(sk-pending-fact SkeletonKey)').
% new answers waiting to reach the joins on their node
% by a unique delivery number: nodes may unify, so a delivery is removed by
% its number, never by its pattern
store_schema('&sk_answer_queue', plain, '(Number SkeletonDelivery)').
% deliveries an earlier query left over, by node hash
store_schema('&sk_parked', plain, '(Number Number SkeletonDelivery)').
% joins an answer reached after the row allowance ran out, by owner hash and
% join hash
store_schema('&sk_deferred_joins', plain, '(Number Number SkeletonJoin)').
% rows found after the row allowance ran out, by owner hash and row hash
store_schema('&sk_deferred', plain, '(Number Number (sk-deferred SkPattern Number))').
% rows and waiters created from query-local rules, removed after the query
store_schema('&sk_temp_rows', plain, '(Number SkeletonKey Number SkeletonRow)').
store_schema('&sk_temp_waits', plain, '(Number SkPattern SkeletonWaiter)').
% children linked since the walk last looked, by node hash
store_schema('&sk_fresh', plain, '(Number SkPattern)').
% each expanded or linked node's search score: the best value a join
% waiting on it assigned
store_schema('&sk_score', plain, '(Number SkPattern Number)').
% rows one evaluation must recompute for a change from outside it, with the
% causes that forced them. Evaluation-local native tries deduplicate causes.
store_schema('&sk_forced', local, '(Number Number Number)').
% fact keys that answered a node, by key hash, and by their statement and
% context for structural lookup
store_schema('&sk_keys', plain, '(Number SkeletonKey)').
store_schema('&sk_key_terms', plain, '(Statement KBContext Number)').
% the same keys by statement prefix, as &kb_prefix and &kb_open index &kb:
% every key under each ground prefix hash, keys with variables also under
% the hash of exactly their longest ground prefix
store_schema('&sk_key_prefix', plain, '(Number Statement KBContext Number)').
store_schema('&sk_key_open', plain, '(Number Statement KBContext Number)').
% Private observation readers, including empty reads, subscribe to MAIN.
% Prefix indexes select only readers of the added statement; lookup columns
% are copied apart from the original private key, which must stay open.
store_schema('&sk_world_reader', plain, '(Number SkeletonKey)').
store_schema('&sk_world_prefix', plain, '(Number Statement KB SkeletonKey)').
store_schema('&sk_world_open', plain, '(Number Statement KB SkeletonKey)').
% A borrowed late input can sit beyond the normal shallow stale refresh.
% Its indexed stale cascade remains demand-visible until recomputation pays.
store_schema('&sk_world_changed', plain, '(Number SkeletonKey)').
store_schema('&sk_world_stale', plain, '(Number Number)').
store_schema('&sk_world_done', plain, '(Number Number)').
store_schema('&sk_world_seen', plain, '(Number SkeletonKey)').
% per reading key: the hashes of the keys unifying with it, its own first
store_schema('&sk_unifiers', plain, '(Number SkeletonKey (List Number))').
% reading keys with a cached set, by a copy of their statement and context,
% indexed as keys with variables are in &sk_key_prefix and &sk_key_open
store_schema('&sk_reader_prefix', plain, '(Number Statement KBContext Number SkeletonKey)').
store_schema('&sk_reader_open', plain, '(Number Statement KBContext Number SkeletonKey)').
% (kb pattern) of a fold's compiled member goal, by hash
store_schema('&sk_fold_members', plain, '(Number Atom SkPattern)').
% the current query's roots
store_schema('&sk_roots', plain, '(Number SkPattern)').
% nodes the current walk visited
store_schema('&sk_seen', plain, '(Number SkPattern)').
% keys the current query's roots read, directly or through rows and folds,
% with the fewest such steps from a root
store_schema('&sk_needed', plain, '(Number SkeletonKey Number)').
% rows whose inputs changed while no query needed them, by key and row hash
store_schema('&sk_stale', main, '(Number Number)').
% stale rows the current query needs, recomputed by its evaluation
store_schema('&sk_refresh', local, '(Number Number)').
% rows the evaluation needs that the stale cascade reached while it ran, by
% key and row hash: readers of a fold, computed again, and readers of a key,
% staled once the query has read its answers
store_schema('&sk_restale', local, '(Number Number)').
store_schema('&sk_held', local, '(Number Number SkeletonHold)').
% Exact exclusion contexts held by this evaluation, indexed by branch slot.
store_schema('&sk_branch_hold', local, '(Number Number SkeletonKey Number (List Number))').
store_schema('&sk_thawed', plain, '(Number SkeletonKey)').
% entries by a hash of their knowledge base and pattern
store_schema('&base_rate_cache', main, '(Number BaseRateEntry)').
% Both indexes expose the selective numeric hash as their first generated
% Prolog argument.  Complete keys remain in the payload to reject collisions.
store_schema('&forward_aggregate_identity', main, '(Number ForwardAggregateIdentityRow)').
store_schema('&forward_aggregate_interest_by_trigger', main, '(Number ForwardAggregateInterest)').
store_schema('&forward_aggregate_triggers', main, '(Number ForwardTriggerKey)').
% Numeric state is keyed by the aggregate id; the external constructor
% also carries the exact number of live contributions for drained reads.
store_schema('&forward_aggregate_state', main, '(Number Number Number Number)').
% Per-observation support and its reverse lookup. Query exclusions touch
% only observations reached by excluded keys, never the whole population.
store_schema('&forward_aggregate_observation', main, '(Number ForwardAggregateObservationKey ForwardAggregateObservationValue Number Number SourceList)').
store_schema('&forward_aggregate_read', main, '(Number Number Number)').
% The skeleton fold key each base-rate aggregate is the estimate of: aggregate
% id, fold key hash. A member whose value depends on that key was derived
% through the estimate and does not count in it.
store_schema('&forward_aggregate_fold', main, '(Number Number)').

% Additional plain compiler/runtime stores use the same typed-space loader.
% Ground given rules, by name and KB. A ground implication is knowledge about
% its particular instances, as a fact is: its applications carry a certain
% rule-ev entry, so a view that never applied it cannot stand for one that
% did. A general given rule stays a parameter and carries no entry.
store_schema('&given_rules', plain, '(Proof KB)').
% given rules whose every branch has strength 0 or 1, by name and KB
store_schema('&deterministic_rules', plain, '(Proof KB)').
% Rules stated as a certain equivalence, ((1, 1), (0, 1)), over one
% statement with the conclusion's variables, by their proof name as their
% applications carry it, such as (bi-backward name): the conclusion is the
% premise, so an application of one update is that update
% (sk-prior-update-of). A premise with a variable the conclusion lacks, as in
% (P $x $y) -> (Q $x), is one of many instances, whose population prior is
% not the conclusion's: carrying its update put Q's own inversion under P's
% prior. A rule named no_inverse
% declares its conclusion no observation of its premise, and a refined rule
% holds by its learned truth: neither is one (the conflict benchmark's claims
% run from a source-wide reliability to each claimed node, no_inverse).
store_schema('&equivalence_rules', plain, '(Proof KB)').
% A KB may declare that it stores only the true instances of a predicate
% (logic KBs of Provable, Path or Ancestor facts): its stored instances are
% then no sample of the predicate's population, their rate (1) estimates
% nothing, and an inversion over it would assert every antecedent of every
% stored conclusion. Declared before the rules that would be inverted onto
% it are added.
store_schema('&positive_only_predicates', plain, '(KB Atom)').
% A pattern one of whose conjuncts (or a negated conjunct's statement) has a
% positive-only predicate.
% A KB may declare that a predicate's rules and facts are the only ways one of
% its statements becomes true (docs/metta/complete_predicates.md). Declared
% before knowledge is added.
store_schema('&complete_predicates', plain, '(KB Atom)').
% SWI indexes &kb by a statement's head only, so a lookup by head and
% arguments walked every fact with that head, across the whole history. Each
% fact is therefore also stored in &kb_prefix under the hash of every ground
% prefix of its statement, including nested antecedent heads for implications
% (kb-fact-prefix-hashes), and a fact whose statement
% has variables in &kb_open under the hash of exactly its longest one
% (kb-fact-open-hash), so a lookup reads only the open facts that share
% one of its own prefixes (see kb-facts). The rows follow &kb's: added with the
% same backend, removed with the fact.
store_schema('&kb_prefix', plain, '(Number Statement KBContext Proof TV)').
store_schema('&kb_open', plain, '(Number Statement KBContext Proof TV)').
% A rule premise is indexed by its statement's head (prem_index, which a
% forward run reads) and, unless its head is a variable, in &prem_prefix by the
% longest ground prefix of its statement within its KB, so the rules a ground
% key is a premise of are found by hashing the key's prefixes
% (statement-prefix-hashes) instead of walking every premise with its head.
store_schema('&prem_prefix', plain, '(Number (| Goal (Statement KBContext Proof TV)) Number Number)').
% A certain fact of a ground statement two or more forward rules conclude is
% an outcome the combination modes learn from; it waits for the first merge
% that needs its predicate's mode (docs/metta/combination_modes.md).
store_schema('&combination_pending', plain, '(Number Atom Atom (Statement KBContext Proof TV))').
% Static completion roles belong to the rule, never its joins or rows.
store_schema('&completion_recipe', plain, '(Number CompletionRecipe)').
% An inversion or antecedent completion onto a positive-only predicate reads
% a population prior that only an explicit user rate supplies (#12). Without
% one the row can never conclude, and a live row that never settles would be
% recomputed on every pass. So the row is registered under the rate it reads,
% and is a rule only while that rate is set: set-base-rate adds it and
% clear-base-rate withdraws it (prior-gated-rate-changed!), at a cost of the
% rows reading that rate. A temporary query row is compiled again by the next
% query, so it is only dropped.
store_schema('&prior_gated_rules', plain, '(Number KB Statement Proof KbBackend Atom Atom Atom)').
store_schema('&prior_gated_live', plain, '(Number KB Statement Proof Number)').
% The producers installed with each lifetime (install-producers!); the
% temporary ones leave with the query's temporary rules.
store_schema('&installed_producers', plain, '(Number KbBackend CompiledAddition)').
% Reference answers borrow the latest query batch's proofs. Context cleanup
% may remove every other holder; keep the batch rooted until the next query
% replaces it, without retaining an unbounded history of returned answers.
store_schema('&query_proofs', plain, '(Proof)').
% kb -> its observed predicates.
store_schema('&observed', plain, '(KB Atom)').
% kb -> the new hypotheses one fact may add, and the live ones a consequent
% pattern may have.
store_schema('&hypothesis_mining', plain, '(KB Number Number)').
% kb -> the predicate of its link facts, (link earlier later).
store_schema('&hm_link', plain, '(KB Atom)').
% Time point -> kb, a true link fact it is an end of.
store_schema('&hm_links', plain, '(Atom KB Atom)').
% A fact's features are read from the last `hm-window` true facts recorded
% for each of its constants, newest first: value hash -> kb, value, the
% value's count of recorded facts, global sequence number, statement, its
% time point and layer, with the value's count beside.
store_schema('&hm_recent', plain, '(Number KB Atom Number Number Atom Atom Atom)').
store_schema('&hm_value_count', plain, '(Number KB Atom Number)').
% Observations in the last hm-window distinct time points of each KB.
% A late link can replay those endpoints; older observations leave this index.
% False observations are outcomes too, but never antecedent features.
store_schema('&hm_period', plain, '(Number KB Atom Number Atom Number Atom)').
store_schema('&hm_period_count', plain, '(KB Number)').
store_schema('&hm_period_order', plain, '(Number KB Atom Number)').
% Pattern hash -> kb, consequent pattern, facts of it seen since its first
% hypothesis: the opportunities a hypothesis had since it was born.
store_schema('&hm_outcomes', plain, '(Number KB Atom Number)').
% Consequent hash -> kb, consequent, rule name, antecedent, the
% consequent's count when it was born. Only live hypotheses.
store_schema('&hm_live', plain, '(Number KB Atom Atom Atom Number)').
% Live hypotheses no review has read yet: their first read folds their
% instances and needs budget (hypothesis_review.metta).
store_schema('&hm_unread', plain, '(Atom KB)').
% Implication hash -> kb, implication: tried candidates. Screening can clear
% one when current instance folds no longer support its screen; other drops stay tried.
store_schema('&hm_tried', plain, '(Number KB Atom)').
% Screening key hash -> kb, key, dropped name, implication.
% One reason per screened candidate; reconsideration reads current folds.
store_schema('&hm_screened', plain, '(Number KB SkeletonKey Atom Atom)').
% Only changed screening keys await the next review; repeated changes coalesce.
store_schema('&hm_screen_dirty', plain, '(Number KB SkeletonKey)').
% Implication hash -> kb, implication, the instance and the context of its
% first sighting: singles seen once and not proposed yet.
store_schema('&hm_seen', plain, '(Number KB Atom Number Atom)').
store_schema('&combination_tally', plain, '(Number Atom Atom CombinationTally)').
% A KB's hazard: the prior probability that a sample of a refined rule's
% branch starts a new regime of its rate (docs/metta/hypothesis_rules.md,
% "Regimes"); 0 keeps one regime.
store_schema('&rule_change_hazard', plain, '(KB Number)').
% A rule's inversion into a compound reads the rule's own conclusion as its
% observation, so its views are nothing to that rule's joins reading the
% compound as their premise: they exclude what depends on their conclusion.
% Below a root, expanding a compound node starts the inversion of a rule only
% once something besides that rule's joins reads the node; until then it
% waits here (node hash, inverted rule, node, match), and a later reader, a
% join of another rule (sk-wait-on!) or a query root, starts it (#142).
store_schema('&sk_deferred_inversion', plain, '(Number Atom SkPattern SkeletonMatch)').
% A fold a forward join reads that no search has expanded, other than a base
% rate, whose estimate the cache holds; the run searches it before evaluating.
store_schema('&sk_forward_folds', plain, '(Number SkPattern)').
% The agenda a run leaves, carried to the next run on its knowledge base
% (docs/metta/forward_units.md).
store_schema('&sk_forward_agenda', plain, '(KB Number SkeletonForwardItem)').
% Per key, the value a forward run last built on.
store_schema('&sk_forward_taken', plain, '(Number SkeletonKey SkeletonValue)').

% Run before loading consumers so whole-file type analysis sees the generated
% SpaceOf declarations. PeTTa's ordinary loader owns validation and snapshots.
'declare-stores!'(true) :-
    findall(Source,
            ( store_schema(Space,Policy,Text),
              format(string(Type), '(: ~w (SpaceOf ~w))', [Space,Text]),
              ( memberchk(Policy,[main,local])
              -> atom_concat('&',Name,Space),
                 format(string(Read), '(: &ctx_~w (SpaceOf ~w))', [Name,Text])
              ; Read="" ),
              ( Policy == view -> Bind=""
              ; format(string(Bind), '!(bind! ~w (new-space))', [Space]) ),
              atomics_to_string([Type,Read,Bind], "\n", Source) ), Sources),
    atomics_to_string(Sources, "\n", Source),
    process_metta_string(Source, _, '&self').
