:- ensure_loaded('../core/runtime_terms').
% Physical inference state: indexed rows, identities, proof/evidence lifetime,
% pending-search ownership and scalar instrumentation. No search expansion or evaluator.
% Rank claims by depth, cost and age, then their pending enumeration sequence.
% Never compare the payload: its hashes include the process's random KB id.
'sk-order-claims'(Claims, Sorted) :-
    findall([Depth,Cost,Age,Sequence]-Claim,
        ( nth0(Sequence,Claims,Claim), Claim=['sk-claim',Depth,Cost,Age,_] ), Pairs),
    keysort(Pairs, Ranked), pairs_values(Ranked, Sorted).

% Membership is evaluation-local and unordered. The pending journal still
% preserves first-arrival order; MAIN and every assumption own distinct tries.
'sk-force-causes!'(Key, Row, Causes, []) :-
    ( context_active(C) -> true ; C=main ),
    ( sk_forced_seen(C,Trie) -> true
    ; trie_new(Trie), assertz(sk_forced_seen(C,Trie)) ),
    forall(member(Cause,Causes),
        ( trie_insert(Trie,forced(Key,Row,Cause))
        -> 'context-add!'('&sk_forced',[Key,Row,Cause],true)
        ; true )).

% PeTTa arrows have one result position. Package SWI's three relational
% get_from_heap/4 outputs into one positional product.
heap_pop(Heap, [Priority, Value, Rest]) :-
    get_from_heap(Heap, Priority, Value, Rest).

% Test before popping, so a caller can pop without collecting the result: a
% collected pop copies the whole remaining heap.
'heap-empty?'(Heap, Empty) :-
    (   empty_heap(Heap) -> Empty = true ; Empty = false ).

% A statically imported rule dump stores its rule ids without advancing the
% live counter, so the counter's next id may already be taken: a new live rule
% then takes the id past every stored live one. Temp ids start at 10^9.
'fresh-rule-id'(Next, Id) :-
    (   catch(rules('runtime-rule-row', Next, _, _), error(existence_error(procedure, _), _), fail)
    ->  aggregate_all(max(I), (rules('runtime-rule-row', I, _, _), I < 1000000000), Max),
        Id is Max + 1
    ;   Id = Next
    ).

% Whether a rule's hazard may have changed since the last evaluation: a head
% gained or lost a stage position (prolog/sorts.pl), or a KB's rule-change
% hazard was set. The evaluation then brings every standing instance tally to
% its rule's hazard (sk-rehazard-tallies!).
:- dynamic hazards_changed/0.
'hazards-changed!'(true) :- ( hazards_changed -> true ; assertz(hazards_changed) ).
'take-hazards-changed'(Result) :- ( retract(hazards_changed) -> Result = true ; Result = false ).

% A term with the constant arguments of its atoms replaced by variables, one
% per constant, so the samples of one link share one pattern; heads and
% numbers stay.
'generalize-constants'(Term, General) :-
    generalize_constants(Term, General, [], _).

generalize_constants(Term, Term, Seen, Seen) :- var(Term), !.
generalize_constants([Head|Args], [Head|GArgs], Seen0, Seen) :- atom(Head), !,
    foldl(generalize_argument, Args, GArgs, Seen0, Seen).
generalize_constants(Terms, General, Seen0, Seen) :- is_list(Terms), !,
    foldl(generalize_constants, Terms, General, Seen0, Seen).
generalize_constants(Term, Term, Seen, Seen).

generalize_argument(Arg, General, Seen0, Seen) :-
    (   atom(Arg)
    ->  ( memberchk(Arg-Var, Seen0) -> General = Var, Seen = Seen0 ; Seen = [Arg-General|Seen0] )
    ;   generalize_constants(Arg, General, Seen0, Seen) ).

% Outer arguments cannot be filled with a binder's private slots.
'existential-outer-values?'(Values, Valid) :-
    ( sub_term(Term, Values), is_list(Term), Term = [Head, _], Head == 'exists-slot'
    -> Valid = false ; Valid = true ).

% A final tie uses alpha-normalized statement keys, not allocation/proof ids.
'existential-key-before?'(A, B, Before) :-
    copy_term(A, CA), numbervars(CA, 0, _),
    copy_term(B, CB), numbervars(CB, 0, _),
    ( CA @< CB -> Before = true ; Before = false ).

% Pure row classification stays opaque to PeTTa's CPU argument specialization.
% A reference cannot certify an endpoint without a Bayes update. Unknown goal
% heads/functions remain eligible; this test never binds the stored template.
'sk-row-has-bayes?'(Hash, Key, Rhash, Has) :-
    ( user:'&sk_row'(Hash, Stored, Rhash, ['sk-row', _, _, Premises, _]), Stored =@= Key,
      member(Premise, Premises),
      ( var(Premise)
      ; Premise=[Tag, Fun|_], (var(Tag) ; Tag=='CPU', (var(Fun) ; Fun=='CTVBayesFormula')) )
    -> Has=true ; Has=false ).

% Hash sets (exclusion lists, unifier sets) are SWI ordered sets of key
% hashes, so union and membership are linear merges over short lists.
'hash-set'(Hashes, Set) :- sort(Hashes, Set).
'hash-union'(Left, Right, Set) :- ord_union(Left, Right, Set).
'hash-subset?'(Left, Right, Result) :- ( ord_subset(Left, Right) -> Result = true ; Result = false ).
'hash-intersection'(Left, Right, Both) :- ord_intersection(Left, Right, Both).

% A value's dependency set is an interned node id, so a value stays one
% integer however long the derivation behind it (docs/metta/
% dependency_tracking_design.md). 0 is the empty set; a key is a leaf; a union
% is a node over its operands' ids, interned by that sorted list. Nodes never
% change, so an id names one set forever. Each node keeps a bitmask of its
% keys' hashes, the OR of its children's, so a membership walk skips every
% child whose mask lacks the key's bit.
:- dynamic deps_leaf/2, deps_node/4, deps_size_memo/2, deps_cut/2.

% A frozen key's views stand for its summary (forgetting.metta): a node cut
% to another is walked as that one, so what a value read before the key was
% frozen depends on the key's window, not its whole past.
'deps-cut!'(Ids, Replacement, true) :-
    forall(( member(Id, Ids), deps_node(Id, _, _, _), \+ deps_cut(Id, _), Id \== Replacement ),
           assertz(deps_cut(Id, Replacement))).
% Drops every dependency node no live value reaches. Roots are the sets the
% stores hold; marking follows cuts; a dropped key leaf is interned anew when
% a key is read again.
'deps-gc!'(Roots, true) :-
    empty_nb_set(Live),
    forall(member(Root, Roots), deps_mark(Root, Live)),
    forall(proof_metadata(_, _, _, _, _, Deps, _, _, _, _), deps_mark(Deps, Live)),
    size_nb_set(Live, Kept), flag(deps_gc_kept, _, Kept),
    length(Roots, Read), flag(deps_gc_roots, _, Read),
    flag(deps_next_id, Next, Next), flag(deps_gc_next, _, Next),
    forall(( member(Head, [deps_node(Id, _, _, _), deps_cut(Id, _), deps_size_memo(Id, _), deps_leaf(Id, _)]),
             clause(Head, true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)).
% A collection is due once more ids were interned since the last one than it
% kept and roots it read (at least 4096), so its cost, a walk of the stores
% that hold the roots and of the ids, stays proportional to what was interned.
'deps-gc-due?'(Result) :-
    flag(deps_next_id, Next, Next), flag(deps_gc_next, Last, Last), flag(deps_gc_kept, Kept, Kept),
    flag(deps_gc_roots, Read, Read),
    (   Next - Last > max(Kept + Read, 4096) -> Result = true ; Result = false ).

% Stored proofs and evidence sets nothing refers to are collected in cycles
% spread over queries (docs/metta/evidence_sets.md, "Collection"). A cycle
% keeps what the stores reached when it started and everything created since:
% it scans the holder columns, follows each marked proof to the proofs and
% evidence sets it holds, then sweeps the proof store, the memoized unions
% and the evidence sets, unions first: a union kept while its result is gone
% would hand the erased set to a later query. A slice does a bounded number
% of these units, so a
% query pays for a share of a collection, never for the whole store. Two
% barriers keep a reachable value from being lost meanwhile: a holder row
% removed while marking runs is scanned as it goes, and an interned evidence
% set found again is marked until the cycle ends. Stored proofs are found
% only through references, so one nothing reached cannot be reached again.

% The spaces whose rows can hold a proof reference or an evidence set, their
% arity, and the columns that can. A fact stored in &kb with a referenced
% proof is held by &sk_forward_stored (a forward run's copy) or by
% &materialized_facts as well.
refs_holder('&sk_latest', 3, [3]).
refs_holder('&sk_view', 4, [4]).
refs_holder('&sk_representative', 6, [6]).
refs_holder('&sk_summary_reference', 7, [6, 7]).
refs_holder('&sk_branch', 6, [6]).
refs_holder('&sk_merged', 5, [4]).
refs_holder('&sk_forward_taken', 3, [3]).
refs_holder('&sk_forward_stored', 5, [3, 4]).
refs_holder('&sk_summary', 5, [3, 4]).
refs_holder('&materialized_facts', 6, [5, 6]).
refs_holder('&forward_aggregate_observation', 6, [3]).
refs_holder('&combination_pending', 4, [4]).
refs_holder('&query_proofs', 1, [1]).
refs_holder(proof_template, 4, [2, 3, 4]).
refs_holder(context_entry, 5, [4]).
refs_holder(context_hidden, 5, [4]).
refs_holder(context_propagated, 4, [4]).

:- dynamic refs_gc_proof/1, refs_gc_set/1, refs_gc_grey/1, refs_gc_rule/1, refs_gc_rule_grey/1.

% The cycle's phase is idle, roots(Holders), mark, or sweep(Stores); its
% limits are the first proof id and the first evidence set id it did not see
% exist; its work is the clause references of the store being scanned or
% swept, the next one to take in flag refs_gc_next.
refs_gc_active :- nb_current(refs_gc_phase, Phase), Phase \== idle.

% A collection is due once the garbage expected among the proofs, or proof
% words, stored since the last one exceeds what it kept and the holder rows it
% scanned (at least 4096). The garbage expected is the share of them the last
% cycle collected (all before the first), at least 1/16, so garbage stays
% bounded by the live store while a store that keeps nearly all it holds is
% not scanned again and again. Exact-fold proofs grow with their members, so
% counting only proofs retained large histories. A cycle's work is those rows
% and proofs, so each stored proof pays a constant share of it however long
% the history: holder rows grow with the keys, one per decision in Pong,
% while the proofs kept need not.
refs_gc_due :-
    (   refs_gc_active -> true
    ;   'search-id-value'(proof_id, Next), flag(refs_gc_last, Last, Last), flag(refs_gc_kept, Kept, Kept),
        flag(refs_gc_rows, Rows, Rows),
        flag(withdraw_epoch, Epoch, Epoch), flag(refs_gc_retired_last, RetiredLast, RetiredLast),
        flag(refs_gc_words, Words, Words), flag(refs_gc_words_last, LastWords, LastWords),
        flag(refs_gc_words_kept, KeptWords, KeptWords),
        flag(refs_gc_retained, Retained, Retained), flag(refs_gc_words_retained, RetainedWords, RetainedWords),
        ( (Next - Last) * max(1 - Retained, 0.0625) > max(Kept + Rows, 4096)
        ; (Words - LastWords) * max(1 - RetainedWords, 0.0625) > max(KeptWords + Rows, 4096)
        ; Epoch - RetiredLast > 512 ) ).

% One slice, starting a cycle when one is due. Its units grow with the proofs
% stored, their size and rules retired since the last slice, so a cycle ends before as many again are
% stored, and a query that stores none pays a small constant.
'stored-refs-gc-step!'(true) :-
    'search-id-value'(proof_id, Next), flag(refs_gc_seen, Seen, Next),
    flag(withdraw_epoch, Epoch, Epoch), flag(refs_gc_retire_seen, RetiredSeen, Epoch),
    flag(refs_gc_words, Words, Words), flag(refs_gc_words_seen, SeenWords, Words),
    (   refs_gc_due
    ->  ( refs_gc_active -> true ; refs_gc_start ),
        Units is 512 + 8 * (max(0, Next - Seen) + max(0, Epoch - RetiredSeen) + max(0, Words - SeenWords) // 32),
        refs_gc_run(Units)
    ;   true ).

% A whole collection now: the running cycle is finished, then one that starts
% now collects everything nothing reaches.
'stored-refs-gc!'(true) :-
    ( refs_gc_active -> refs_gc_run(inf) ; true ),
    refs_gc_start, refs_gc_run(inf).

refs_gc_start :-
    flag(refs_gc_words, Words, Words), nb_setval(refs_gc_word_limit, Words),
    flag(refs_gc_marked_words, _, 0),
    'search-id-value'(proof_id, ProofLimit), flag(ev_next_set, Sets, Sets), SetLimit is Sets + 1,
    nb_setval(refs_gc_limits, limits(ProofLimit, SetLimit)),
    retractall(refs_gc_proof(_)), retractall(refs_gc_set(_)), retractall(refs_gc_grey(_)),
    retractall(refs_gc_rule(_)), retractall(refs_gc_rule_grey(_)),
    flag(rule_set_next, Rules, Rules), RuleLimit is Rules + 1, nb_setval(refs_gc_rule_limit, RuleLimit),
    flag(withdraw_epoch, Epoch, Epoch), nb_setval(refs_gc_retire_floor, Epoch),
    nb_setval(refs_gc_retire_epoch, Epoch),
    findall(holder(Head, Columns),
            ( refs_holder(Space, Arity, Columns), current_predicate(user:Space/Arity), functor(Head, Space, Arity) ),
            Holders),
    forall(member(holder(Head, Columns), Holders), prolog_listen(user:Head, refs_gc_removed(Columns))),
    aggregate_all(sum(N), ( member(holder(Head, _), Holders), predicate_property(user:Head, number_of_clauses(N)) ), Rows),
    flag(refs_gc_rows, _, Rows),
    nb_setval(refs_gc_holders, Holders),
    nb_setval(refs_gc_phase, roots(Holders)),
    refs_gc_take(none).

refs_gc_removed(Columns, retract, Ref) :- !,
    (   clause(Head, true, Ref) -> refs_gc_mark_columns(Columns, Head) ; true ).
refs_gc_removed(_, _, _).

refs_gc_mark_columns(Columns, Row) :-
    forall(member(Column, Columns), ( arg(Column, Row, Value), refs_gc_mark_term(Value) )).

refs_gc_mark_term(Term) :-
    forall(( sub_term(Sub, Term), nonvar(Sub), Sub = [Tag, Id], atom(Tag), integer(Id) ), refs_gc_mark(Tag, Id)).

refs_gc_mark('proof-ref', Pid) :- !,
    nb_getval(refs_gc_limits, limits(ProofLimit, _)),
    (   Pid < ProofLimit, \+ refs_gc_proof(Pid) -> assertz(refs_gc_proof(Pid)), assertz(refs_gc_grey(Pid)) ; true ).
refs_gc_mark('ev-set', Set) :- !, refs_gc_mark_set(Set).
refs_gc_mark(_, _).

refs_gc_mark_set(Set) :-
    nb_getval(refs_gc_limits, limits(_, SetLimit)),
    (   Set > 0, Set < SetLimit, \+ refs_gc_set(Set) -> assertz(refs_gc_set(Set)) ; true ).

% An evidence set found again by its entries or a memoized union.
refs_gc_touch_set(Set) :- ( refs_gc_active -> refs_gc_mark_set(Set) ; true ).

% The work of the next store: its clause references, taken in order.
refs_gc_take(Refs) :-
    (   Refs == none -> Work = none ; Work =.. [refs|Refs] ),
    nb_setval(refs_gc_work, Work), flag(refs_gc_next, _, 1).

refs_gc_run(Units) :-
    (   ( Units == 0 ; \+ refs_gc_active ) -> true
    ;   nb_getval(refs_gc_phase, Phase), refs_gc_units(Phase, Units, Left), refs_gc_run(Left) ).

% Units of each phase: a holder row scanned, a marked proof followed, a stored
% proof, set or memoized union swept.
refs_gc_units(roots([]), Units, Units) :- nb_setval(refs_gc_phase, mark).
refs_gc_units(roots([holder(Head, Columns)|Rest]), Units, Left) :-
    refs_gc_through(roots(Rest), Head, Units, Left, Ref,
        ( clause(Head, true, Ref) -> refs_gc_mark_columns(Columns, Head) ; true )).
refs_gc_units(mark, Units, Left) :-
    (   refs_gc_grey(_) -> refs_gc_follow_loop(Units, Left)
    ;   nb_getval(refs_gc_holders, Holders),
        forall(member(holder(Head, Columns), Holders), prolog_unlisten(user:Head, refs_gc_removed(Columns))),
        nb_setval(refs_gc_phase, sweep([proofs, unions, sets])), Left = Units ).
refs_gc_units(sweep([]), Units, Units) :- nb_setval(refs_gc_phase, rule_memos).
refs_gc_units(sweep([Store|Stores]), Units, Left) :-
    nb_getval(refs_gc_limits, limits(ProofLimit, SetLimit)),
    refs_gc_store(Store, Head),
    refs_gc_through(sweep(Stores), Head, Units, Left, Ref,
        ( clause(Head, true, Ref), refs_gc_dead(Store, Head, ProofLimit, SetLimit) -> refs_gc_erase(Store, Head, Ref) ; true )).

% Provenance collection shares the same unit budget as proof/evidence GC.
% Each root, tree node and swept entry consumes one unit. Proof cache entries
% and summary users leave in refs_gc_erase, not in a second orphan-proof scan.
refs_gc_units(rule_memos, Units, Left) :-
    refs_gc_through(rule_roots([proofs, summaries, stores]), summary_rules(Hash, Epoch, _), Units, Left, Ref,
        ( clause(summary_rules(Hash, Epoch, _), true, Ref),
          \+ user:'&sk_summary'(Hash, _, [_, _, [forgotten, Hash, Epoch], _], _, _),
          \+ summary_ref(Hash, Epoch, _) -> erase(Ref) ; true )).
refs_gc_units(rule_roots([]), Units, Units) :- nb_setval(refs_gc_phase, rule_mark).
refs_gc_units(rule_roots([Store|Stores]), Units, Left) :-
    rule_gc_root(Store, Head, Set),
    refs_gc_through(rule_roots(Stores), Head, Units, Left, Ref,
        ( clause(Head, true, Ref) -> refs_gc_mark_rule(Set) ; true )).
refs_gc_units(rule_mark, Units, Left) :-
    ( refs_gc_follow_rules(Units, Left) -> true
    ; nb_setval(refs_gc_phase, rule_sweep([sets, unions, retirements, marks])), Left = Units ).
refs_gc_units(rule_sweep([]), Units, Units) :- refs_gc_finish.
refs_gc_units(rule_sweep([Store|Stores]), Units, Left) :-
    ( refs_gc_follow_rules(Units, Left) -> true
    ; rule_gc_store(Store, Head),
      refs_gc_through(rule_sweep(Stores), Head, Units, Left, Ref,
          ( clause(Head, true, Ref), rule_gc_dead(Store, Head) -> rule_gc_erase(Store, Head, Ref) ; true )) ).

rule_gc_root(proofs, proof_rules_memo(_, Set), Set).
rule_gc_root(summaries, summary_rules(_, _, Set), Set).
rule_gc_root(stores, stored_rules(_, _, _, _, Set), Set).
rule_gc_store(sets, rule_set(_, _, _, _, _)).
rule_gc_store(unions, rule_union(_, _, _)).
rule_gc_store(retirements, retired_epoch(_, _)).
rule_gc_store(marks, refs_gc_rule(_)).

refs_gc_mark_rule(0) :- !.
refs_gc_mark_rule(Set) :-
    ( refs_gc_rule(Set) -> true
    ; assertz(refs_gc_rule(Set)), assertz(refs_gc_rule_grey(Set)) ).
refs_gc_follow_rules(Units, Left) :-
    refs_gc_rule_grey(_), !,
    ( Units == 0 -> Left = 0
    ; retract(refs_gc_rule_grey(Set)),
      ( rule_set(Set, Kind, Children, _, Count)
      -> forall(member(Child, Children), refs_gc_mark_rule(Child)),
         % A long-unread set can use its leaves instead of older events.
         ( Kind = leaf(_) -> true
         ; ( proof_live_memo(Set, Checked, Live) -> true ; Checked = 0, Live = true ),
           ( Live == false -> true
           ; nb_getval(refs_gc_retire_epoch, Epoch), Floor is max(Checked, Epoch - Count),
             nb_getval(refs_gc_retire_floor, Previous), NextFloor is min(Previous, Floor),
             nb_setval(refs_gc_retire_floor, NextFloor) ))
      ; true ),
      ( Units == inf -> Next = inf ; Next is Units - 1 ),
      ( refs_gc_follow_rules(Next, Left) -> true ; Left = Next ) ).

rule_gc_live(Set) :-
    ( Set =:= 0 ; nb_getval(refs_gc_rule_limit, Limit), Set >= Limit ; refs_gc_rule(Set) ), !.
rule_gc_dead(marks, refs_gc_rule(_)).
rule_gc_dead(sets, rule_set(Set, _, _, _, _)) :- \+ rule_gc_live(Set).
rule_gc_dead(unions, rule_union(A, B, Set)) :-
    \+ ( rule_gc_live(A), rule_gc_live(B), rule_gc_live(Set) ).
% An event for an identity in no surviving set is unnecessary too. A later
% cold proof builds its leaf with current indexed retirement status. Such
% holes need not force existing sets to use a full leaf check.
rule_gc_dead(retirements, retired_epoch(Epoch, Rule)) :-
    ( nb_getval(refs_gc_retire_floor, Floor), Epoch =< Floor ; \+ rule_leaf(Rule, _) ).
rule_gc_erase(sets, rule_set(Set, Kind, Children, _, _), Ref) :- !,
    erase(Ref),
    forall(member(Child, Children), retractall(rule_parent(Child, Set))),
    ( Kind = leaf(Rule) -> retractall(rule_leaf(Rule, Set))
    ; Kind = branch(Bit, _), Children = [Left, Right], term_hash([Bit, Left, Right], Hash),
      retractall(rule_branch(Hash, Bit, Left, Right, Set)) ),
    retractall(proof_live_memo(Set, _, _)).
rule_gc_erase(retirements, retired_epoch(Epoch, _), Ref) :- !,
    erase(Ref), nb_getval(refs_gc_retire_floor, Floor),
    ( Epoch =< Floor -> flag(rule_retired_floor, Old, max(Old, Epoch)) ; true ).
rule_gc_erase(_, _, Ref) :- erase(Ref).

% Takes a store's clause references when its turn comes, runs Goal on at most
% Units of them, and moves on to the phase after once all were taken.
refs_gc_through(After, Head, Units, Left, Ref, Goal) :-
    nb_getval(refs_gc_work, Work0),
    (   Work0 == none -> findall(R, clause(Head, true, R), Refs), refs_gc_take(Refs), nb_getval(refs_gc_work, Work)
    ;   Work = Work0 ),
    functor(Work, _, Size), flag(refs_gc_next, First, First),
    (   Units == inf -> Last = Size ; Last is min(Size, First + Units - 1) ),
    forall(between(First, Last, I), ( arg(I, Work, Ref), \+ \+ Goal )),
    Next is Last + 1, flag(refs_gc_next, _, Next),
    (   Units == inf -> Left = inf ; Left is Units - (Last - First + 1) ),
    (   Next > Size -> nb_setval(refs_gc_phase, After), refs_gc_take(none) ; true ).

% Metadata marking and removal are physical proof-lifetime operations.
proof_metadata_mark(Pid) :-
    ( proof_metadata(Pid, Role, _, Semantic, Given, Deps, Zero, Sources, Representative, Observed)
    -> refs_gc_mark_term(Semantic), refs_gc_mark_term(Role), refs_gc_mark_set(Given),
       term_size(metadata(Role, Semantic, Given, Deps, Zero, Sources, Representative, Observed), Words),
       flag(refs_gc_marked_words, Before, Before+Words)
    ; true ).
proof_metadata_erase(Pid) :-
    retractall(proof_metadata(Pid, _, _, _, _, _, _, _, _, _)),
    retractall(user:'&proof_fact'(Pid, _, _)).

% Follows marked proofs to what they hold.
refs_gc_follow_loop(Units, Left) :-
    (   Units == 0 -> Left = 0
    ;   retract(refs_gc_grey(Pid))
    ->  (   user:'&proof'(Pid, Stored, Leaves, _)
        ->  term_size(Stored, Size), flag(refs_gc_marked_words, Marked, Marked + Size),
            refs_gc_mark_term(Stored), refs_gc_mark_term(Leaves),
            proof_metadata_mark(Pid)
        ;   true ),
        (   Units == inf -> Next = inf ; Next is Units - 1 ),
        refs_gc_follow_loop(Next, Left)
    ;   Left = Units ).

refs_gc_store(proofs, user:'&proof'(_, _, _, _)).
refs_gc_store(sets, ev_set(_, _, _, _, _)).
refs_gc_store(unions, ev_union_memo(_, _)).

refs_gc_dead(proofs, user:'&proof'(Pid, _, _, _), ProofLimit, _) :- Pid < ProofLimit, \+ refs_gc_proof(Pid).
refs_gc_dead(sets, ev_set(Set, _, _, _, _), _, SetLimit) :- \+ refs_gc_live_set(Set, SetLimit).
refs_gc_dead(unions, ev_union_memo(Key, Union), _, SetLimit) :-
    Left is Key >> 32, Right is Key /\ 0xffffffff,
    \+ ( refs_gc_live_set(Left, SetLimit), refs_gc_live_set(Right, SetLimit), refs_gc_live_set(Union, SetLimit) ).

refs_gc_live_set(Set, SetLimit) :- ( Set =:= 0 ; Set >= SetLimit ; refs_gc_set(Set) ), !.

refs_gc_erase(proofs, user:'&proof'(Pid, _, _, _), Ref) :- !,
    erase(Ref), proof_metadata_erase(Pid), retractall(proof_rules_memo(Pid, _)),
    forget_summary_user(Pid).
refs_gc_erase(sets, ev_set(Set, _, _, _, _), Ref) :- !,
    erase(Ref), retractall(ev_given_memo(Set, _)), retractall(ev_inherited_memo(Set, _)).
refs_gc_erase(_, _, Ref) :- erase(Ref).

% The share kept of what existed when the cycle started: what the last cycle
% kept and what was stored between the two.
refs_gc_finish :-
    flag(refs_gc_words, Words, Words), flag(refs_gc_words_last, LastWords, Words),
    flag(refs_gc_marked_words, MarkedWords, MarkedWords), nb_getval(refs_gc_word_limit, LimitWords),
    flag(refs_gc_words_kept, KeptWords, MarkedWords + Words - LimitWords),
    flag(refs_gc_words_retained, _, min(1, MarkedWords / max(1, KeptWords + LimitWords - LastWords))),
    nb_getval(refs_gc_retire_epoch, Epoch), flag(refs_gc_retired_last, _, Epoch),
    aggregate_all(count, refs_gc_proof(_), Marked),
    nb_getval(refs_gc_limits, limits(ProofLimit, _)), 'search-id-value'(proof_id, Next),
    flag(refs_gc_last, Last, Next), flag(refs_gc_kept, KeptBefore, Marked + Next - ProofLimit),
    flag(refs_gc_retained, _, min(1, Marked / max(1, KeptBefore + ProofLimit - Last))),
    retractall(refs_gc_proof(_)), retractall(refs_gc_set(_)),
    nb_setval(refs_gc_phase, idle), refs_gc_take(none).

deps_mark(0, _) :- !.
deps_mark(Id, Live) :-
    (   add_nb_set(Id, Live, true)
    ->  (   deps_cut(Id, Replacement) -> deps_mark(Replacement, Live)
        ;   deps_node(Id, _, Children, _) -> forall(member(Child, Children), deps_mark(Child, Live))
        ;   true )
    ;   true ).

deps_children(Id, Children) :-
    (   deps_cut(Id, Replacement) -> Children = [Replacement] ; deps_node(Id, _, Children, _) ).
% The mask width trades stored bytes per node against collisions in dominance
% (docs/metta/dependency_tracking_design.md, "Mask width").
deps_mask_bits(4096).

deps_bit(Hash, Bit) :- deps_mask_bits(W), Bit is 1 << (Hash mod W).

deps_mask(0, 0) :- !.
deps_mask(Id, Mask) :- deps_leaf(Id, Hash), !, deps_bit(Hash, Mask).
deps_mask(Id, Mask) :- deps_node(Id, _, _, Mask).

'deps-key'(Hash, Id) :-
    (   deps_leaf(Id, Hash) -> true
    ;   flag(deps_next_id, Last, Last + 1), Id is Last + 1,
        assertz(deps_leaf(Id, Hash)) ).

'deps-union'(Left, Right, Id) :- 'deps-join'([Left, Right], Id).

'deps-join'(Ids, Id) :-
    sort(Ids, Sorted), exclude(==(0), Sorted, Children),
    (   Children == [] -> Id = 0
    ;   Children = [Only] -> Id = Only
    ;   term_hash(Children, Key),
        (   deps_node(Id, Key, Children, _) -> true
        ;   flag(deps_next_id, Last, Last + 1), Id is Last + 1,
            foldl([Child, Acc0, Acc]>>(deps_mask(Child, M), Acc is Acc0 \/ M), Children, 0, Mask),
            assertz(deps_node(Id, Key, Children, Mask)) ) ).

% Whether a set holds a key: the walk enters only children whose mask has the
% key's bit and visits each node once.
deps_has(Id, Hash) :- deps_bit(Hash, Bit), empty_nb_set(Seen), deps_has(Id, Hash, Bit, Seen).
deps_has(Id, Hash, Bit, Seen) :-
    deps_mask(Id, Mask), Mask /\ Bit =\= 0,
    (   deps_leaf(Id, Leaf) -> Leaf =:= Hash
    ;   add_nb_set(Id, Seen, true),
        deps_children(Id, Children),
        member(Child, Children), deps_has(Child, Hash, Bit, Seen), ! ).

'deps-has?'(Id, Hash, Result) :- ( deps_has(Id, Hash) -> Result = true ; Result = false ).
'deps-excluded'(Hashes, Id, Excluded) :- include(deps_has(Id), Hashes, Excluded).

% Whether a set holds any of the keys: one walk, entering only children whose
% mask has one of the keys' bits.
'deps-meet?'(Hashes, Id, Result) :-
    foldl([Hash, Bits0, Bits]>>(deps_bit(Hash, Bit), Bits is Bits0 \/ Bit), Hashes, 0, Bits),
    empty_nb_set(Seen),
    (   deps_meets(Id, Hashes, Bits, Seen) -> Result = true ; Result = false ).
deps_meets(Id, Hashes, Bits, Seen) :-
    deps_mask(Id, Mask), Mask /\ Bits =\= 0,
    (   deps_leaf(Id, Leaf) -> memberchk(Leaf, Hashes)
    ;   add_nb_set(Id, Seen, true),
        deps_children(Id, Children),
        member(Child, Children), deps_meets(Child, Hashes, Bits, Seen), ! ).

% Whether a set's mask lies within another's: exact when it does not (the
% first set has a key the second lacks); when it does, the keys may still
% differ by hash collisions. View dominance uses it, so a collision drops an
% older view a consumer could have read, never admits a self-supporting one.
'deps-mask-within?'(Set, Within, Result) :-
    (   ( Set == 0 ; Set == Within ) -> Result = true
    ;   deps_mask(Set, M1), deps_mask(Within, M2), ( M1 /\ \ M2 =:= 0 -> Result = true ; Result = false ) ).

% Whether every key of Set is in Within. A bit of Set's mask that Within's
% lacks is a key Within lacks, which decides most calls at once. Otherwise a
% node reachable from Within is covered whole; only the rest is walked down to
% its keys.
'deps-within?'(Set, Within, Result) :-
    (   deps_within(Set, Within) -> Result = true ; Result = false ).
deps_within(Set, Within) :- ( Set == 0 ; Set == Within ), !.
deps_within(Set, Within) :-
    deps_mask(Set, M1), deps_mask(Within, M2), M1 /\ \ M2 =:= 0,
    empty_nb_set(Nodes), empty_nb_set(Keys), deps_collect(Within, Nodes, Keys),
    empty_nb_set(Seen), deps_covered(Set, Nodes, Keys, Seen).
deps_collect(0, _, _) :- !.
deps_collect(Id, Nodes, Keys) :-
    (   add_nb_set(Id, Nodes, true)
    ->  (   deps_leaf(Id, Hash) -> add_nb_set(Hash, Keys, _)
        ;   deps_children(Id, Children), forall(member(Child, Children), deps_collect(Child, Nodes, Keys)) )
    ;   true ).
deps_covered(Id, Nodes, Keys, Seen) :-
    (   add_nb_set(Id, Nodes, false) -> true
    ;   add_nb_set(Id, Seen, false) -> true
    ;   add_nb_set(Id, Seen, true),
        (   deps_leaf(Id, Hash) -> add_nb_set(Hash, Keys, false)
        ;   deps_children(Id, Children), forall(member(Child, Children), deps_covered(Child, Nodes, Keys, Seen)) ) ).

% The number of keys in a set; a node's count never changes once computed.
'deps-size'(0, 0) :- !.
'deps-size'(Id, Size) :-
    (   deps_cut(Id, Replacement) -> 'deps-size'(Replacement, Size)
    ;   deps_leaf(Id, _) -> Size = 1
    ;   deps_size_memo(Id, Size) -> true
    ;   empty_nb_set(Nodes), empty_nb_set(Keys), deps_collect(Id, Nodes, Keys),
        size_nb_set(Keys, Size), assertz(deps_size_memo(Id, Size)) ).

% The keys near the top of at least two of the sets: each set's keys within
% two levels of its node (a value's own key and the keys of the premises its
% row read), held by two of the sets. Entangled premises of a row
% (sk-entangle) are found so by masked lookups, without collecting the sets.
'deps-entangled'(Ids, Hashes) :-
    foldl(deps_near_child(2), Ids, [], Near0), sort(Near0, Near),
    include(deps_held_twice(Ids), Near, Hashes).
deps_near(0, _, []) :- !.
deps_near(Id, _, [Hash]) :- deps_leaf(Id, Hash), !.
deps_near(Id, Depth, Near) :-
    Depth > 0, deps_children(Id, Children), !,
    Next is Depth - 1,
    foldl(deps_near_child(Next), Children, [], Near).
deps_near(_, _, []).
deps_near_child(Depth, Child, Acc0, Acc) :- deps_near(Child, Depth, Found), append(Found, Acc0, Acc).
deps_held_twice(Ids, Hash) :-
    aggregate_all(count, (member(Id, Ids), deps_has(Id, Hash)), Count), Count >= 2.

% One-step filtering: the keys within two levels of at least two of the sets
% (near in both), the one-step horizon of a key merge's views.
'deps-near-shared'(Ids, Hashes) :-
    maplist([Id, Near]>>(deps_near(Id, 2, Near0), sort(Near0, Near)), Ids, Nears),
    append(Nears, All), msort(All, Sorted), clumped(Sorted, Runs),
    findall(Hash, (member(Hash-Count, Runs), Count > 1), Hashes).

% The keys two sets both hold, in order.
'deps-shared'(A, B, Hashes) :-
    empty_nb_set(NodesA), empty_nb_set(KeysA), deps_collect(A, NodesA, KeysA),
    empty_nb_set(NodesB), empty_nb_set(KeysB), deps_collect(B, NodesB, KeysB),
    nb_set_to_list(KeysB, InB), include(deps_in(KeysA), InB, Hashes).
deps_in(Keys, Hash) :- add_nb_set(Hash, Keys, false).

% A value's evidence is an interned set, `ev-set(Id)` with 0 the empty set, so
% a value stays one small term however much evidence is behind it
% (docs/metta/evidence_sets.md). An entry, a fact or rule a proof uses, is
% interned once as an integer. A set is its entry ids in the order they were
% first added, interned by that sequence, so two values have the same
% evidence exactly when their ids are equal. It also keeps its ids sorted, for
% the set tests, and the ids of the rule entries its excluded-rule entries
% name. Both id sequences are packed in strings, one character per id, which
% a clause stores in a fifth of the space of an integer list; so at most
% 1,114,111 entries can be interned. Sets never change; a union is memoized by
% its operands.
:- dynamic ev_entry/3, ev_set/5, ev_union_memo/2.

% A fact's entries are also indexed by the hash of its stored proof, the name
% a row's leaf premise reads it by (evidence-condition), and a condition's by
% the fact it is given.
ev_entry_id(Entry, Id) :-
    'index-hash'(Entry, Hash),
    (   ev_entry(Id, Hash, Stored), Stored =@= Entry -> true
    ;   flag(ev_next_entry, Last, Last + 1), Id is Last + 1,
        assertz(ev_entry(Id, Hash, Entry)), ev_index_entry(Entry, Id) ).
ev_index_entry([Tag, _, Proof, _], Id) :- memberchk(Tag, ['fact-ev', 'not-fact-ev']), !,
    'index-hash'(Proof, ProofHash), assertz(ev_proof_entry(ProofHash, Id)).
ev_index_entry(['given-ev', K, P, T], Id) :- !, ev_entry_id(['fact-ev', K, P, T], Fact), assertz(ev_given_fact(Id, Fact)).
ev_index_entry(['not-ev', ['given-ev', K, P, T]], Id) :- !, ev_entry_id(['not-fact-ev', K, P, T], Fact), assertz(ev_given_fact(Id, Fact)).
ev_index_entry(_, _).
:- dynamic ev_proof_entry/2, ev_given_fact/2.

ev_order(0, []) :- !.
ev_order(Set, Ids) :- ev_set(Set, _, Order, _, _), string_codes(Order, Ids).
ev_sorted(0, []) :- !.
ev_sorted(Set, Ids) :- ev_set(Set, _, _, Sorted, _), string_codes(Sorted, Ids).
ev_excluded(0, []) :- !.
ev_excluded(Set, Excluded) :- ev_set(Set, _, _, _, Excluded).

ev_intern([], _, _, 0) :- !.
ev_intern(Ids, Sorted, Excluded, Set) :-
    string_codes(Order, Ids), term_hash(Order, Hash),
    (   ev_set(Set, Hash, Order, _, _) -> refs_gc_touch_set(Set)
    ;   flag(ev_next_set, Last, Last + 1), Set is Last + 1, string_codes(SortedString, Sorted),
        assertz(ev_set(Set, Hash, Order, SortedString, Excluded)) ).

% The set of a list of ids without repeats, in its order.
ev_of_ids(Ids, Set) :-
    findall(Rule, ( member(Id, Ids), ev_entry(Id, _, ['rule-excluded', Kb, Name]), ev_entry_id(['rule-ev', Kb, Name], Rule) ), Rules),
    sort(Ids, Sorted), sort(Rules, Excluded), ev_intern(Ids, Sorted, Excluded, Set).

ev_in_assoc(Assoc, Id) :- get_assoc(Id, Assoc, _).

% The ids of a list that are in a sorted list, in the list's order.
ev_keep(Ids, Sorted, Kept) :-
    pairs_keys_values(Pairs, Sorted, Sorted), ord_list_to_assoc(Pairs, Assoc), include(ev_in_assoc(Assoc), Ids, Kept).

ev_fact_entry(Id, Entry) :-
    ev_entry(Id, _, Entry), \+ Entry = ['rule-ev', _, _], \+ Entry = ['rule-excluded', _, _].

'evidence-set'(Entries, ['ev-set', Set]) :-
    maplist(ev_entry_id, Entries, Repeated), list_to_set(Repeated, Ids), ev_of_ids(Ids, Set).

'evidence-entries'(['ev-set', Set], Entries) :- ev_order(Set, Ids), maplist([Id, Entry]>>ev_entry(Id, _, Entry), Ids, Entries).

% A's entries followed by the entries of B that A lacks.
'evidence-union'(['ev-set', A], ['ev-set', B], ['ev-set', C]) :- ev_union(A, B, C).
ev_union(A, B, C) :-
    (   B == 0 -> C = A
    ;   A == 0 -> C = B
    ;   A == B -> C = A
    ;   Key is A << 32 \/ B, ev_union_memo(Key, Memo) -> refs_gc_touch_set(Memo), C = Memo
    ;   ev_sorted(A, SortedA), ev_sorted(B, SortedB),
        ord_subtract(SortedB, SortedA, New),
        (   New == [] -> C = A
        ;   ev_order(A, IdsA), ev_order(B, IdsB),
            ( New == SortedB -> Added = IdsB ; ev_keep(IdsB, New, Added) ),
            append(IdsA, Added, Ids), ord_union(SortedA, New, Sorted),
            ev_excluded(A, ExcludedA), ev_excluded(B, ExcludedB), ord_union(ExcludedA, ExcludedB, Excluded),
            ev_intern(Ids, Sorted, Excluded, C) ),
        Key is A << 32 \/ B, assertz(ev_union_memo(Key, C)) ).

% The union of the sets in order, interned once. Materializing every prefix
% retained quadratic evidence history when an exact fold ran repeatedly.
'evidence-join'(Sets, ['ev-set', Set]) :-
    findall(Id, (member(['ev-set', S], Sets), ev_order(S, Ids), member(Id, Ids)), Repeated),
    list_to_set(Repeated, Ids), ev_of_ids(Ids, Set).

'evidence-overlap?'(['ev-set', A], ['ev-set', B], Result) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ( ord_intersect(SortedA, SortedB) -> Result = true ; Result = false ).

'evidence-subset?'(['ev-set', A], ['ev-set', B], Result) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ( ord_subset(SortedA, SortedB) -> Result = true ; Result = false ).

% A's entries that B lacks, in A's order.
'evidence-subtraction'(['ev-set', A], ['ev-set', B], ['ev-set', C]) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ord_subtract(SortedA, SortedB, Kept),
    (   Kept == SortedA -> C = A
    ;   ev_order(A, IdsA), ev_keep(IdsA, Kept, Ids), ev_of_ids(Ids, C) ).

% Each entry as a Not reads it: a fact's entry names the fact negated, any
% other entry is wrapped. Negation cancels a previous wrapper; rule source
% identity and exclusions do not depend on the polarity of the conclusion.
'evidence-negated'(['ev-set', A], ['ev-set', C]) :-
    ev_order(A, Ids), maplist(ev_negated_id, Ids, Negated), ev_of_ids(Negated, C).
ev_negated_id(Id, Negated) :-
    ev_entry(Id, _, Entry),
    (   Entry = ['fact-ev', Kb, Proof, Type] -> Not = ['not-fact-ev', Kb, Proof, Type]
    ;   Entry = ['not-fact-ev', Kb, Proof, Type] -> Not = ['fact-ev', Kb, Proof, Type]
    ;   Entry = ['not-ev', Inner] -> Not = Inner
    ;   Entry = ['rule-ev', _, _] -> Not = Entry
    ;   Entry = ['rule-excluded', _, _] -> Not = Entry
    ;   Not = ['not-ev', Entry] ),
    ev_entry_id(Not, Negated).

% The entries other than rules that A shares with B, in reverse of A's order.
'evidence-shared-facts'(['ev-set', A], ['ev-set', B], Entries) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ord_intersection(SortedA, SortedB, Shared),
    (   Shared == [] -> Entries = []
    ;   ev_order(A, IdsA), ev_keep(IdsA, Shared, Kept), reverse(Kept, Reversed),
        convlist(ev_fact_entry, Reversed, Entries) ).

% Whether B uses a rule that one of A's excluded-rule entries names.
'evidence-excludes?'(['ev-set', A], ['ev-set', B], Result) :-
    ev_excluded(A, Excluded),
    (   Excluded \== [], ev_sorted(B, SortedB), ord_intersect(Excluded, SortedB) -> Result = true ; Result = false ).

% Proof metadata keeps the permanent owner identity, alongside its negation
% bit. Shared transitive provenance is interned only when a retirement check
% or an exposed KB copy needs it. Epoch-zero backward reads allocate no sets;
% publishing a KB copy registers it once against its shared source set.
% A canonical Patricia tree shares branches and bounds membership by one path.
:- dynamic retired_rule/2, retired_epoch/2, proof_live_memo/3,
           summary_rules/3, rule_set/5, rule_leaf/2, rule_branch/5, rule_union/3, rule_parent/2,
           proof_rules_memo/2, summary_user/3, stored_rules/5, stored_set/2, stored_token/2, summary_ref/3.

'withdraw-rule!'(Id, true) :-
    ( retired_rule(Id, _) -> true
    ; flag(withdraw_epoch, E, E + 1), Epoch is E + 1,
      assertz(retired_rule(Id, Epoch)), assertz(retired_epoch(Epoch, Id)) ).

'rule-live?'(Id, Live) :- ( retired_rule(Id, _) -> Live = false ; Live = true ).

rule_set_leaf(Rule, Set) :-
    ( rule_leaf(Rule, Set) -> true
    ; deps_bit(Rule, Mask), rule_set_new(leaf(Rule), [], Mask, Set), assertz(rule_leaf(Rule, Set)) ).

rule_sets_join(Sets, Set) :-
    sort(Sets, Sorted), exclude(==(0), Sorted, Children),
    foldl(rule_sets_union, Children, 0, Set),
    ( refs_gc_active -> refs_gc_mark_rule(Set) ; true ).

rule_sets_union(0, B, B) :- !.
rule_sets_union(A, 0, A) :- !.
rule_sets_union(A, A, A) :- !.
rule_sets_union(A, B, Set) :-
    First is min(A, B), Second is max(A, B),
    ( rule_union(First, Second, Set) -> true
    ; rule_set(A, AK, AC, _, _), rule_set(B, BK, BC, _, _),
      ( AK = leaf(AR) -> AB = -1 ; AK = branch(AB, AR) ),
      ( BK = leaf(BR) -> BB = -1 ; BK = branch(BB, BR) ),
      ( AR =:= BR -> Split = -1 ; Split is msb(AR xor BR) ),
      Rep is min(AR, BR),
      ( Split > max(AB, BB)
      -> ( AR < BR -> Left = A, Right = B ; Left = B, Right = A ),
         rule_set_branch(Split, Rep, Left, Right, Set)
      ; AB =:= BB
      -> AC = [AL, AT], BC = [BL, BT],
         rule_sets_union(AL, BL, Left), rule_sets_union(AT, BT, Right),
         rule_set_branch(AB, Rep, Left, Right, Set)
      ; AB > BB
      -> AC = [AL, AT],
         ( BR /\ (1 << AB) =:= 0 -> rule_sets_union(AL, B, Left), Right = AT
         ; Left = AL, rule_sets_union(AT, B, Right) ),
         rule_set_branch(AB, Rep, Left, Right, Set)
      ; BC = [BL, BT],
        ( AR /\ (1 << BB) =:= 0 -> rule_sets_union(A, BL, Left), Right = BT
        ; Left = BL, rule_sets_union(A, BT, Right) ),
        rule_set_branch(BB, Rep, Left, Right, Set) ),
      assertz(rule_union(First, Second, Set)) ).

rule_set_branch(Bit, Rep, Left, Right, Set) :-
    term_hash([Bit, Left, Right], Hash),
    ( rule_branch(Hash, Bit, Left, Right, Set) -> true
    ; rule_set(Left, _, _, LM, _), rule_set(Right, _, _, RM, _), Mask is LM \/ RM,
      rule_set_new(branch(Bit, Rep), [Left, Right], Mask, Set),
      assertz(rule_branch(Hash, Bit, Left, Right, Set)) ).

% A distinct node inherits current child liveness; its first read never
% replays the historical retirement log or copies transitive rule lists.
rule_set_new(Kind, Children, Mask, Set) :-
    flag(rule_set_next, N, N + 1), Set is N + 1,
    ( Kind = leaf(_) -> Count = 1
    ; Children = [Left, Right], rule_set(Left, _, _, _, LC), rule_set(Right, _, _, _, RC), Count is LC + RC ),
    assertz(rule_set(Set, Kind, Children, Mask, Count)), flag(withdraw_epoch, Epoch, Epoch),
    forall(member(Child, Children), assertz(rule_parent(Child, Set))),
    ( Epoch =:= 0 -> true
    ; ( ( Kind = leaf(Rule) -> \+ retired_rule(Rule, _) ; forall(member(Child, Children), rule_set_live(Child, Epoch)) )
        -> Live = true ; Live = false ),
      assertz(proof_live_memo(Set, Epoch, Live)) ).

proof_rule_set(Proof, Set) :-
    findall(S, ( sub_term(Ref, Proof), nonvar(Ref), proof_source_rules(Ref, S) ), Children),
    rule_sets_join(Children, Set).

% Resolve each immutable proof DAG node once, sharing the canonical source
% sets. The cache is absent until provenance is actually read, and collected
% with its proof. This never enumerates other proofs or the retirement log.
proof_rules(Pid, Set) :-
    ( proof_rules_memo(Pid, Set) -> ( refs_gc_active -> refs_gc_mark_rule(Set) ; true )
    ; user:'&proof'(Pid, Proof, _, Flags), Code is Flags >> 1,
      proof_rule_set(Proof, Sources),
      ( Code > 0 -> Owner is Code - 1, rule_set_leaf(Owner, Own), rule_sets_join([Sources, Own], Set) ; Set = Sources ),
      assertz(proof_rules_memo(Pid, Set)), forget_summary_user(Pid) ).
'proof-ref-negated?'(Pid, Negated) :-
    ( user:'&proof'(Pid, _, _, Flags), Flags /\ 1 =:= 1 -> Negated = true ; Negated = false ).

forget_summary_user(Pid) :-
    forall(retract(summary_user(Pid, Hash, Epoch)), retractall(summary_ref(Hash, Epoch, Pid))).

'record-summary-rules!'(Hash, Epoch, Proof, true) :-
    proof_rule_set(Proof, Set), assertz(summary_rules(Hash, Epoch, Set)).

proof_source_rules([Tag, Pid], Set) :- Tag == 'proof-ref', integer(Pid), proof_rules(Pid, Set).
proof_source_rules([Tag, Hash, Epoch], Set) :- Tag == forgotten, integer(Hash), integer(Epoch), summary_rules(Hash, Epoch, Set).

'proof-live?'(Proof, Live) :-
    flag(withdraw_epoch, Epoch, Epoch),
    ( Epoch =:= 0 -> Live = true
    ; forall(( sub_term(Ref, Proof), nonvar(Ref), proof_source_rules(Ref, Set) ),
             rule_set_live(Set, Epoch)) -> Live = true
    ; Live = false ).

rule_set_live(0, _) :- !.
rule_set_live(Set, Epoch) :-
    ( proof_live_memo(Set, Checked, Live) -> true ; Checked = 0, Live = true ),
    Live == true,
    ( Checked =:= Epoch -> true
    ; rule_set(Set, Kind, _, _, Count), flag(rule_retired_floor, Floor, Floor),
      ( Kind = leaf(Owner)
      -> ( retired_rule(Owner, _) -> Next = false ; Next = true )
      ; ( Epoch - Checked > Count ; Checked < Floor )
      -> ( rule_set_leaves_live(Set) -> Next = true ; Next = false )
      ; First is Checked + 1,
        ( between(First, Epoch, E), retired_epoch(E, Rule), rule_set_has(Set, Rule) -> Next = false ; Next = true ) ),
      retractall(proof_live_memo(Set, _, _)), assertz(proof_live_memo(Set, Epoch, Next)), Next == true ).

rule_set_leaves_live(Set) :- forall(rule_set_rule(Set, Rule), \+ retired_rule(Rule, _)).
rule_set_rule(Set, Rule) :-
    rule_set(Set, Kind, Children, _, _),
    ( Kind = leaf(Rule) -> true ; member(Child, Children), rule_set_rule(Child, Rule) ).

rule_set_has(Set, Rule) :- rule_leaf(Rule, _), deps_bit(Rule, Bit), rule_set_has(Set, Rule, Bit).
rule_set_has(Set, Rule, Bit) :-
    rule_set(Set, Kind, Children, Mask, _), Mask /\ Bit =\= 0,
    ( Kind = leaf(Rule) -> true
    ; Kind = branch(Branch, Rep), Rule >> (Branch + 1) =:= Rep >> (Branch + 1),
      Children = [Left, Right],
      ( Rule /\ (1 << Branch) =:= 0 -> rule_set_has(Left, Rule, Bit) ; rule_set_has(Right, Rule, Bit) ) ).

% Each physical KB copy registers once against its canonical set. Shared
% child-to-parent edges lead from a retired rule's leaf to affected copies;
% publication/removal never enumerates that set's contributing rules.
'record-stored-rules!'(Kind, Hash, Key, Proof, true) :-
    'forget-stored-rules!'(Kind, Hash, Key, true), proof_rule_set(Proof, Set),
    flag(stored_rules_next, N, N + 1), Token is N + 1,
    assertz(stored_rules(Hash, Kind, Key, Token, Set), Ref), assertz(stored_token(Token, Ref)),
    assertz(stored_set(Set, Token)).

'forget-stored-rules!'(Kind, Hash, Key, true) :-
    forall(( stored_rules(Hash, Kind, Stored, Token, Set), Stored =@= Key ),
           ( retractall(stored_set(Set, Token)), stored_token(Token, Ref), erase(Ref), retractall(stored_token(Token, _)) )).

'withdrawn-stores!'(Ids, Stores) :-
    findall(Leaf, ( member(Id, Ids), rule_leaf(Id, Leaf) ), Leaves), empty_nb_set(Seen),
    findall(Token, ( rule_set_ancestor(Leaves, Seen, Set), stored_set(Set, Token) ), Tokens0), sort(Tokens0, Tokens),
    findall(['retired-store', Kind, Hash, Key],
            ( member(Token, Tokens), stored_token(Token, Ref),
              clause(stored_rules(Hash, Kind, Key, Token, _), true, Ref),
              'forget-stored-rules!'(Kind, Hash, Key, true) ), Stores).

% The Patricia nodes form a shared DAG across canonical sets. Visit each
% affected node once, including ancestors without a published copy of their
% own, so diamonds and multiple retired sources do not repeat subtree work.
rule_set_ancestor([Set|Rest], Seen, Ancestor) :-
    add_nb_set(Set, Seen, New),
    ( New == true
    -> ( Ancestor = Set
       ; findall(Parent, rule_parent(Set, Parent), Parents), append(Parents, Rest, Next),
         rule_set_ancestor(Next, Seen, Ancestor) )
    ; rule_set_ancestor(Rest, Seen, Ancestor) ).


% An answer is redundant when another answer with the same proof has a
% strictly more general statement, or a variant statement earlier in the list:
% of answers that instantiate each other, the first stays. Only identical
% ground proofs are compared; nonground proofs cannot be identical after the
% independent copies used for subsumption. The local index shares the inputs;
% findall retains order and copies each survivor just as MeTTa's collapse does,
% isolating variables between returned answers.
prune_answer_instances([], []) :- !.
prune_answer_instances([Answer], [Kept]) :- !, copy_term(Answer, Kept).
prune_answer_instances(Answers, Kept) :-
    numbered_answers(Answers, 1, Numbered),
    empty_assoc(Empty),
    reverse(Numbered, Reversed),
    foldl(index_answer_proof, Reversed, Empty-Empty, Index),
    findall(Answer, (member(Position-Answer, Numbered),
                     \+ answer_instance(Index, Position, Answer)), Kept).

numbered_answers([], _, []).
numbered_answers([Answer|Answers], Position, [Position-Answer|Numbered]) :-
    Next is Position + 1,
    numbered_answers(Answers, Next, Numbered).

index_answer_proof(Position-Answer, Before-Memo, After-NextMemo) :-
    (   nonvar(Answer), Answer = [_, _, Proof, _],
        proof_identity_hash(Proof, Memo, NextMemo, Hash)
    ->  (get_assoc(Hash, Before, Previous) -> true ; Previous = []),
        put_assoc(Hash, Before, [Position-Answer|Previous], After)
    ;   After = Before, NextMemo = Memo
    ).

% Hash the semantic proof DAG once per reference, without expanding it. An
% open leaf has no identity hash and passes through; collisions are checked
% by the same nonbinding proof comparison used by merging.
proof_identity_hash(Proof, Memo, NextMemo, Hash) :-
    (   proof_ref_id(Proof, Id)
    ->  (   get_assoc(Id, Memo, Hash) -> NextMemo = Memo
        ;   user:'&proof'(Id, Stored, _, _),
            (   opaque_proof_step(Stored)
            ->  term_hash(opaque(Id), Hash), ExpandedMemo = Memo
            ;   proof_identity_hash(Stored, Memo, ExpandedMemo, Hash) ),
            put_assoc(Id, ExpandedMemo, Hash, NextMemo) )
    ;   nonvar(Proof), Proof = [Head|Tail]
    ->  proof_identity_hash(Head, Memo, HeadMemo, HeadHash),
        proof_identity_hash(Tail, HeadMemo, NextMemo, TailHash),
        term_hash(node(HeadHash, TailHash), Hash)
    ;   ground(Proof), term_hash(leaf(Proof), Hash), NextMemo = Memo
    ).

answer_instance(Index-Memo, Position, Answer) :-
    nonvar(Answer), Answer = [_, _, Proof, _],
    proof_identity_hash(Proof, Memo, _, Hash),
    get_assoc(Hash, Index, Candidates),
    member(Other-General, Candidates),
    Other \== Position,
    '=alpha'(Answer, General, false),
    copy_term(Answer, [SpecificType, _, _, _]),
    copy_term(General, [GeneralType, _, GeneralProof, _]),
    subsumes_term(GeneralType, SpecificType),
    (   Other < Position
    ->  true
    ;   \+ subsumes_term(SpecificType, GeneralType)
    ),
    empty_nb_set(Seen), same_proof_terms(Proof, GeneralProof, Seen),
    !.

% What building a skeleton row or node of a term costs, in rows of the row
% allowance or steps of the budget: one, and one more for each 400 words of the
% term, about what storing, hashing and comparing that much of a term takes
% beyond a row's fixed cost (ONA reasoningbench_num: a row of a 9,000-word
% statement took 25 ms, one of a few words about 1 ms).
'term-cost'(Term, Cost) :- term_size(Term, Size), Cost is 1 + Size // 400.

% Whether node Specific is an instance of node General whose statement binds
% one of General's variables to a compound term: the term a recursive rule
% grows, as (Num (succ $x)) grows from (Num $x), and not a mere specialization
% such as (Reward op1 $t) of (Reward $op $t). Tested on attribute-free copies,
% so typed variables run no constraints.
'grows-from?'(General, Specific, Result) :-
    copy_term_nat(General, G),
    copy_term_nat(Specific, S),
    (   subsumes_term(G, S), G = [GT|_], S = [ST|_], term_size(ST, SS), term_size(GT, GS), SS > GS
    ->  Result = true ; Result = false ).

% Links the key a join read to the premise the join bound (sk-read-step):
% each variable of General, at a position where Instance, an instance of it,
% still has a variable, is unified with that variable, unless the join bound
% two variables of General to one of Instance. Where the join bound Instance
% further, General keeps its own variable, so the row reads the key that
% answered it, and evaluation still binds Instance's open variables through it.
'link-open-variables'(General, Instance, true) :-
    (   ground(General)
    ->  true
    ;   open_variable_pairs(General, Instance, Pairs, []),
        include(one_to_one(Pairs), Pairs, Linked),
        maplist(link_pair, Linked)
    ).

open_variable_pairs(General, Instance, Pairs, Tail) :-
    (   var(General)
    ->  (   var(Instance) -> Pairs = [General-Instance|Tail] ; Pairs = Tail )
    ;   compound(General), compound(Instance)
    ->  General =.. [_|GeneralArgs],
        Instance =.. [_|InstanceArgs],
        foldl(open_variable_pairs, GeneralArgs, InstanceArgs, Pairs, Tail)
    ;   Pairs = Tail
    ).

one_to_one(Pairs, General-Instance) :-
    \+ ( member(G-I, Pairs),
          ( G == General, I \== Instance ; I == Instance, G \== General ) ).

link_pair(Variable-Variable).

'rule-lookup-needs-occurs-check'(Term, Result) :-
    term_variables(Term, Variables),
    term_singletons(Term, Singletons),
    (   same_length(Variables, Singletons)
    ->  Result = false
    ;   Result = true
    ).

'ccls-index-occurs-matches'(LookupTemplate, Matches) :-
    current_prolog_flag(occurs_check, Previous),
    setup_call_cleanup(
        set_prolog_flag(occurs_check, true),
        (   current_predicate(ccls_index/3)
        ->  findall(
                [Matched, RuleId, Args],
                ( copy_term(LookupTemplate, Matched),
                  ccls_index(Matched, RuleId, Args)
                ),
                Matches)
        ;   Matches = []
        ),
        set_prolog_flag(occurs_check, Previous)).

% Deterministic bounded particle condensation. The strongest particles become
% anchors; each overflow particle is absorbed by the compatible anchor with
% the least Ward loss. This retains modes with meaningful mass, merges nearby
% numeric samples by weighted centroid, and costs O(support * budget).
particle_merge_resample(Pairs, Budget, Result) :-
    integer(Budget),
    Budget > 0,
    indexed_particle_pairs(Pairs, 0, Ranked),
    keysort(Ranked, Sorted),
    length(Sorted, Length), Taken is min(Budget, Length),
    length(Strongest, Taken), append(Strongest, Overflow, Sorted), pairs_values(Strongest, Anchors0),
    sort(1, @<, Anchors0, Anchors),
    absorb_overflow_particles(Overflow, Anchors, Merged),
    sort(1, @<, Merged, Ordered),
    maplist([component(_, Value, Weight), [Value, Weight]]>>true, Ordered, Result).

indexed_particle_pairs([], _, []).
indexed_particle_pairs([[Value, Weight]|Rest], Index,
        [key(NegativeWeight, Index)-component(Index, Value, Weight)|Ranked]) :-
    NegativeWeight is -Weight,
    NextIndex is Index + 1,
    indexed_particle_pairs(Rest, NextIndex, Ranked).

absorb_overflow_particles([], Anchors, Anchors).
absorb_overflow_particles([_-Particle|Rest], Anchors0, Anchors) :-
    closest_particle_anchor(Anchors0, Particle, none, Best),
    Best = best(_, AnchorIndex, Value, Weight),
    replace_particle_anchor(Anchors0, AnchorIndex, Value, Weight, Anchors1),
    absorb_overflow_particles(Rest, Anchors1, Anchors).

closest_particle_anchor([], _, Best, Best).
closest_particle_anchor(
        [component(AnchorIndex, Anchor, AnchorWeight)|Rest],
        component(_, Value, Weight), Best0, Best) :-
    (   particle_merge_term(
            Anchor, AnchorWeight, Value, Weight, Mean, DistanceSquared)
    ->  MergedWeight is AnchorWeight + Weight,
        Cost is AnchorWeight * Weight / MergedWeight * DistanceSquared,
        (   Best0 = best(BestCost, _, _, _), \+ Cost < BestCost
        ->  Best1 = Best0
        ;   Best1 = best(Cost, AnchorIndex, Mean, MergedWeight) )
    ;   Best1 = Best0
    ),
    closest_particle_anchor(
        Rest, component(_, Value, Weight), Best1, Best).

replace_particle_anchor(
        [component(Index, _, _)|Rest], Index, Value, Weight,
        [component(Index, Value, Weight)|Rest]) :- !.
replace_particle_anchor([Anchor|Rest], Index, Value, Weight,
        [Anchor|Updated]) :-
    replace_particle_anchor(Rest, Index, Value, Weight, Updated).

particle_merge_term(Left, _, Right, _, Left, 0.0) :-
    Left == Right,
    !.
particle_merge_term(Left, LeftWeight, Right, RightWeight, Mean, DistanceSquared) :-
    number(Left),
    number(Right),
    !,
    Mean is (LeftWeight * Left + RightWeight * Right) /
        (LeftWeight + RightWeight),
    Delta is Left - Right,
    DistanceSquared is Delta * Delta.
particle_merge_term(Left, LeftWeight, Right, RightWeight, Mean, DistanceSquared) :-
    compound(Left),
    compound(Right),
    compound_name_arguments(Left, Functor, LeftArgs),
    compound_name_arguments(Right, Functor, RightArgs),
    particle_merge_args(
        LeftArgs, LeftWeight, RightArgs, RightWeight,
        MeanArgs, DistanceSquared),
    compound_name_arguments(Mean, Functor, MeanArgs).

particle_merge_args([], _, [], _, [], 0.0).
particle_merge_args(
        [Left|LeftRest], LeftWeight, [Right|RightRest], RightWeight,
        [Mean|MeanRest], DistanceSquared) :-
    particle_merge_term(
        Left, LeftWeight, Right, RightWeight, Mean, HeadDistanceSquared),
    particle_merge_args(
        LeftRest, LeftWeight, RightRest, RightWeight,
        MeanRest, RestDistanceSquared),
    DistanceSquared is HeadDistanceSquared + RestDistanceSquared.

% The ordinary readers being computed, innermost first. The stack is a
% backtrackable global: a reader pushes a copy of its identity, restores the
% stack it found when it is done, and failure or an exception restores it by
% backtracking. Neither copies the stack.
'sk-push-reader!'(Reader, Readers) :-
    ( nb_current(sk_reading, Stored) -> Readers = Stored ; Readers = [] ),
    copy_term(Reader, Copy),
    b_setval(sk_reading, [Copy|Readers]).
'sk-restore-readers!'(Readers, true) :- b_setval(sk_reading, Readers).
% Each active reader, outermost first.
'sk-active-reader'(Reader) :-
    nb_current(sk_reading, Readers), reverse(Readers, Outermost), member(Reader, Outermost).

% Inference time, process-wide, in seconds: activation, search and evaluation
% of backward queries, and forward runs. A caller splits the wall time of its
% calls into inference and overhead with it; it costs two clock reads a call.
'inference-clock'(Time) :- get_time(Time).
'inference-add!'(Start, true) :-
    get_time(Now),
    flag(pettachainer_inference_seconds, Seconds, Seconds + Now - Start).
inference_seconds(Seconds) :- flag(pettachainer_inference_seconds, Seconds, Seconds).

% Optional query counters sit on backward-search hot paths. Keep their disabled
% check and enabled scalar updates native so diagnostics do not distort normal
% query performance with thousands of MeTTa state or space operations.
query_metrics_enabled(Enabled) :-
    ( nb_current(pettachainer_query_metrics_enabled, Stored) -> Enabled = Stored ; Enabled = false ).
query_metrics_set_enabled(Enabled, Enabled) :- nb_setval(pettachainer_query_metrics_enabled, Enabled).
query_metric_value(Key, Value) :- atom_concat(pettachainer_query_metric_, Key, G), 'search-id-value'(G, Value).
query_metric_set(Key, Value, Value) :-
    ( query_metrics_enabled(true) -> atom_concat(pettachainer_query_metric_, Key, G), nb_setval(G, Value) ; true ).
query_metric_increment(Key, Result) :-
    (   query_metrics_enabled(true)
    ->  query_metric_value(Key, Old), Result is Old + 1,
        atom_concat(pettachainer_query_metric_, Key, G), nb_setval(G, Result)
    ;   Result = 0
    ).

% KL divergence of Beta(A1,B1) from Beta(A2,B2): how far a key's new value,
% read as a Beta over its strength, moved from its old one.
beta_kl(A1, B1, A2, B2, KL) :-
    digamma(A1, PA), digamma(B1, PB), S1 is A1 + B1, digamma(S1, PS),
    KL is lgamma(A2) + lgamma(B2) - lgamma(A2 + B2)
        - (lgamma(A1) + lgamma(B1) - lgamma(S1))
        + (A1 - A2) * PA + (B1 - B2) * PB
        + (A2 - A1 + B2 - B1) * PS.

% Digamma by the recurrence psi(x) = psi(x + 1) - 1/x up to x >= 6, then the
% asymptotic series.
digamma(X, P) :-
    (   X < 6.0
    ->  X1 is X + 1.0, digamma(X1, P1), P is P1 - 1.0 / X
    ;   I is 1.0 / (X * X),
        P is log(X) - 0.5 / X
            - I * (1.0/12 - I * (1.0/120 - I * (1.0/252 - I * (1.0/240 - I / 132))))
    ).

% Python's call of a chainer function (pettachainer.py): Fn applied to the
% arguments each MeTTa source in Sources reads as, every result collected in
% order, as a runnable `!(Fn Args)` returns them. Arguments that are data,
% which a runnable passes as they are, are passed without compiling one; any
% other argument, such as a nested call or a lambda a runnable evaluates
% first, is compiled as a runnable. As text, a result is printed as MeTTa
% prints it; as terms, an expression arrives through janus as a list and a
% symbol or string as a str, and since janus passes no unbound variable each
% is named as MeTTa prints it.
metta_call(Fn, Sources, Results) :-
    atom_string(Name, Fn),
    foldl(metta_call_source(Name), Sources, Results, []).
metta_call_source(Name, Source, Results, Rest) :-
    format(string(Expression), "(~s)", [Source]),
    sread(Expression, Args),
    (   maplist(metta_data, Args)
    ->  append(Args, [Result], CallArgs),
        Goal =.. [Name|CallArgs],
        findall(Result, Goal, Results, Rest)
    ;   format(string(Code), "!(~w ~s)", [Name, Source]),
        process_metta_string(Code, Own),
        append(Own, Rest, Results)
    ).
% What a runnable passes unevaluated: a variable, a number, symbol or string,
% or an expression of such terms whose head names no function, special form
% or translator rule.
metta_data(Term) :- var(Term), !.
metta_data(Term) :- atomic(Term), !.
metta_data([Head|Args]) :-
    (   atom(Head)
    ->  \+ fun(Head), \+ translator_rule(Head), \+ special_builtin_form(Head, Args, _)
    ;   metta_data(Head)
    ),
    maplist(metta_data, Args).
metta_call_text(Fn, Sources, Texts) :-
    metta_call(Fn, Sources, Results),
    maplist(swrite, Results, Texts).
metta_call_terms(Fn, Sources, Results) :-
    metta_call(Fn, Sources, Results),
    term_variables(Results, Variables),
    foldl([Variable, N0, N]>>(format(atom(Variable), '$_~d', [N0]), N is N0 + 1),
          Variables, 0, _).

% A view's evidence as its readers inherit it: the role in which the view read
% a certain fact (given-ev, a condition) is that view's own; a reader holds the
% fact itself. A set with no given entry is itself. Sets never change, so each
% is computed once; the memo goes with its set, and a collected result is
% computed again.
:- dynamic ev_inherited_memo/2.
'evidence-inherited'(['ev-set', A], ['ev-set', C]) :-
    (   ev_inherited_memo(A, C0), ( C0 == A ; ev_set(C0, _, _, _, _) ) -> refs_gc_touch_set(C0), C = C0
    ;   retractall(ev_inherited_memo(A, _)), ev_order(A, Ids),
        (   member(Id, Ids), ev_given_fact(Id, _)
        ->  maplist(ev_inherited_id, Ids, Out), list_to_set(Out, Set), ev_of_ids(Set, C)
        ;   C = A ),
        assertz(ev_inherited_memo(A, C)) ).
ev_inherited_id(Id, Out) :- ( ev_given_fact(Id, Fact) -> Out = Fact ; Out = Id ).

% The fact entries stored with Proof of Evidence's inherited set, in its
% order. They are found by the proof's hash, without reading the set: a fact
% is inherited when it or a condition given it is in the set.
'evidence-proof-fact'(['ev-set', A], Proof, Entry) :-
    'index-hash'(Proof, Hash), ev_sorted(A, Sorted),
    findall(Id, ( ev_proof_entry(Hash, Id), ev_entry(Id, _, ['fact-ev', _, Proof, _]),
                  ( ord_memberchk(Id, Sorted) -> true ; ev_given_fact(Given, Id), ord_memberchk(Given, Sorted) ) ),
            Ids),
    (   Ids = [_, _|_]
    ->  ev_order(A, Order), maplist(ev_inherited_id, Order, Out), list_to_set(Out, Set),
        include([Id]>>memberchk(Id, Ids), Set, Ordered)
    ;   Ordered = Ids ),
    member(Id, Ordered), ev_entry(Id, _, Entry).

% Stored binary-certain facts and conditions are certain entries. A fact's
% certainty is read from the live KB, not cached with its entry.
ev_entry_certain(Id) :- ev_entry(Id, _, E), ev_entry_is_certain(E).
ev_entry_is_certain(['given-ev'|_]) :- !.
ev_entry_is_certain(['rule-ev', Kb, Name]) :- !,
    catch('&given_rules'(Name, Kb), error(existence_error(procedure, _), _), fail).
ev_entry_is_certain(['not-ev', Inner]) :- !, ev_entry_is_certain(Inner).
ev_entry_is_certain(['not-fact-ev', Ctx, P, Type]) :- !, ev_entry_is_certain(['fact-ev', Ctx, P, Type]).
ev_entry_is_certain(['fact-ev', Ctx, P, Type]) :- !,
    once(catch('&kb'(Type, Ctx, P, ['STV', S, C]), error(existence_error(procedure, _), _), fail)),
    ev_binary_certain(S, C).
ev_binary_certain(S, C) :- number(S), number(C), C >= 1.0, ( S >= 1.0 ; S =< 0.0 ).

% The evidence B's raw sources add to A, as a count: none (0) when B lies
% within A; unbounded (-1) when a source new to A is certain (a binary fact,
% a given, or a value at confidence 1); otherwise the sum of the counts
% k c/(1 - c) of B's new sources, a source whose truth value cannot be read
% counting nothing (what A already holds is never counted again).
'evidence-unique-count'(K, ['ev-set', A], ['ev-set', B], Count) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ord_subtract(SortedB, SortedA, New),
    (   New == []
    ->  Count = 0.0
    ;   member(Id, New), ( ev_entry_certain(Id) ; entry_confidence(Id, C), C >= 1.0 )
    ->  Count = -1.0
    ;   foldl(entry_count(K), New, 0.0, Count) ).

entry_count(K, Id, N0, N) :- ( entry_confidence(Id, C) -> N is N0 + K * C / (1 - C) ; N = N0 ).

entry_confidence(Id, C) :- ev_entry(Id, _, Entry), entry_tv_confidence(Entry, C).
entry_tv_confidence(['not-ev', Inner], C) :- !, entry_tv_confidence(Inner, C).
entry_tv_confidence(['not-fact-ev', Ctx, P, Type], C) :- !, entry_tv_confidence(['fact-ev', Ctx, P, Type], C).
entry_tv_confidence(['fact-ev', Ctx, P, Type], C) :- !,
    once(catch('&kb'(Type, Ctx, P, TV), error(existence_error(procedure, _), _), fail)), tv_confidence(TV, C).
entry_tv_confidence(['rule-ev', Kb, Name], C) :-
    once(catch('&kb'(_, [Kb|_], Name, TV),
               error(existence_error(procedure, _), _), fail)),
    tv_confidence(TV, C).
tv_confidence(['STV', _, C], C).
tv_confidence(['CTV', ['STV', _, C1], ['STV', _, C2]], C) :- C is min(C1, C2).

% Whether two views share an uncertain entry. Only the shared entries are
% classified.
'evidence-uncertain-overlap?'(['ev-set', A], ['ev-set', B], Result) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ( ev_shared_where(ev_uncertain_id, SortedA, SortedB) -> Result = true ; Result = false ).
ev_uncertain_id(Id) :- \+ ev_entry_certain(Id).
% Whether two sorted id lists share an id meeting Goal; stops at the first.
ev_shared_where(Goal, [X|Xs], [Y|Ys]) :-
    compare(Order, X, Y),
    (   Order == (=) -> ( call(Goal, X) -> true ; ev_shared_where(Goal, Xs, Ys) )
    ;   Order == (<) -> ev_shared_where(Goal, Xs, [Y|Ys])
    ;   ev_shared_where(Goal, [X|Xs], Ys) ).

% A's entries without the certain entries of B.
'evidence-subtraction-certain'(['ev-set', A], ['ev-set', B], ['ev-set', C]) :-
    ev_sorted(B, SortedB), include(ev_entry_certain, SortedB, Certain),
    ev_sorted(A, SortedA), ord_subtract(SortedA, Certain, Kept),
    (   Kept == SortedA -> C = A
    ;   ev_order(A, IdsA), ev_keep(IdsA, Kept, Ids), ev_of_ids(Ids, C) ).

% A certain fact a row read as a condition (its stored proof among the row's
% condition leaves, by hash) becomes given-ev in the row's evidence, or
% (not-ev given-ev) when read under a Not. Only the leaves' entries are looked at.
'evidence-condition'(['ev-set', A], Names, ['ev-set', C]) :-
    findall(Id, ( member(Name, Names), ev_proof_entry(Name, Id), ev_entry_certain(Id) ), Leaves0),
    (   Leaves0 == [] -> C = A
    ;   sort(Leaves0, Leaves), ev_sorted(A, SortedA), ord_intersection(SortedA, Leaves, Given),
        (   Given == [] -> C = A
        ;   ev_order(A, Ids), maplist(ev_condition_id(Given), Ids, Out), list_to_set(Out, Set), ev_of_ids(Set, C) ) ).
ev_condition_id(Given, Id, Out) :-
    (   ord_memberchk(Id, Given), ev_entry(Id, _, [Tag, K, P, T])
    ->  ( Tag == 'fact-ev' -> ev_entry_id(['given-ev', K, P, T], Out) ; ev_entry_id(['not-ev', ['given-ev', K, P, T]], Out) )
    ;   Out = Id ).

% How two views share a certain fact: `observed` when both observed it,
% `a-condition` / `b-condition` when one read it as a condition the other
% observed, outside complete predicates (whether that is a loop depends on the
% reader being a forward view), `no-shared` otherwise. Roles are given-ev / fact-ev.
'evidence-observed-roles'(['ev-set', A], ['ev-set', B], Result) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    (   ev_shared_where(ev_certain_observation, SortedA, SortedB) -> Result = observed
    ;   ev_given_facts(A, SortedA, GivenA), ord_intersection(GivenA, SortedB, AB), \+ maplist(ev_complete_entry, AB)
    ->  Result = 'a-condition'
    ;   ev_given_facts(B, SortedB, GivenB), ord_intersection(GivenB, SortedA, BA), \+ maplist(ev_complete_entry, BA)
    ->  Result = 'b-condition'
    ;   Result = 'no-shared' ).
% The certain facts a set read as conditions, as sorted fact-ev ids. Sets never
% change, so they are computed once (a collected set's id is never reused).
:- dynamic ev_given_memo/2.
ev_given_facts(Set, Sorted, Facts) :-
    (   ev_given_memo(Set, Facts0) -> Facts = Facts0
    ;   findall(Fact, ( member(Id, Sorted), ev_given_fact(Id, Fact) ), Facts1), sort(Facts1, Facts),
        assertz(ev_given_memo(Set, Facts)) ).
ev_certain_observation(Id) :- ev_entry(Id, _, [Tag|_]), memberchk(Tag, ['fact-ev', 'not-fact-ev']), ev_entry_certain(Id).
ev_complete_entry(Id) :-
    ev_entry(Id, _, ['fact-ev', [Kb, 'MAIN', _], _, Type]), ground(Type),
    ( Type = [Head|_] -> true ; Head = Type ),
    catch('&complete_predicates'(Kb, Head), error(existence_error(procedure, _), _), fail).

% What applying a refined rule can add, from its truth: its confidence, and
% for a CTV how far the consequent's probability moves with the antecedent
% (docs/metta/hypothesis_rules.md). An STV does not say, so it counts fully.
% Never 0: a rule that adds nothing is still reached with budget to spare.
'rule-truth-factor'(Tv, Factor) :-
    (   Tv = ['CTV', ['STV', S1, C1], ['STV', S0, _]], number(S1), number(C1), number(S0)
    ->  Raw is C1 * abs(S1 - S0)
    ;   Tv = ['STV', _, C], number(C) -> Raw = C
    ;   Raw = 1.0 ),
    Factor is max(Raw, 0.01).

