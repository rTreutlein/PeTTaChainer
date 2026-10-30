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
store_schema('&sk_deferred', plain, '(Number Number (sk-deferred SkPattern Number SkFact (List SkPattern) (List SkeletonKey)))').
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
