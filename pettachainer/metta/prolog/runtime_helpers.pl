:- use_module(library(heaps)).
:- use_module(library(assoc)).

% Data-only spaces have no function definitions or compiler metadata. In
% particular, an open first column must not enter remove-atom's function case.
'remove-data-rows!'(Space, Pattern, true) :-
    Row =.. [Space|Pattern],
    retractall(Row).

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

% Dependency sets are SWI ordered sets of key hashes, so union, containment
% and intersection are linear merges.
'deps-set'(Hashes, Set) :- sort(Hashes, Set).
'deps-union'(Left, Right, Set) :- ord_union(Left, Right, Set).
'deps-join'(Sets, Set) :- ord_union(Sets, Set).
'deps-within?'(Set, Within, Result) :-
    (   ord_subset(Set, Within) -> Result = true ; Result = false ).
'deps-meet?'(Left, Right, Result) :-
    (   ord_disjoint(Left, Right) -> Result = false ; Result = true ).

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
