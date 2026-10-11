:- use_module(library(heaps)).
:- use_module(library(assoc)).
:- use_module(library(nb_set)).
:- use_module(library(yall)).

% Data-only spaces have no function definitions or compiler metadata. In
% particular, an open first column must not enter remove-atom's function case.
'remove-data-rows!'(Space, Pattern, true) :-
    Row =.. [Space|Pattern],
    retractall(Row).

% Add a row that add-atom could not prove against the space's declared type
% when compiled: the space is named at run time, or a column's type is only
% known then. add-atom checks such a row on every call, which costs more than
% the add itself (PeTTa's analysis hooks raise and catch an exception per
% checked column); the callers build rows of the declared shape.
'add-space-atom!'(Space, Row, true) :-
    Term =.. [Space|Row],
    assertz(Term).

% Remove the rows of each space whose first column is Hash: the stores keyed
% by a node's or key's own hash, all at once.
'remove-hash-rows!'(Spaces, Hash, true) :-
    forall(( member(Space, Spaces), current_predicate(Space/Arity), Arity > 0 ),
           ( functor(Row, Space, Arity), arg(1, Row, Hash), retractall(Row) )).

% Erase the one stored row that is a variant of Row. A removal by unification
% could also take a different row with the same coarse hash; a variant cannot.
'remove-variant-row!'(Space, Row, true) :-
    Head =.. [Space|Row],
    functor(Head, Name, Arity),
    functor(Stored, Name, Arity),
    foldl(bind_ground_column(Stored), Row, 1, _),
    (   clause(Stored, true, Ref), Stored =@= Head -> erase(Ref) ; true ).

% Every ground column of the row is bound for the clause lookup, so SWI can
% index on the most selective one.
bind_ground_column(Stored, Column, I, J) :-
    ( ground(Column) -> arg(I, Stored, Column) ; true ),
    J is I + 1.

% PeTTa arrows have one result position. Package SWI's three relational
% get_from_heap/4 outputs into one positional product.
heap_pop(Heap, [Priority, Value, Rest]) :-
    get_from_heap(Heap, Priority, Value, Rest).

% Test before popping, so a caller can pop without collecting the result: a
% collected pop copies the whole remaining heap.
'heap-empty?'(Heap, Empty) :-
    (   empty_heap(Heap) -> Empty = true ; Empty = false ).

% Hash a lookup column with every variable replaced by one marker, so a row
% keeps an integer SWI can JIT-index; =alpha on the stored key still decides.
'index-hash'(Term, Hash) :-
    (   ground(Term)
    ->  term_hash(Term, Hash)
    ;   % Hash markers must not run attributes on copied typed variables.
        % The original term keeps its constraints for actual matching.
        copy_term_nat(Term, Copy),
        term_variables(Copy, CopyVariables),
        maplist(=('goal-key-hash-variable'), CopyVariables),
        term_hash(Copy, Hash)
    ).

% A list-shaped statement is JIT-indexed by its head only, so &kb rows are also
% stored under the hash of each statement prefix: the head with its first one,
% two, ... arguments, up to the first argument that is not ground. Longest
% prefix first.
'statement-prefix-hashes'(Statement, Hashes) :-
    (   nonvar(Statement), Statement = [Head|Args], atomic(Head)
    ->  prefix_hashes(Args, [Head], [], Hashes)
    ;   Hashes = []
    ).

prefix_hashes([Arg|Args], Reversed, Hashes0, Hashes) :-
    ground(Arg), !,
    Prefix = [Arg|Reversed],
    reverse(Prefix, Statement),
    term_hash(Statement, Hash),
    prefix_hashes(Args, Prefix, [Hash|Hashes0], Hashes).
prefix_hashes(_, _, Hashes, Hashes).

% The shape a fold's member is compiled for (sk-shape-members). A user
% predicate compiles to its own lookup goal, and a connective over user
% predicates to adapters that only its structure decides, so the predicates'
% ground arguments become variables: folds that differ only in constants,
% such as one per decision step, share one compilation. Variables stay
% shared. Any other pattern (chainer vocabulary) is its own shape.
'pattern-shape'(Pattern, Shape) :-
    (   statement_shape(Pattern, Shape) -> true ; Shape = Pattern ).

connective_shape(Pattern, Shape) :-
    nonvar(Pattern), Pattern = [Connective|Children], Children \== [],
    memberchk(Connective, ['And', 'Or', 'Not']),
    maplist(statement_shape, Children, Shapes),
    Shape = [Connective|Shapes].

statement_shape(Statement, Shape) :-
    (   connective_shape(Statement, Shape) -> true
    ;   nonvar(Statement), Statement = [Head|Args], atom(Head),
        \+ memberchk(Head, ['Inheritance', 'Member', 'MemberInheritanceSample',
            'ImplicationInstanceSample', 'RuleTruth', 'Implication', 'Equivalence',
            'BiImplication', 'ForAll', 'Exists', 'WithPrior', 'Evaluation', 'Similarity',
            'Compute', 'CPU', 'FoldAll', 'FoldAllValue', 'FoldAllTruth', 'MapDist', 'Map2Dist',
            'AverageDist', 'KnownExistential', 'ExistentialResidual', 'GreaterThan', '>',
            'Assuming', 'LikelierThan']),
        maplist(argument_shape, Args, ArgShapes),
        Shape = [Head|ArgShapes] ).

argument_shape(Arg, Shape) :-
    (   ground(Arg) -> true
    ;   Shape = Arg ).

% The hypothetical context a node or key lies in, 'MAIN' for the main context
% (or one left open); a fold scoped to a context lies in it. Only an Assuming
% query's contexts are query-local: an implication's contexts hold the
% derivation of a main-context belief and stay. Fields are read without
% binding anything, so a node is not copied.
'node-context'(Node, Ctx) :-
    (   nonvar(Node), Node = [Head, _, Args|_], Head == 'CPU'
    ->  ( nonvar(Args), Args = [Scope|_] -> 'scope-context'(Scope, Ctx) ; Ctx = 'MAIN' )
    ;   nonvar(Node), Node = [_, KbCtx|_], nonvar(KbCtx), KbCtx = [_, C|_], nonvar(C) -> Ctx = C
    ;   Ctx = 'MAIN' ).

'key-context'(Key, Ctx) :-
    (   nonvar(Key), Key = [Head, _, KbCtx|_], Head == 'sk-key', nonvar(KbCtx), KbCtx = [_, C|_], nonvar(C) -> Ctx = C
    ;   nonvar(Key), Key = [Head, Args|_], Head == 'sk-fold', nonvar(Args), Args = [Scope|_] -> 'scope-context'(Scope, Ctx)
    ;   Ctx = 'MAIN' ).

'scope-context'(Scope, Ctx) :-
    (   nonvar(Scope), Scope = [_, C|_], nonvar(C) -> Ctx = C ; Ctx = 'MAIN' ).

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

% A link is recorded once, by a 60-bit digest of the link term (SHA-1 of the
% term up to variable renaming): a record stays one integer however large the
% link, and two different links share a digest with probability about
% n^2 / 2^61.
'link-digest'(Link, Digest) :-
    copy_term_nat(Link, Copy), variant_sha1(Copy, Hex),
    sub_atom(Hex, 0, 15, _, Prefix), atom_concat('0x', Prefix, Number), atom_number(Number, Digest).

% The last rule application of a proof, its premise proofs still references:
% a stored proof's own step, any other proof itself. Read by every merge and
% fold step, so one clause lookup instead of a collected match.
'sk-step-proof'(Proof, Step) :-
    (   nonvar(Proof), Proof = ['proof-ref', Pid], user:'&proof'(Pid, Stored, _, _) -> Step = Stored ; Step = Proof ).

% Hash sets (exclusion lists, unifier sets) are SWI ordered sets of key
% hashes, so union and membership are linear merges over short lists.
'hash-set'(Hashes, Set) :- sort(Hashes, Set).
'hash-union'(Left, Right, Set) :- ord_union(Left, Right, Set).

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
    size_nb_set(Live, Kept), flag(deps_gc_kept, _, Kept),
    flag(deps_next_id, Next, Next), flag(deps_gc_next, _, Next),
    forall(( clause(deps_node(Id, _, _, _), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)),
    forall(( clause(deps_cut(Id, _), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)),
    forall(( clause(deps_size_memo(Id, _), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)),
    forall(( clause(deps_leaf(Id, _), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)).
% A collection is due once more ids were interned since the last one than it
% kept (at least 4096), so its cost, a walk of the stores, stays proportional
% to what was interned.
'deps-gc-due?'(Result) :-
    flag(deps_next_id, Next, Next), flag(deps_gc_next, Last, Last), flag(deps_gc_kept, Kept, Kept),
    (   Next - Last > max(Kept, 4096) -> Result = true ; Result = false ).

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
refs_holder('&sk_merged', 5, [5]).
refs_holder('&sk_forward_taken', 3, [3]).
refs_holder('&sk_forward_stored', 5, [3, 4]).
refs_holder('&sk_summary', 5, [3, 4]).
refs_holder('&materialized_facts', 6, [5, 6]).
refs_holder('&forward_aggregate_observation', 5, [3]).
refs_holder('&combination_pending', 4, [4]).

:- dynamic refs_gc_proof/1, refs_gc_set/1, refs_gc_grey/1.

% The cycle's phase is idle, roots(Holders), mark, or sweep(Stores); its
% limits are the first proof id and the first evidence set id it did not see
% exist; its work is the clause references of the store being scanned or
% swept, the next one to take in flag refs_gc_next.
refs_gc_active :- nb_current(refs_gc_phase, Phase), Phase \== idle.

% A collection is due once more proofs were stored since the last one than it
% kept (at least 4096), as for dependency nodes.
refs_gc_due :-
    (   refs_gc_active -> true
    ;   'search-id-value'(proof_id, Next), flag(refs_gc_last, Last, Last), flag(refs_gc_kept, Kept, Kept),
        Next - Last > max(Kept, 4096) ).

% One slice, starting a cycle when one is due. Its units grow with the proofs
% stored since the last slice, so a cycle ends before as many again are
% stored, and a query that stores none pays a small constant.
'stored-refs-gc-step!'(true) :-
    'search-id-value'(proof_id, Next), flag(refs_gc_seen, Seen, Next),
    (   refs_gc_due
    ->  ( refs_gc_active -> true ; refs_gc_start ),
        Units is 512 + 8 * max(0, Next - Seen),
        refs_gc_run(Units)
    ;   true ).

% A whole collection now: the running cycle is finished, then one that starts
% now collects everything nothing reaches.
'stored-refs-gc!'(true) :-
    ( refs_gc_active -> refs_gc_run(inf) ; true ),
    refs_gc_start, refs_gc_run(inf).

refs_gc_start :-
    'search-id-value'(proof_id, ProofLimit), flag(ev_next_set, Sets, Sets), SetLimit is Sets + 1,
    nb_setval(refs_gc_limits, limits(ProofLimit, SetLimit)),
    retractall(refs_gc_proof(_)), retractall(refs_gc_set(_)), retractall(refs_gc_grey(_)),
    findall(holder(Head, Columns),
            ( refs_holder(Space, Arity, Columns), current_predicate(user:Space/Arity), functor(Head, Space, Arity) ),
            Holders),
    forall(member(holder(Head, Columns), Holders), prolog_listen(user:Head, refs_gc_removed(Columns))),
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
    (   refs_gc_follow(Units, Left) -> true
    ;   nb_getval(refs_gc_holders, Holders),
        forall(member(holder(Head, Columns), Holders), prolog_unlisten(user:Head, refs_gc_removed(Columns))),
        nb_setval(refs_gc_phase, sweep([proofs, unions, sets])), Left = Units ).
refs_gc_units(sweep([]), Units, Units) :- refs_gc_finish.
refs_gc_units(sweep([Store|Stores]), Units, Left) :-
    nb_getval(refs_gc_limits, limits(ProofLimit, SetLimit)),
    refs_gc_store(Store, Head),
    refs_gc_through(sweep(Stores), Head, Units, Left, Ref,
        ( clause(Head, true, Ref), refs_gc_dead(Store, Head, ProofLimit, SetLimit) -> refs_gc_erase(Store, Head, Ref) ; true )).

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

% Follows marked proofs to what they hold; fails when none is left.
refs_gc_follow(Units, Left) :- refs_gc_grey(_), !, refs_gc_follow_loop(Units, Left).
refs_gc_follow_loop(Units, Left) :-
    (   Units == 0 -> Left = 0
    ;   retract(refs_gc_grey(Pid))
    ->  (   user:'&proof'(Pid, Stored, Leaves, _) -> refs_gc_mark_term(Stored), refs_gc_mark_term(Leaves) ; true ),
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

refs_gc_erase(proofs, user:'&proof'(Pid, _, _, _), Ref) :- !, erase(Ref), retractall(user:'&proof_fact'(Pid, _, _)).
refs_gc_erase(_, _, Ref) :- erase(Ref).

refs_gc_finish :-
    aggregate_all(count, refs_gc_proof(_), Marked),
    nb_getval(refs_gc_limits, limits(ProofLimit, _)), 'search-id-value'(proof_id, Next),
    Kept is Marked + Next - ProofLimit, flag(refs_gc_kept, _, Kept), flag(refs_gc_last, _, Next),
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
    foldl(deps_near_step, Ids, [], Near0), sort(Near0, Near),
    include(deps_held_twice(Ids), Near, Hashes).
deps_near_step(Id, Acc0, Acc) :- deps_near(Id, 2, Near), append(Near, Acc0, Acc).
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

ev_entry_id(Entry, Id) :-
    'index-hash'(Entry, Hash),
    (   ev_entry(Id, Hash, Stored), Stored =@= Entry -> true
    ;   flag(ev_next_entry, Last, Last + 1), Id is Last + 1,
        assertz(ev_entry(Id, Hash, Entry)) ).

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

% The union of the sets in order.
'evidence-join'(Sets, ['ev-set', Set]) :-
    foldl([['ev-set', S], Acc0, Acc]>>ev_union(Acc0, S, Acc), Sets, 0, Set).

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
% other entry is wrapped.
'evidence-negated'(['ev-set', A], ['ev-set', C]) :-
    ev_order(A, Ids), maplist(ev_negated_id, Ids, Negated), ev_of_ids(Negated, C).
ev_negated_id(Id, Negated) :-
    ev_entry(Id, _, Entry),
    (   Entry = ['fact-ev', Kb, Proof, Type] -> Not = ['not-fact-ev', Kb, Proof, Type]
    ;   Entry = ['not-fact-ev', Kb, Proof, Type] -> Not = ['fact-ev', Kb, Proof, Type]
    ;   Not = ['not-ev', Entry] ),
    ev_entry_id(Not, Negated).

% The entries other than rules that A shares with B, in reverse of A's order.
'evidence-shared-facts'(['ev-set', A], ['ev-set', B], Entries) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ord_intersection(SortedA, SortedB, Shared),
    (   Shared == [] -> Entries = []
    ;   ev_order(A, IdsA), ev_keep(IdsA, Shared, Kept), reverse(Kept, Reversed),
        convlist(ev_fact_entry, Reversed, Entries) ).

% The entries other than rules that every set holds: the first set's entries,
% kept by each set in turn, each keeping reversing the order.
'evidence-common-facts'([['ev-set', First]|Sets], Entries) :-
    ev_order(First, Ids), ev_sorted(First, Sorted),
    foldl(ev_common_step, [['ev-set', First]|Sets], Ids-Sorted, Common-_),
    convlist(ev_fact_entry, Common, Entries).
ev_common_step(['ev-set', Set], Ids-Sorted, Kept-Shared) :-
    ev_sorted(Set, SortedSet), ord_intersection(Sorted, SortedSet, Shared),
    (   Shared == [] -> Kept = [] ; ev_keep(Ids, Shared, InOrder), reverse(InOrder, Kept) ).

% Whether B uses a rule that one of A's excluded-rule entries names.
'evidence-excludes?'(['ev-set', A], ['ev-set', B], Result) :-
    ev_excluded(A, Excluded),
    (   Excluded \== [], ev_sorted(B, SortedB), ord_intersect(Excluded, SortedB) -> Result = true ; Result = false ).

% A rule is dormant when one of its statement premises can be proved, apart
% from a stored fact, only through the rule's own conclusion with the same
% arguments: self-support exclusion would drop whatever it derives
% (docs/metta/dormant_rules.md). The search runs backward over rules and
% facts on patterns, bounded: past the bound a premise counts as supported,
% so a useful rule is never put to sleep. Forward copies of derived values
% are not support. The verdict is memoized per rule with the heads the
% search found no fact for; a new fact with one of those heads, or any new
% rule, wakes the rule for another look. A rule application concluding a
% complete predicate is never dormant: its join is how a closed read sees
% that a derivation exists (docs/metta/complete_predicates.md). An
% antecedent completion reads the other parts of the antecedent at their
% population prior when nothing else gives them a value (sk-start-prior!), so
% a part that no rule application concludes and that is not complete
% supports it.
:- dynamic rule_dormancy/3.

'rule-dormant?'(Id, Dormant) :-
    (   rule_dormancy(Id, Dormant, _) -> true
    ;   dormancy_analysis(Id, Dormant, Heads), assertz(rule_dormancy(Id, Dormant, Heads)) ).

dormancy_analysis(Id, Dormant, Heads) :-
    nb_setval(dormancy_budget, 2000), nb_setval(dormancy_heads, []),
    (   dormancy_row(rules('runtime-rule-row', Id, [Type, Ctx, Proof|_], Premises)),
        \+ ( ( Proof = [by|_] ; Proof = [negated, [by|_]] ),
             Ctx = [Kb|_], statement_head(Type, Head), dormancy_row('&complete_predicates'(Kb, Head)) ),
        member([PType, PCtx, _, _], Premises), PType \== 'CPU',
        \+ dormancy_premise_supported(Proof, PType, PCtx, Type-Ctx, [], 8)
    ->  Dormant = true
    ;   Dormant = false ),
    nb_getval(dormancy_heads, Heads0), sort(Heads0, Heads).

dormancy_supported(Type, Ctx, Forbidden, Path, Depth) :-
    nb_getval(dormancy_budget, Budget),
    (   Budget =< 0 -> true
    ;   Budget1 is Budget - 1, nb_setval(dormancy_budget, Budget1),
        (   Type-Ctx == Forbidden -> fail
        ;   dormancy_complete(Type, Ctx) -> true
        ;   member(Seen, Path), Seen =@= Type-Ctx -> fail
        ;   Depth =< 0 -> true
        ;   \+ dormancy_judged(Type, Ctx) -> true
        ;   dormancy_fact(Type, Ctx) -> true
        ;   \+ dormancy_row(rules('runtime-rule-row', _, [Type, Ctx|_], _)) -> true
        ;   dormancy_note_head(Type),
            Depth1 is Depth - 1,
            dormancy_row(rules('runtime-rule-row', _, [Type, Ctx, Proof|_], Premises)),
            (   memberchk(['CPU', 'SettlesFormula'|_], Premises) -> \+ \+ dormancy_settles(Premises)
            ;   forall(( member([PType, PCtx, _, _], Premises), PType \== 'CPU' ),
                       dormancy_premise_supported(Proof, PType, PCtx, Forbidden, [Type-Ctx|Path], Depth1)) ) ) ).

dormancy_premise_supported(Proof, Type, Ctx, Forbidden, Path, Depth) :-
    (   Type-Ctx \== Forbidden, Proof = [['antecedent-completion'|_]|_], \+ dormancy_derived(Type, Ctx) -> true
    ;   dormancy_supported(Type, Ctx, Forbidden, Path, Depth) ).

dormancy_derived(Type, Ctx) :-
    (   dormancy_complete(Type, Ctx) -> true
    ;   \+ \+ ( dormancy_row(rules('runtime-rule-row', _, [Type, Ctx, Proof|_], _)),
                 ( Proof = [by|_] ; Proof = [negated, [by|_]] ) ) ).

% A complete statement always has a value once its search settles: its rule
% applications read closed, and with none it is unfounded, false
% (docs/metta/complete_predicates.md). So it supports a reader even when its
% only derivations run through a loop back to it: a loop disjunct read closed
% is false, and the rest of its antecedent decides.
dormancy_complete(Type, [Kb|_]) :-
    statement_head(Type, Head), dormancy_row('&complete_predicates'(Kb, Head)).

% A settled rule reads only a part whose certain stored fact settles its
% compound (docs/metta/connective_settling.md), so it supports its conclusion
% only through such a fact: the part's formulas run on the fact up to the
% settling check. A refined rule's truth goal is supported.
dormancy_settles([['CPU', 'SettlesFormula', Args, Res]|_]) :- !,
    append(Args, [Out], CallArgs), G =.. ['SettlesFormula'|CallArgs],
    catch(G, _, fail), Out = Res.
dormancy_settles([['CPU', Fun, Args, Res]|Rest]) :- !,
    append(Args, [Out], CallArgs), G =.. [Fun|CallArgs],
    catch(G, _, fail), Out = Res, dormancy_settles(Rest).
dormancy_settles([[['RuleTruth'|_], _, _, _]|Rest]) :- !, dormancy_settles(Rest).
dormancy_settles([[Type, Ctx, Proof, Tv]|Rest]) :-
    dormancy_row('&kb'(Type, Ctx, Proof, Tv)), Tv = ['STV', _, C], number(C), C >= 1.0,
    dormancy_settles(Rest).

% A statement no fact and no rule speaks of yet is an input still to come,
% not one only the rule's conclusion supports, so it counts as supported.
% The search judges only what it fully sees: user predicates in the main
% context (or one a rule leaves open). An assumption context supplies its own
% premises, and the chainer's own vocabulary has support the search does not
% model: rules installed when a node expands (implications, member
% inheritance), member folds and samples. Anything else counts as supported.
dormancy_judged(Type, [_, Context|_]) :-
    ( var(Context) ; Context == 'MAIN' ),
    \+ ( Type = [Head|_], memberchk(Head, ['Inheritance', 'Member', 'MemberInheritanceSample',
        'ImplicationInstanceSample', 'RuleTruth', 'Implication', 'Equivalence', 'And', 'Or', 'Not',
        'ForAll', 'WithPrior', 'Evaluation', 'Similarity']) ).

dormancy_fact(Type, Ctx) :-
    \+ \+ ( dormancy_row('&kb'(Type, Ctx, Proof, Tv)),
            \+ ( 'index-hash'(['sk-key', Type, Ctx], Hash),
                 dormancy_row('&sk_forward_stored'(Hash, _, Copy, _, _)), Copy == [Type, Ctx, Proof, Tv] ) ).

% A space has no clauses, and so no predicate, until its first row.
dormancy_row(Row) :- catch(user:Row, error(existence_error(procedure, _), _), fail).

dormancy_note_head(Type) :-
    (   Type = [Head|_] -> true ; Head = Type ),
    nb_getval(dormancy_heads, Heads), nb_setval(dormancy_heads, [Head|Heads]).

% The dormant rules a new fact or query rule concluding this statement could
% wake; their verdicts are dropped. A statement of any head may wake any.
'rule-dormancy-wake!'(Type, Ids) :-
    statement_head(Type, Head),
    (   Head == '$var' -> 'rule-dormancy-reset!'(Ids)
    ;   findall(Id, ( rule_dormancy(Id, true, Heads), memberchk(Head, Heads) ), Ids0), sort(Ids0, Ids),
        forall(member(Id, Ids), retractall(rule_dormancy(Id, _, _))) ).

% A query's own rules leave with it, and so do their verdicts.
'rule-dormancy-forget-temp!'(true) :-
    forall(( rule_dormancy(Id, _, _), Id >= 1000000000 ), retractall(rule_dormancy(Id, _, _))).

% A new rule can give any premise support: every dormant rule is looked at
% again, and every verdict is dropped.
'rule-dormancy-reset!'(Ids) :-
    findall(Id, rule_dormancy(Id, true, _), Ids0), sort(Ids0, Ids),
    retractall(rule_dormancy(_, _, _)).

% A permanent rule can change what any context's assumptions affect; a query's
% own rules are compiled into its contexts before their premises are placed.
'context-affected-reset!'(true) :- retractall(context_affected_memo(_, _)).

% A context removed with its query leaves no mark.
'context-forget!'(Ctx, true) :- retractall(world_context(Ctx, _)), retractall(context_affected_memo(Ctx, _)).

% Contexts of `Assuming` queries see the world: the main context's facts and
% keys stay readable there, and a premise is placed in the context only when the
% assumptions can change it (docs/metta/assumption_queries.md).
:- dynamic world_context/2, context_affected_memo/2.

% A world context keeps the heads its assumed facts state, so finding what the
% assumptions affect reads the query's facts, not every stored fact.
'context-world!'([_, Ctx|_], Facts, true) :-
    (   world_context(Ctx, _) -> true
    ;   findall(H, ( fact_conjunct(Facts, F), assumed_head(F, H) ), Heads0),
        sort(Heads0, Heads), assertz(world_context(Ctx, Heads)) ).

fact_conjunct(Facts, F) :-
    (   nonvar(Facts), Facts = ['And'|Conjuncts] -> member(C, Conjuncts), fact_conjunct(C, F)
    ;   F = Facts ).

'context-world?'(Ctx, Result) :- ( nonvar(Ctx), world_context(Ctx, _) -> Result = true ; Result = false ).

% Whether a world context's assumptions can change a statement: its head is
% stated in the context (an assumption, the statement a negated one negates,
% or the conclusion of a rule the query compiled into it), or concluded by a
% rule that is not dormant and one of whose premises, or the members a fold
% premise reads, has an affected head. A variable head may be anything, so it
% counts as affected, and a rule concluding a variable head from an affected
% premise affects everything. Computed once per context and dropped when a
% rule is added.
'context-affected?'(Ctx, Type, Result) :-
    (   context_affected_memo(Ctx, Heads) -> true
    ;   context_affected_heads(Ctx, Heads), assertz(context_affected_memo(Ctx, Heads)) ),
    statement_head(Type, Head),
    (   ( Heads == all ; Head == '$var' ; memberchk(Head, Heads) ) -> Result = true ; Result = false ).

% Whether a world context's assumptions can change some member a fold over a
% pattern reads: any conjunct of the pattern is affected.
'context-pattern-affected?'(Ctx, Pattern, Result) :-
    (   context_affected_memo(Ctx, Heads) -> true
    ;   context_affected_heads(Ctx, Heads), assertz(context_affected_memo(Ctx, Heads)) ),
    (   ( Heads == all ; pattern_head(Pattern, H), ( H == '$var' ; memberchk(H, Heads) ) )
    ->  Result = true ; Result = false ).

context_affected_heads(Ctx, Heads) :-
    world_context(Ctx, FactHeads),
    findall(H, ( dormancy_row(rules('runtime-rule-row', _, [T, [_, C|_]|_], _)),
                 C == Ctx, assumed_head(T, H) ), RuleHeads),
    append(FactHeads, RuleHeads, Seeds0), sort(Seeds0, Seeds),
    findall(CH-PHs, ( dormancy_row(rules('runtime-rule-row', Id, [CT|_], Ps)),
                      'rule-dormant?'(Id, false), statement_head(CT, CH),
                      findall(PH, ( member(P, Ps), premise_head(P, PH) ), PHs) ), Edges),
    affected_fixpoint(Seeds, Edges, Heads).

assumed_head(T, H) :-
    (   nonvar(T), T = ['Not', Inner] -> ( statement_head(T, H) ; statement_head(Inner, H) )
    ;   statement_head(T, H) ).

statement_head(T, H) :-
    (   var(T) -> H = '$var'
    ;   T = [H0|_] -> ( var(H0) -> H = '$var' ; H = H0 )
    ;   H = T ).

premise_head(['CPU', Fun, Args|_], H) :- !,
    memberchk(Fun, ['FoldAllCompiled', 'GroupedFoldAllCompiled']),
    nonvar(Args), Args = [_, Pattern|_], pattern_head(Pattern, H).
premise_head([T|_], H) :- statement_head(T, H).

pattern_head(Pattern, H) :-
    (   nonvar(Pattern), Pattern = ['And'|Conjuncts] -> member(C, Conjuncts), pattern_head(C, H)
    ;   statement_head(Pattern, H) ).

affected_fixpoint(Heads, Edges, Result) :-
    (   memberchk('$var', Heads) -> Result = all
    ;   member(CH-PHs, Edges), \+ memberchk(CH, Heads),
        member(PH, PHs), ( PH == '$var' ; memberchk(PH, Heads) )
    ->  affected_fixpoint([CH|Heads], Edges, Result)
    ;   Result = Heads ).

% The trie compares variants exactly, without binding caller variables or
% confusing hash collisions. Destroy query-local storage even on an exception.
alpha_unique_keys(Keys, Unique) :-
    setup_call_cleanup(trie_new(Seen), alpha_unique_keys(Keys, Seen, Unique),
                       trie_destroy(Seen)).

alpha_unique_keys([], _, []).
alpha_unique_keys([Key|Keys], Seen, Unique) :-
    copy_term_nat(Key, Plain),
    (   trie_insert(Seen, Plain)
    ->  Unique = [Key|Rest]
    ;   Unique = Rest
    ),
    alpha_unique_keys(Keys, Seen, Rest).

% An answer is redundant when another answer with the same proof has a
% strictly more general statement, or a variant statement earlier in the list:
% of answers that instantiate each other, the first stays. Only identical
% ground proofs are compared; nonground proofs cannot be identical after the
% independent copies used for subsumption. The local index shares the inputs;
% findall retains order and copies each survivor just as MeTTa's collapse does,
% isolating variables between returned answers.
prune_answer_instances(Answers, Kept) :-
    numbered_answers(Answers, 1, Numbered),
    empty_assoc(Empty),
    reverse(Numbered, Reversed),
    foldl(index_answer_proof, Reversed, Empty, Index),
    findall(Answer, (member(Position-Answer, Numbered),
                     \+ answer_instance(Index, Position, Answer)), Kept).

numbered_answers([], _, []).
numbered_answers([Answer|Answers], Position, [Position-Answer|Numbered]) :-
    Next is Position + 1,
    numbered_answers(Answers, Next, Numbered).

index_answer_proof(Position-Answer, Before, After) :-
    (   nonvar(Answer), Answer = [_, _, Proof, _], ground(Proof)
    ->  (get_assoc(Proof, Before, Previous) -> true ; Previous = []),
        put_assoc(Proof, Before, [Position-Answer|Previous], After)
    ;   After = Before
    ).

answer_instance(Index, Position, Answer) :-
    nonvar(Answer), Answer = [_, _, Proof, _], ground(Proof),
    get_assoc(Proof, Index, Candidates),
    member(Other-General, Candidates),
    Other \== Position,
    '=alpha'(Answer, General, false),
    copy_term(Answer, [SpecificType, _, _, _]),
    copy_term(General, [GeneralType, _, _, _]),
    subsumes_term(GeneralType, SpecificType),
    (   Other < Position
    ->  true
    ;   \+ subsumes_term(SpecificType, GeneralType)
    ),
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
    take_particle_anchors(Budget, Sorted, Anchors0, Overflow),
    predsort(compare_particle_index, Anchors0, Anchors),
    absorb_overflow_particles(Overflow, Anchors, Merged),
    predsort(compare_particle_index, Merged, Ordered),
    particle_components_pairs(Ordered, Result).

indexed_particle_pairs([], _, []).
indexed_particle_pairs([[Value, Weight]|Rest], Index,
        [key(NegativeWeight, Index)-component(Index, Value, Weight)|Ranked]) :-
    NegativeWeight is -Weight,
    NextIndex is Index + 1,
    indexed_particle_pairs(Rest, NextIndex, Ranked).

take_particle_anchors(0, Rest, [], Rest) :- !.
take_particle_anchors(_, [], [], []).
take_particle_anchors(Count, [_-Component|Rest], [Component|Anchors], Overflow) :-
    NextCount is Count - 1,
    take_particle_anchors(NextCount, Rest, Anchors, Overflow).

compare_particle_index(Order, component(LeftIndex, _, _),
        component(RightIndex, _, _)) :-
    compare(Order, LeftIndex, RightIndex).

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
        prefer_particle_anchor(
            Best0, candidate(Cost, AnchorIndex, Mean, MergedWeight), Best1)
    ;   Best1 = Best0
    ),
    closest_particle_anchor(
        Rest, component(_, Value, Weight), Best1, Best).

prefer_particle_anchor(none, candidate(Cost, Index, Value, Weight),
        best(Cost, Index, Value, Weight)).
prefer_particle_anchor(best(BestCost, BestIndex, BestValue, BestWeight),
        candidate(Cost, Index, Value, Weight), Best) :-
    (   Cost < BestCost
    ->  Best = best(Cost, Index, Value, Weight)
    ;   Best = best(BestCost, BestIndex, BestValue, BestWeight)
    ).

replace_particle_anchor(
        [component(Index, _, _)|Rest], Index, Value, Weight,
        [component(Index, Value, Weight)|Rest]) :- !.
replace_particle_anchor([Anchor|Rest], Index, Value, Weight,
        [Anchor|Updated]) :-
    replace_particle_anchor(Rest, Index, Value, Weight, Updated).

particle_components_pairs([], []).
particle_components_pairs(
        [component(_, Value, Weight)|Rest], [[Value, Weight]|Pairs]) :-
    particle_components_pairs(Rest, Pairs).

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

% A counter's value (change-state!), 0 before it is set.
'search-id-value'(Key, Value) :- ( nb_current(Key, Stored) -> Value = Stored ; Value = 0 ).

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
    (   nb_current(pettachainer_query_metrics_enabled, Stored)
    ->  Enabled = Stored
    ;   Enabled = false
    ).

query_metrics_set_enabled(Enabled, Enabled) :-
    nb_setval(pettachainer_query_metrics_enabled, Enabled).

query_metric_global_key(Key, GlobalKey) :-
    atom_concat(pettachainer_query_metric_, Key, GlobalKey).

query_metric_value(Key, Value) :-
    query_metric_global_key(Key, GlobalKey),
    (   nb_current(GlobalKey, Stored)
    ->  Value = Stored
    ;   Value = 0
    ).

query_metric_set(Key, Value, Result) :-
    query_metrics_enabled(Enabled),
    (   Enabled == true
    ->  query_metric_global_key(Key, GlobalKey),
        nb_setval(GlobalKey, Value)
    ;   true
    ),
    Result = Value.

query_metric_increment(Key, Result) :-
    query_metrics_enabled(Enabled),
    (   Enabled == true
    ->  query_metric_increment_enabled(Key, Result)
    ;   Result = 0
    ).

query_metric_increment_enabled(Key, Result) :-
    query_metric_global_key(Key, GlobalKey),
    (   nb_current(GlobalKey, Old)
    ->  true
    ;   Old = 0
    ),
    Result is Old + 1,
    nb_setval(GlobalKey, Result).

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

% A stored proof is a DAG: each view's proof is one rule application whose
% premise proofs are references to stored proofs. Expanding it as a tree
% repeats every shared subproof, exponentially in how deeply values build on
% merged values. The expansion instead prints a subproof that is referenced
% more than once and itself refers to stored proofs in full at its first
% occurrence, as (shared Id Proof), and as (shared Id) after that; a shared
% subproof with no references of its own is a fixed-size term and is printed
% where it occurs. Both passes visit each stored proof once.
proof_dag_expand(Proof, Out) :-
    empty_assoc(E),
    proof_ref_counts(Proof, E, Counts),
    proof_dag_term(Proof, Counts, E, _, Out).

proof_ref_counts(T, C0, C) :-
    (   var(T) -> C = C0
    ;   T = ['proof-ref', Pid]
    ->  (   get_assoc(Pid, C0, N)
        ->  N1 is N + 1, put_assoc(Pid, C0, N1, C)
        ;   put_assoc(Pid, C0, 1, C1),
            (   '&proof'(Pid, Stored, _, _) -> proof_ref_counts(Stored, C1, C) ; C = C1 )
        )
    ;   is_list(T) -> foldl(proof_ref_counts, T, C0, C)
    ;   C = C0
    ).

proof_dag_term(T, Counts, D0, D, Out) :-
    (   var(T) -> Out = T, D = D0
    ;   T = ['proof-ref', Pid], '&proof'(Pid, Stored, _, _)
    ->  (   get_assoc(Pid, Counts, N), N > 1, proof_has_ref(Stored)
        ->  (   get_assoc(Pid, D0, _)
            ->  Out = [shared, Pid], D = D0
            ;   put_assoc(Pid, D0, true, D1),
                proof_dag_term(Stored, Counts, D1, D, X),
                Out = [shared, Pid, X]
            )
        ;   proof_dag_term(Stored, Counts, D0, D, Out)
        )
    ;   is_list(T) -> proof_dag_list(T, Counts, D0, D, Out)
    ;   Out = T, D = D0
    ).

proof_dag_list([], _, D, D, []).
proof_dag_list([T|Ts], Counts, D0, D, [O|Os]) :-
    proof_dag_term(T, Counts, D0, D1, O),
    proof_dag_list(Ts, Counts, D1, D, Os).

proof_has_ref(T) :-
    nonvar(T),
    (   T = ['proof-ref', _] -> true
    ;   is_list(T), member(E, T), proof_has_ref(E) -> true
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

% Hypothesis mining (docs/metta/hypothesis_rules.md, "Mining hypotheses").
% The candidate implications between Fact, of layer Layer at its time point,
% and its Features, as [Antecedent, Consequent, Sighting]: its singles, then
% its pairs. A feature is [Statement, Layer, Relation]: a true fact sharing a
% constant with Fact at Fact's time point (Relation now), or at the time point
% a link fact makes the previous or next one ([earlier, Link] or [later,
% Link]). Causes precede effects: at one time point a fact of a lower layer is
% an antecedent of one of a higher layer, and across a link the earlier fact
% is, with the link as a conjunct; equal layers order nothing. At one time
% point each constant an antecedent shares with the consequent becomes a
% variable; across a link only the two time points do, so persistence is
% per entity, (And (NextPeriod $q $p) (Storm north $q)) -> (Storm north $p):
% the general (Storm $r $q) form is recursive over every entity at once, and
% its fold took 229 s and 2.5 GB after a SupplyNet stage 2 history where the
% three regions' rules took 7 s (with Late and Blocked persistence alike it
% ran out of memory).
%
% A pair concludes a fact of the time point from two of a lower layer, one of
% them Fact (ordered as ground terms, so a pair is one candidate); a pair
% whose two facts share a constant apart from the consequent also gives its
% relational form, with that constant a variable too: (And (Sample $x $t)
% (LeftStim $x $t)). Its Sighting is none. A single concludes one fact from
% another; its Sighting is the hash of its consequent and the hash of the
% facts of a lower layer at the consequent's time point it does not read,
% generalized alike, so the miner can tell whether it recurs where the pairs
% of its first sighting do not explain it (without one, no pair could, and
% the hash is the consequent's, which differs at every instance).
'hypothesis-candidates'(Fact, Layer, Features, Candidates) :-
    findall(Single, hypothesis_single(Fact, Layer, Features, Single), Singles),
    findall(F-L, member([F, L, now], Features), Now),
    findall([A, C, none],
            ( (   pair_below(Now, Layer, Pair), Consequent = Fact
              ;   select(Consequent-LC, Now, Rest), Layer < LC,
                  member(B-LB, Rest), LB < LC, msort([Fact, B], Pair) ),
              hypothesis_pair_rule(Pair, Consequent, [A, C]) ),
            Pairs),
    append(Singles, Pairs, Candidates).

hypothesis_single(Fact, Layer, Features, [A, C, [Instance, Context]]) :-
    member([F, L, Relation], Features),
    single_order(Relation, Fact, Layer, F, L, Antecedents, Consequent, Above),
    (   Antecedents = [[_, Earlier, Later], _]
    ->  generalized_rule(Antecedents, Consequent, [Earlier, Later], [A, C], Subst)
    ;   hypothesis_rule(Antecedents, Consequent, [], [A, C], Subst) ),
    term_hash(Consequent, Instance),
    findall(G, ( Above \== none, member([G, LG, now], Features), LG < Above, G \== Consequent,
                 \+ memberchk(G, Antecedents) ), Others),
    maplist(generalize_statement(Subst), Others, General0), msort(General0, General),
    ( General == [] -> Context = Instance ; 'index-hash'(General, Context) ).

% The antecedents and consequent of a single, and the layer below which the
% facts at Fact's time point could explain the consequent too (none for a
% consequent at the next time point, whose own are not read).
single_order(now, Fact, Layer, F, L, [F], Fact, Layer) :- L < Layer.
single_order(now, Fact, Layer, F, L, [Fact], F, L) :- Layer < L.
single_order([earlier, Link], Fact, Layer, F, _, [Link, F], Fact, Layer).
single_order([later, Link], Fact, _, F, _, [Link, Fact], F, none).

pair_below(Now, Layer, Pair) :-
    append(_, [F1-L1|Rest], Now), L1 < Layer, member(F2-L2, Rest), L2 < Layer, msort([F1, F2], Pair).

% The pairs that vary a failed prediction: Live holds the [Antecedent,
% Consequent] of live hypotheses concluding Fact's pattern; one whose
% antecedent holds of Features predicted Fact, and the pairs concluding Fact
% that contain one of the features it read can learn where it fails.
'hypothesis-exception-pairs'(Fact, Layer, Features, Live, Pairs) :-
    findall(F, member([F|_], Features), Statements),
    findall(F, ( member(Rule, Live), copy_term(Rule, [A, Fact]), rule_conjuncts(A, Conjuncts),
                 features_read(Conjuncts, Statements), member(F, Conjuncts) ), Read0),
    sort(Read0, Read),
    findall(F-L, member([F, L, now], Features), Now),
    findall([A, C, none], ( pair_below(Now, Layer, Pair), hypothesis_pair_rule(Pair, Fact, [A, C]), rule_conjuncts(A, Conjuncts),
                            once(( member(Conjunct, Conjuncts), member(F, Read), subsumes_term(Conjunct, F) )) ), Pairs).

features_read([], _).
features_read([Conjunct|Conjuncts], Features) :- memberchk(Conjunct, Features), features_read(Conjuncts, Features).

hypothesis_pair_rule(Pair, Fact, Rule) :-
    hypothesis_rule(Pair, Fact, [], Rule, _).
hypothesis_pair_rule([A, B], Fact, Rule) :-
    shared_constants(A, B, Both), shared_constants(A, Fact, ToA), shared_constants(B, Fact, ToB),
    subtract(Both, ToA, Own0), subtract(Own0, ToB, Own), Own \== [],
    hypothesis_rule([A, B], Fact, Own, Rule, _).

hypothesis_rule(Features, Fact, Own, Rule, Subst) :-
    maplist(shared_constants(Fact), Features, Shared),
    append([Own|Shared], Joins0), sort(Joins0, Joins),
    generalized_rule(Features, Fact, Joins, Rule, Subst).

generalized_rule(Features, Fact, Joins, [Antecedent, Consequent], Subst) :-
    findall(K-_, member(K, Joins), Subst),
    maplist(generalize_statement(Subst), Features, Conjuncts),
    generalize_statement(Subst, Fact, Consequent),
    ( Conjuncts = [Antecedent] -> true ; Antecedent = ['And'|Conjuncts] ).

shared_constants([_|Xs], [_|Ys], Shared) :-
    include(atomic, Xs, As), include(atomic, Ys, Bs), intersection(As, Bs, Common), sort(Common, Shared).

generalize_statement(Subst, [Head|Args], [Head|General]) :-
    maplist(generalize_argument(Subst), Args, General).
generalize_argument(Subst, Arg, General) :-
    ( atomic(Arg), memberchk(Arg-Var, Subst) -> General = Var ; General = Arg ).

% A statement's place in time, [Time, Layer], from its predicate's declared
% [Position, Layer], where Time is the constant at argument Position; []
% when there is none.
'hypothesis-place'(Statement, [Position, Layer], Place) :-
    ( nth0(Position, Statement, Time), atomic(Time), Time \== [] -> Place = [Time, Layer] ; Place = [] ).

% A statement's distinct constant arguments, the values it can join on.
'hypothesis-constants'([_|Args], Constants) :-
    include(atomic, Args, Constants0), sort(Constants0, Constants).

% The patterns a fact is an instance of: the fact with each nonempty set of
% its distinct constant arguments turned into variables.
'hypothesis-patterns'([Head|Args], Patterns) :-
    'hypothesis-constants'([Head|Args], Constants),
    findall(Pattern, ( subset_of(Constants, Joins), Joins \== [],
                       findall(K-_, member(K, Joins), Subst),
                       generalize_statement(Subst, [Head|Args], Pattern) ), Patterns).

subset_of([], []).
subset_of([X|Xs], [X|Ys]) :- subset_of(Xs, Ys).
subset_of([_|Xs], Ys) :- subset_of(Xs, Ys).

% A candidate is screened off by a more general one: one whose antecedent
% conjuncts, under a substitution taking its consequent to the candidate's,
% are some of the candidate's.
'hypothesis-generalizes?'(General, Specific, Bool) :-
    (   General = ['Implication', GA, GC], Specific = ['Implication', SA, SC],
        \+ General =@= Specific,
        rule_conjuncts(GA, Gs), rule_conjuncts(SA, Ss),
        length(Gs, N), length(Selected, N), selected_conjuncts(Selected, Ss),
        subsumes_term([GC|Gs], [SC|Selected])
    ->  Bool = true
    ;   Bool = false ).

rule_conjuncts(['And'|Conjuncts], Conjuncts) :- !.
rule_conjuncts(Conjunct, [Conjunct]).

selected_conjuncts([], _).
selected_conjuncts([X|Xs], Ys) :- select(X, Ys, Rest), selected_conjuncts(Xs, Rest).

'hypothesis-name'(N, Name) :- atom_concat('hypothesis-', N, Name).

% A fact's features from the [Seq, Statement, Time, Layer] rows recorded
% for its constants: the newest Max distinct statements at its time point
% Time or at one a link fact among Links makes the previous or next one, as
% [Statement, Layer, Relation] (see hypothesis-candidates).
'hypothesis-features'(Fact, Time, Rows, Links, Max, Features) :-
    findall(Key-[S, L, Relation], ( member([Seq, S, T, L], Rows), S \== Fact,
                                    feature_relation(Time, T, Links, Relation), Key is -Seq ), Keyed),
    keysort(Keyed, Sorted), pairs_values(Sorted, Features0), list_to_set(Features0, Features1),
    length(Features1, N), M is min(Max, N), length(Features, M), append(Features, _, Features1).

feature_relation(Time, Time, _, now) :- !.
feature_relation(Time, T, Links, [earlier, Link]) :- member(Link, Links), Link = [_, T, Time], !.
feature_relation(Time, T, Links, [later, Link]) :- member(Link, Links), Link = [_, Time, T], !.

% The live hypotheses under review, each ['hm-reviewed', Name, Antecedent,
% Consequent, Born, _], with the truth the review's query answered for it:
% its root's most confident answer among the query-result rows, or
% no-evidence.
'hypothesis-truths'(Live, Rows, Reviewed) :-
    findall(['hm-reviewed', Name, A, C, Born, Best],
            ( nth0(I, Live, ['hm-reviewed', Name, A, C, Born, _]),
              findall(Conf-TV, ( member(['query-result', I, [':', _, _, TV]], Rows), hypothesis_confidence(TV, Conf) ), Answers),
              ( Answers == [] -> Best = 'no-evidence' ; max_member(_-Best, Answers) ) ),
            Reviewed).

hypothesis_confidence(['STV', _, C], C).
hypothesis_confidence(['CTV', ['STV', _, C], _], C).

% The live hypotheses under review grouped by their consequent's layer
% (set-predicate-time), lowest first.
'hypothesis-layers'(KB, Live, Groups) :-
    findall(Layer-Reviewed, ( member(Reviewed, Live), Reviewed = ['hm-reviewed', _, _, [Head|_], _, _],
                              '&hm_time'(Head, KB, _, Layer) ), Keyed),
    keysort(Keyed, Sorted), group_pairs_by_key(Sorted, ByLayer), pairs_values(ByLayer, Groups).

% How many of the live hypotheses under review no review had read, which
% this review reads: their &hm_unread rows are removed.
'hypothesis-read!'(KB, Live, Count) :-
    aggregate_all(count, ( member(['hm-reviewed', Name|_], Live), retract('&hm_unread'(Name, KB)) ), Count).

% --- Pending work (skeleton.metta, "Pending work") ---------------------------
%
% Which nodes' searches may still have work: the node or one below it is
% unexpanded or holds parked deliveries, deferred joins or deferred rows. A
% skeleton is cyclic (inverted rules, a rule's truth read through its own
% instances), and every node of a cycle reaches what any of them reaches, so
% the nodes are kept as their strongly connected components, condensed into an
% acyclic graph. A component counts its nodes' work items and its child
% components that are pending; it is pending while either count is positive.
% A change in a component's state moves its parents' counts, up to the first
% parent whose state stays, so the state is always exact and a lookup is a
% union-find step.
%
% A child link joins two components when the child's component reaches the
% owner's: a search forward from the child and backward from the owner, one
% component at a time each, until one side is exhausted, so it costs the
% smaller side (a new node has no children, a new root no parents). The
% components on the paths from child to owner become one.
%
% pw_id(NodeHash, Node, Id); pw_up(Id, Parent) for a merged id; for a
% component Rep: pw_size(Rep, Nodes), pw_work(Rep, Items), pw_pend(Rep,
% PendingChildren), pw_deg(Rep, Children, Parents); pw_out(Rep, Child, Links)
% and pw_in(Child, Rep, Links) for the condensed edges, with the child links
% each stands for.
:- dynamic pw_id/3, pw_up/2, pw_size/2, pw_work/2, pw_pend/2, pw_deg/3, pw_out/3, pw_in/3.
:- dynamic('&sk_expanded'/2), dynamic('&sk_child'/4), dynamic('&sk_parked'/3),
   dynamic('&sk_deferred_joins'/3), dynamic('&sk_deferred'/3).

% A node's id, created with one work item when the node is unexpanded.
pw_node(H, N, Id) :-
    (   pw_known(H, N, Id) -> true
    ;   flag(pw_next_id, Id, Id + 1),
        assertz(pw_id(H, N, Id)),
        ( '&sk_expanded'(H, S), attribute_free_variant(S, N) -> W = 0 ; W = 1 ),
        assertz(pw_size(Id, 1)), assertz(pw_work(Id, W)), assertz(pw_pend(Id, 0)), assertz(pw_deg(Id, 0, 0))
    ).

pw_known(H, N, Id) :- pw_id(H, S, Id), attribute_free_variant(S, N), !.

pw_find(Id, Rep) :-
    (   pw_up(Id, Up)
    ->  pw_find(Up, Rep),
        ( Up == Rep -> true ; retract(pw_up(Id, Up)), assertz(pw_up(Id, Rep)) )
    ;   Rep = Id
    ).

pw_pending_rep(R) :- ( pw_work(R, W), W > 0 -> true ; pw_pend(R, P), P > 0 ).

'sk-pending?'(H, N, B) :-
    (   pw_known(H, N, Id), pw_find(Id, R), pw_pending_rep(R) -> B = true ; B = false ).

% A node's pending children, each as (sk-node-at hash child).
'sk-pending-children'(H, N, Children) :-
    findall(['sk-node-at', CH, C],
            ( '&sk_child'(H, O, C, CH), attribute_free_variant(O, N),
              pw_known(CH, C, Id), pw_find(Id, R), pw_pending_rep(R) ),
            Children).

'sk-holds-work?'(H, B) :- ( holds_work(H) -> B = true ; B = false ).

holds_work(H) :- ( '&sk_parked'(H, _, _) ; '&sk_deferred_joins'(H, _, _) ; '&sk_deferred'(H, _, _) ), !.

% A node's work items change by Delta: one for being unexpanded (taken when it
% is expanded), one per parked delivery, deferred join and deferred row. A
% node without an id has none counted; work added gives it one.
'sk-work!'(H, N, Delta, []) :-
    (   Delta > 0 -> pw_node(H, N, Id), pw_add_work(Id, Delta)
    ;   pw_known(H, N, Id) -> pw_add_work(Id, Delta)
    ;   true
    ).

pw_add_work(Id, Delta) :-
    pw_find(Id, R),
    ( pw_pending_rep(R) -> Old = true ; Old = false ),
    retract(pw_work(R, W0)), W is W0 + Delta, assertz(pw_work(R, W)),
    pw_changed(R, Old).

% After a component's counts changed: when its state flipped, each parent's
% count of pending children moves with it.
pw_changed(R, Old) :-
    ( pw_pending_rep(R) -> New = true ; New = false ),
    (   Old == New -> true
    ;   ( New == true -> D = 1 ; D = -1 ),
        forall(pw_in(R, P, _), pw_add_pend(P, D))
    ).

pw_add_pend(P, D) :-
    ( pw_pending_rep(P) -> Old = true ; Old = false ),
    retract(pw_pend(P, P0)), P1 is P0 + D, assertz(pw_pend(P, P1)),
    pw_changed(P, Old).

% A new child link from owner to child.
'sk-link-pending!'(OH, Owner, CH, Child, []) :-
    pw_node(OH, Owner, U), pw_node(CH, Child, V),
    pw_find(U, RU), pw_find(V, RV),
    (   RU == RV -> true
    ;   retract(pw_out(RU, RV, M0))
    ->  M is M0 + 1, assertz(pw_out(RU, RV, M)),
        retract(pw_in(RV, RU, M0)), assertz(pw_in(RV, RU, M))
    ;   pw_out(RV, _, _), pw_in(RU, _, _), pw_reaching(RV, RU, Merge)
    ->  pw_merge(Merge)
    ;   assertz(pw_out(RU, RV, 1)), assertz(pw_in(RV, RU, 1)),
        pw_deg_add(RU, 1, 0), pw_deg_add(RV, 0, 1),
        ( pw_pending_rep(RV) -> pw_add_pend(RU, 1) ; true )
    ).

% A child with no children, or an owner with no parents, closes no cycle,
% which settles most links (a new node, a new root) without a search.
%
% The components on a path from From to To, when there is one: a search
% forward from From and one backward from To read one link each in turn
% until one is exhausted. Neither passes the other's start, since a path from
% From to To ends at To. The exhausted search found every component on such a
% path; those are the ones whose links within what it found lead back to the
% other start. So the cost is twice the smaller search's links: linking a new
% node under a large component never reads that component's links.
pw_reaching(From, To, Merge) :-
    empty_nb_set(F), add_nb_set(From, F), empty_nb_set(B), add_nb_set(To, B),
    pw_alternate([To], [From], 0, 0, From, To, F, B, Side),
    (   Side == forward
    ->  add_nb_set(To, F, false), pw_on_paths(F, pw_out, To, Merge)
    ;   add_nb_set(From, B, false), pw_on_paths(B, pw_in, From, Merge)
    ).

% pw_alternate(+BackwardStack, +ForwardStack, +BackwardLinks, +ForwardLinks,
% ..., -Exhausted): each turn the search that will have read fewer links
% after expanding its next component expands it.
pw_alternate([], _, _, _, _, _, _, _, backward) :- !.
pw_alternate(_, [], _, _, _, _, _, _, forward) :- !.
pw_alternate([Z|Bs], [X|Fs], CB, CF, From, To, F, B, Side) :-
    ( Z == From -> DB = 0 ; pw_deg(Z, _, DB) ),
    ( X == To -> DF = 0 ; pw_deg(X, DF, _) ),
    (   CB + DB =< CF + DF
    ->  ( Z == From -> Bs1 = Bs ; findall(P, pw_in(Z, P, _), Ps), pw_visit(Ps, B, Bs, Bs1) ),
        CB1 is CB + DB,
        pw_alternate(Bs1, [X|Fs], CB1, CF, From, To, F, B, Side)
    ;   ( X == To -> Fs1 = Fs ; findall(Y, pw_out(X, Y, _), Ys), pw_visit(Ys, F, Fs, Fs1) ),
        CF1 is CF + DF,
        pw_alternate([Z|Bs], Fs1, CB, CF1, From, To, F, B, Side)
    ).

pw_visit([], _, Stack, Stack).
pw_visit([Y|Ys], Set, Stack0, Stack) :-
    (   add_nb_set(Y, Set, true) -> pw_visit(Ys, Set, [Y|Stack0], Stack)
    ;   pw_visit(Ys, Set, Stack0, Stack)
    ).

% The components of a search's set from which its Edge links, staying in
% the set, lead to Start: Start's own links are not read.
pw_on_paths(Set, Edge, Start, Found) :-
    nb_set_to_list(Set, Members),
    findall(Y-Z, ( member(Z, Members), Z \== Start, call(Edge, Z, Y, _), add_nb_set(Y, Set, false) ), Back),
    keysort(Back, Sorted), group_pairs_by_key(Sorted, Grouped), list_to_assoc(Grouped, Into),
    empty_nb_set(Seen), add_nb_set(Start, Seen),
    pw_back([Start], Into, Seen),
    nb_set_to_list(Seen, Found).

pw_back([], _, _).
pw_back([Y|Ys], Into, Seen) :-
    (   get_assoc(Y, Into, Zs) -> findall(Z, ( member(Z, Zs), add_nb_set(Z, Seen, true) ), New) ; New = [] ),
    append(New, Ys, Next),
    pw_back(Next, Into, Seen).

% Merges components into the largest (the lowest id among equals): their
% links to one another vanish, their other links move to it, and each outside
% parent counts the merged component once, by its state after the merge.
% Each count changes in one step that passes a flipped state on, so every
% parent always counts its children's current states.
pw_merge(Members) :-
    findall(S-R, ( member(R, Members), pw_size(R, S0), S is -S0 ), Sized),
    keysort(Sized, [_-R0|_]),
    findall(R, ( member(R, Members), pw_pending_rep(R) ), Pending),
    findall(P, ( member(R, Members), pw_in(R, P, _), \+ memberchk(P, Members) ), Ps),
    sort(Ps, Parents),
    findall(P-K, ( member(P, Parents),
                   aggregate_all(count, ( member(R, Pending), pw_in(R, P, _) ), K) ),
            ParentCounts),
    forall(( member(Y, Members), Y \== R0, retract(pw_out(R0, Y, _)) ),
           ( retract(pw_in(Y, R0, _)), pw_deg_add(R0, -1, 0),
             ( memberchk(Y, Pending) -> pw_bump(pw_pend, R0, -1) ; true ) )),
    forall(( member(X, Members), X \== R0 ), pw_absorb(R0, X, Members)),
    ( pw_pending_rep(R0) -> Now = 1 ; Now = 0 ),
    forall(member(P-K, ParentCounts),
           ( D is Now - K, ( D =:= 0 -> true ; pw_add_pend(P, D) ) )).

pw_absorb(R0, X, Members) :-
    assertz(pw_up(X, R0)),
    retract(pw_size(X, SX)), pw_bump(pw_size, R0, SX),
    retract(pw_work(X, WX)), pw_bump(pw_work, R0, WX),
    retract(pw_pend(X, _)), retract(pw_deg(X, _, _)),
    forall(retract(pw_out(X, Y, M)),
           (   retract(pw_in(Y, X, M)),
               (   memberchk(Y, Members) -> ( Y == R0 -> pw_deg_add(R0, 0, -1) ; true )
               ;   retract(pw_out(R0, Y, M0))
               ->  M1 is M0 + M, assertz(pw_out(R0, Y, M1)), retract(pw_in(Y, R0, M0)), assertz(pw_in(Y, R0, M1)),
                   pw_deg_add(Y, 0, -1)
               ;   assertz(pw_out(R0, Y, M)), assertz(pw_in(Y, R0, M)), pw_deg_add(R0, 1, 0),
                   ( pw_pending_rep(Y) -> pw_bump(pw_pend, R0, 1) ; true )
               ) )),
    forall(retract(pw_in(X, P, M)),
           (   retract(pw_out(P, X, M)),
               (   memberchk(P, Members) -> true
               ;   retract(pw_out(P, R0, M0))
               ->  M1 is M0 + M, assertz(pw_out(P, R0, M1)), retract(pw_in(R0, P, M0)), assertz(pw_in(R0, P, M1)),
                   pw_deg_add(P, -1, 0)
               ;   assertz(pw_out(P, R0, M)), assertz(pw_in(R0, P, M)), pw_deg_add(R0, 0, 1)
               ) )).

pw_deg_add(R, DO, DI) :-
    retract(pw_deg(R, O0, I0)), O is O0 + DO, I is I0 + DI, assertz(pw_deg(R, O, I)).

pw_bump(Count, R, D) :-
    Old =.. [Count, R, V0], retract(Old), V is V0 + D, New =.. [Count, R, V], assertz(New).

% A node of a query's hypothetical context leaves with it. Its component goes
% once all its nodes went, with its links; before, its counts stay as they
% are, which can only keep a node pending longer.
'sk-drop-pending!'(H, N, []) :-
    (   pw_known(H, N, Id)
    ->  pw_find(Id, R),
        forall(clause(pw_id(H, S, Id), true, Ref), ( attribute_free_variant(S, N) -> erase(Ref) ; true )),
        retractall(pw_up(Id, _)),
        pw_bump(pw_size, R, -1),
        ( pw_size(R, 0) -> pw_drop_rep(R) ; true )
    ;   true
    ).

pw_drop_rep(R) :-
    ( pw_pending_rep(R) -> D = -1 ; D = 0 ),
    forall(retract(pw_out(R, Y, _)), ( retract(pw_in(Y, R, _)), pw_deg_add(Y, 0, -1) )),
    findall(P, retract(pw_in(R, P, _)), Ps),
    forall(member(P, Ps), ( retract(pw_out(P, R, _)), pw_deg_add(P, -1, 0) )),
    retractall(pw_size(R, _)), retractall(pw_work(R, _)), retractall(pw_pend(R, _)), retractall(pw_deg(R, _, _)),
    forall(member(P, Ps), ( D =:= 0 -> true ; pw_add_pend(P, D) )).
