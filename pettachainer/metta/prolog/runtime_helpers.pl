:- use_module(library(heaps)).

% PeTTa arrows have one result position. Package SWI's three relational
% get_from_heap/4 outputs into one positional product.
heap_pop(Heap, [Priority, Value, Rest]) :-
    get_from_heap(Heap, Priority, Value, Rest).

% Hash a lookup column with every variable replaced by one marker, so a row
% keeps an integer SWI can JIT-index; =alpha on the stored key still decides.
'index-hash'(Term, Hash) :-
    term_variables(Term, Variables),
    (   Variables == []
    ->  term_hash(Term, Hash)
    ;   copy_term(Term, Copy),
        term_variables(Copy, CopyVariables),
        maplist(=('goal-key-hash-variable'), CopyVariables),
        term_hash(Copy, Hash)
    ).

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

% One native call records the complete outcome of a proof liveness lookup.
% Retired proofs are checks, but are neither cache hits nor cache misses.
query_metric_liveness_event(Outcome, Outcome) :-
    query_metrics_enabled(Enabled),
    (   Enabled == true
    ->  query_metric_increment_enabled('proof-liveness-checks', _),
        query_metric_liveness_outcome(Outcome)
    ;   true
    ).

query_metric_liveness_outcome(hit) :-
    query_metric_increment_enabled('proof-liveness-cache-hits', _).
query_metric_liveness_outcome(miss) :-
    query_metric_increment_enabled('proof-liveness-cache-misses', _).
query_metric_liveness_outcome(retired).
