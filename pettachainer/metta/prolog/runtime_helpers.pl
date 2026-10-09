:- use_module(library(heaps)).
:- use_module(library(assoc)).
:- use_module(library(nb_set)).
:- use_module(library(yall)).

% Data-only spaces have no function definitions or compiler metadata. In
% particular, an open first column must not enter remove-atom's function case.
'remove-data-rows!'(Space, Pattern, true) :-
    Row =.. [Space|Pattern],
    retractall(Row).

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
    (   Row = [First|_], ground(First) -> arg(1, Stored, First) ; true ),
    (   clause(Stored, true, Ref), Stored =@= Head -> erase(Ref) ; true ).

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
    term_variables(Term, Variables),
    (   Variables == []
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
:- dynamic deps_leaf/2, deps_leaf_hash/2, deps_node/3, deps_interned/3, deps_size_memo/2, deps_cut/2.

% A frozen key's views stand for its summary (forgetting.metta): a node cut
% to another is walked as that one, so what a value read before the key was
% frozen depends on the key's window, not its whole past.
'deps-cut!'(Ids, Replacement, true) :-
    forall(( member(Id, Ids), deps_node(Id, _, _), \+ deps_cut(Id, _), Id \== Replacement ),
           assertz(deps_cut(Id, Replacement))).
% Drops every dependency node no live value reaches. Roots are the sets the
% stores hold; marking follows cuts; a dropped key leaf is interned anew when
% a key is read again.
'deps-gc!'(Roots, true) :-
    empty_nb_set(Live),
    forall(member(Root, Roots), deps_mark(Root, Live)),
    size_nb_set(Live, Kept), flag(deps_gc_kept, _, Kept),
    flag(deps_next_id, Next, Next), flag(deps_gc_next, _, Next),
    forall(( clause(deps_node(Id, _, _), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)),
    forall(( clause(deps_interned(_, _, Id), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)),
    forall(( clause(deps_cut(Id, _), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)),
    forall(( clause(deps_size_memo(Id, _), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)),
    forall(( clause(deps_leaf_hash(Id, _), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)),
    forall(( clause(deps_leaf(_, Id), true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)).
% A collection is due once more ids were interned since the last one than it
% kept (at least 4096), so its cost, a walk of the stores, stays proportional
% to what was interned.
'deps-gc-due?'(Result) :-
    flag(deps_next_id, Next, Next), flag(deps_gc_next, Last, Last), flag(deps_gc_kept, Kept, Kept),
    (   Next - Last > max(Kept, 4096) -> Result = true ; Result = false ).

% Drops every stored proof and evidence set no store reaches: roots are the
% proof references and evidence sets in any space but the proof store itself,
% and a stored proof keeps the proofs it refers to and its evidence. A replaced
% view's proof stays while an older view or a consumer's proof still refers to
% it.
'stored-refs-gc!'(true) :-
    empty_nb_set(Proofs), empty_nb_set(Sets),
    forall(( current_predicate(user:F/A), sub_atom(F, 0, 1, _, '&'),
             F \== '&proof', F \== '&proof_fact',
             functor(H, F, A), predicate_property(user:H, dynamic),
             user:H, sub_term(S, H), nonvar(S), S = [Tag, Id], integer(Id) ),
           (   Tag == 'proof-ref' -> proof_mark(Id, Proofs, Sets)
           ;   Tag == 'ev-set' -> add_nb_set(Id, Sets, _)
           ;   true )),
    forall(( clause(user:'&proof'(Pid, _, _, _), true, Ref), \+ add_nb_set(Pid, Proofs, false) ), erase(Ref)),
    forall(( clause(user:'&proof_fact'(Pid, _, _), true, Ref), \+ add_nb_set(Pid, Proofs, false) ), erase(Ref)),
    forall(( clause(ev_set(Set, _, _, _), true, Ref), \+ add_nb_set(Set, Sets, false) ), erase(Ref)),
    forall(( clause(ev_set_key(_, Set), true, Ref), \+ add_nb_set(Set, Sets, false) ), erase(Ref)),
    forall(( clause(ev_union_memo(Key, C), true, Ref),
             \+ ( Left is Key >> 32, Right is Key /\ 0xffffffff,
                  add_nb_set(Left, Sets, false), add_nb_set(Right, Sets, false), add_nb_set(C, Sets, false) ) ),
           erase(Ref)).

proof_mark(Pid, Proofs, Sets) :-
    (   add_nb_set(Pid, Proofs, true)
    ->  forall(user:'&proof'(Pid, _, ['ev-set', Set], _), add_nb_set(Set, Sets, _)),
        forall(( user:'&proof'(Pid, Stored, _, _), sub_term(S, Stored), nonvar(S),
                 S = ['proof-ref', Inner], integer(Inner) ),
               proof_mark(Inner, Proofs, Sets))
    ;   true ).

deps_mark(0, _) :- !.
deps_mark(Id, Live) :-
    (   add_nb_set(Id, Live, true)
    ->  (   deps_cut(Id, Replacement) -> deps_mark(Replacement, Live)
        ;   deps_node(Id, Children, _) -> forall(member(Child, Children), deps_mark(Child, Live))
        ;   true )
    ;   true ).

deps_children(Id, Children) :-
    (   deps_cut(Id, Replacement) -> Children = [Replacement] ; deps_node(Id, Children, _) ).
% The mask width trades stored bytes per node against collisions in dominance
% (docs/metta/dependency_tracking_design.md, "Mask width").
deps_mask_bits(4096).

deps_bit(Hash, Bit) :- deps_mask_bits(W), Bit is 1 << (Hash mod W).

deps_mask(0, 0) :- !.
deps_mask(Id, Mask) :- deps_leaf_hash(Id, Hash), !, deps_bit(Hash, Mask).
deps_mask(Id, Mask) :- deps_node(Id, _, Mask).

'deps-key'(Hash, Id) :-
    (   deps_leaf(Hash, Id) -> true
    ;   flag(deps_next_id, Last, Last + 1), Id is Last + 1,
        assertz(deps_leaf(Hash, Id)), assertz(deps_leaf_hash(Id, Hash)) ).

'deps-union'(Left, Right, Id) :- 'deps-join'([Left, Right], Id).

'deps-join'(Ids, Id) :-
    sort(Ids, Sorted), exclude(==(0), Sorted, Children),
    (   Children == [] -> Id = 0
    ;   Children = [Only] -> Id = Only
    ;   term_hash(Children, Key),
        (   deps_interned(Key, Children, Id) -> true
        ;   flag(deps_next_id, Last, Last + 1), Id is Last + 1,
            foldl([Child, Acc0, Acc]>>(deps_mask(Child, M), Acc is Acc0 \/ M), Children, 0, Mask),
            assertz(deps_node(Id, Children, Mask)), assertz(deps_interned(Key, Children, Id)) ) ).

% Whether a set holds a key: the walk enters only children whose mask has the
% key's bit and visits each node once.
deps_has(Id, Hash) :- deps_bit(Hash, Bit), empty_nb_set(Seen), deps_has(Id, Hash, Bit, Seen).
deps_has(Id, Hash, Bit, Seen) :-
    deps_mask(Id, Mask), Mask /\ Bit =\= 0,
    (   deps_leaf_hash(Id, Leaf) -> Leaf =:= Hash
    ;   add_nb_set(Id, Seen, true),
        deps_children(Id, Children),
        member(Child, Children), deps_has(Child, Hash, Bit, Seen), ! ).

'deps-has?'(Id, Hash, Result) :- ( deps_has(Id, Hash) -> Result = true ; Result = false ).

'deps-meet?'(Hashes, Id, Result) :-
    (   member(Hash, Hashes), deps_has(Id, Hash) -> Result = true ; Result = false ).

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
    ->  (   deps_leaf_hash(Id, Hash) -> add_nb_set(Hash, Keys, _)
        ;   deps_children(Id, Children), forall(member(Child, Children), deps_collect(Child, Nodes, Keys)) )
    ;   true ).
deps_covered(Id, Nodes, Keys, Seen) :-
    (   add_nb_set(Id, Nodes, false) -> true
    ;   add_nb_set(Id, Seen, false) -> true
    ;   add_nb_set(Id, Seen, true),
        (   deps_leaf_hash(Id, Hash) -> add_nb_set(Hash, Keys, false)
        ;   deps_children(Id, Children), forall(member(Child, Children), deps_covered(Child, Nodes, Keys, Seen)) ) ).

% The number of keys in a set; a node's count never changes once computed.
'deps-size'(0, 0) :- !.
'deps-size'(Id, Size) :-
    (   deps_cut(Id, Replacement) -> 'deps-size'(Replacement, Size)
    ;   deps_leaf_hash(Id, _) -> Size = 1
    ;   deps_size_memo(Id, Size) -> true
    ;   empty_nb_set(Nodes), empty_nb_set(Keys), deps_collect(Id, Nodes, Keys),
        size_nb_set(Keys, Size), assertz(deps_size_memo(Id, Size)) ).

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
:- dynamic ev_entry/2, ev_entry_key/2, ev_set/4, ev_set_key/2, ev_union_memo/2.

ev_entry_id(Entry, Id) :-
    'index-hash'(Entry, Hash),
    (   ev_entry_key(Hash, Id), ev_entry(Id, Stored), Stored =@= Entry -> true
    ;   flag(ev_next_entry, Last, Last + 1), Id is Last + 1,
        assertz(ev_entry_key(Hash, Id)), assertz(ev_entry(Id, Entry)) ).

ev_order(0, []) :- !.
ev_order(Set, Ids) :- ev_set(Set, Order, _, _), string_codes(Order, Ids).
ev_sorted(0, []) :- !.
ev_sorted(Set, Ids) :- ev_set(Set, _, Sorted, _), string_codes(Sorted, Ids).
ev_excluded(0, []) :- !.
ev_excluded(Set, Excluded) :- ev_set(Set, _, _, Excluded).

ev_intern([], _, _, 0) :- !.
ev_intern(Ids, Sorted, Excluded, Set) :-
    string_codes(Order, Ids), term_hash(Order, Hash),
    (   ev_set_key(Hash, Set), ev_set(Set, Order, _, _) -> true
    ;   flag(ev_next_set, Last, Last + 1), Set is Last + 1, string_codes(SortedString, Sorted),
        assertz(ev_set(Set, Order, SortedString, Excluded)), assertz(ev_set_key(Hash, Set)) ).

% The set of a list of ids without repeats, in its order.
ev_of_ids(Ids, Set) :-
    findall(Rule, ( member(Id, Ids), ev_entry(Id, ['rule-excluded', Kb, Name]), ev_entry_id(['rule-ev', Kb, Name], Rule) ), Rules),
    sort(Ids, Sorted), sort(Rules, Excluded), ev_intern(Ids, Sorted, Excluded, Set).

ev_in_assoc(Assoc, Id) :- get_assoc(Id, Assoc, _).

% The ids of a list that are in a sorted list, in the list's order.
ev_keep(Ids, Sorted, Kept) :-
    pairs_keys_values(Pairs, Sorted, Sorted), ord_list_to_assoc(Pairs, Assoc), include(ev_in_assoc(Assoc), Ids, Kept).

ev_fact_entry(Id, Entry) :-
    ev_entry(Id, Entry), \+ Entry = ['rule-ev', _, _], \+ Entry = ['rule-excluded', _, _].

'evidence-set'(Entries, ['ev-set', Set]) :-
    maplist(ev_entry_id, Entries, Repeated), list_to_set(Repeated, Ids), ev_of_ids(Ids, Set).

'evidence-entries'(['ev-set', Set], Entries) :- ev_order(Set, Ids), maplist(ev_entry, Ids, Entries).

% A's entries followed by the entries of B that A lacks.
'evidence-union'(['ev-set', A], ['ev-set', B], ['ev-set', C]) :- ev_union(A, B, C).
ev_union(A, B, C) :-
    (   B == 0 -> C = A
    ;   A == 0 -> C = B
    ;   A == B -> C = A
    ;   Key is A << 32 \/ B, ev_union_memo(Key, Memo) -> C = Memo
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
    ev_entry(Id, Entry),
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
% that a derivation exists (docs/metta/complete_predicates.md).
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
        \+ dormancy_supported(PType, PCtx, Type-Ctx, [], 8)
    ->  Dormant = true
    ;   Dormant = false ),
    nb_getval(dormancy_heads, Heads0), sort(Heads0, Heads).

dormancy_supported(Type, Ctx, Forbidden, Path, Depth) :-
    nb_getval(dormancy_budget, Budget),
    (   Budget =< 0 -> true
    ;   Budget1 is Budget - 1, nb_setval(dormancy_budget, Budget1),
        (   Type-Ctx == Forbidden -> fail
        ;   member(Seen, Path), Seen =@= Type-Ctx -> fail
        ;   Depth =< 0 -> true
        ;   \+ dormancy_judged(Type, Ctx) -> true
        ;   dormancy_fact(Type, Ctx) -> true
        ;   \+ dormancy_row(rules('runtime-rule-row', _, [Type, Ctx|_], _)) -> true
        ;   dormancy_note_head(Type),
            Depth1 is Depth - 1,
            dormancy_row(rules('runtime-rule-row', _, [Type, Ctx|_], Premises)),
            (   memberchk(['CPU', 'SettlesFormula'|_], Premises) -> \+ \+ dormancy_settles(Premises)
            ;   forall(( member([PType, PCtx, _, _], Premises), PType \== 'CPU' ),
                       dormancy_supported(PType, PCtx, Forbidden, [Type-Ctx|Path], Depth1)) ) ) ).

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
