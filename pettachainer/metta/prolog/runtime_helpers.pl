:- use_module(library(heaps)).

% PeTTa arrows have one result position. Package SWI's three relational
% get_from_heap/4 outputs into one positional product.
heap_pop(Heap, [Priority, Value, Rest]) :-
    get_from_heap(Heap, Priority, Value, Rest).

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
