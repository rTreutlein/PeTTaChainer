% Raw pending-component graph, ownership tables and work counters.
% Retirement decisions and listeners belong to application_support/search_state.
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
:- dynamic '&sk_expanded'/2, '&sk_link'/1, '&sk_join_link'/2, '&sk_child'/4,
           '&sk_parked'/3, '&sk_deferred_joins'/3, '&sk_deferred'/3, '&sk_fact_watch'/3.

% Search work is indexed by the ground statement/context it concludes, apart
% from its awaited premise index. Clause references erase exactly that work;
% retract listeners keep the index correct for ordinary context cleanup too.
% None of the values, facts, rows or sample/tally stores belong to this index.
:- dynamic sk_search_clause/3, sk_search_node/4, sk_retire_queue/2,
           sk_child_edge/2, sk_child_users/2, sk_child_claim/3,
           sk_child_debt/2, sk_retire_component/1, sk_join_wait/2, sk_retire_wait/1.
% Removing one actual child link removes just its share of a condensed edge.
% A merged component need not be split: its remaining nodes and work still
% share the conservative component, as on context retirement; obsolete
% outgoing links no longer keep any parent pending.
pw_unlink(OH, O, NH, N) :-
    (   pw_known(OH, O, U), pw_known(NH, N, V), pw_find(U, RU), pw_find(V, RV), RU \== RV,
        retract(pw_out(RU, RV, M0))
    ->  retract(pw_in(RV, RU, M0)),
        (   M0 > 1 -> M is M0 - 1, assertz(pw_out(RU, RV, M)), assertz(pw_in(RV, RU, M))
        ;   pw_deg_add(RU, -1, 0), pw_deg_add(RV, 0, -1),
            ( pw_pending_rep(RV) -> pw_add_pend(RU, -1) ; true ) )
    ;   true ).

% A node's id, created with one work item when the node is unexpanded.
pw_node(H, N, Id) :-
    (   pw_known(H, N, Id) -> true
    ;   flag(pw_next_id, Id, Id + 1),
        assertz(pw_id(H, N, Id)),
        ( '&sk_expanded'(H, S), attribute_free_variant(S, N) -> W = 0 ; W = 1 ),
        ( sk_search_key(N, KH, Key) -> assertz(sk_search_node(KH, Key, H, N)) ; true ),
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
        forall(pw_in(R, P, _), pw_add_pend(P, D)),
        ( New == false, sk_child_debt(R, _), \+ sk_retire_component(R)
        -> assertz(sk_retire_component(R)) ; true )
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
    ;   pw_deg(RV, Children, _), Children > 0, pw_deg(RU, _, Parents), Parents > 0,
        pw_reaching(RV, RU, Merge)
    ->  pw_merge(Merge)
    ;   assertz(pw_out(RU, RV, 1)), assertz(pw_in(RV, RU, 1)),
        pw_deg_add(RU, 1, 0), pw_deg_add(RV, 0, 1),
        ( pw_pending_rep(RV) -> pw_add_pend(RU, 1) ; true )
    ).

% A child with no children, or an owner with no parents, closes no cycle,
% which settles most links (a new node, a new root) without a search. The
% degrees say so: pw_out and pw_in share their first argument with every link
% of a component with many children, such as a fold over one member per
% decision, so a lookup by it would read all of them.
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
           ( D is Now - K, ( D =:= 0 -> true ; pw_add_pend(P, D) ) )),
    ( Now =:= 0, sk_child_debt(R0, _), \+ sk_retire_component(R0)
    -> assertz(sk_retire_component(R0)) ; true ).

pw_absorb(R0, X, Members) :-
    assertz(pw_up(X, R0)),
    forall(retract(sk_child_debt(X, D)), assertz(sk_child_debt(R0, D))),
    retractall(sk_retire_component(X)),
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
    ( nb_current(sk_retiring, true) -> true ; sk_unwatch_fact(H, N) ),
    (   pw_known(H, N, Id)
    ->  pw_find(Id, R),
        forall(clause(pw_id(H, S, Id), true, Ref), ( attribute_free_variant(S, N) -> erase(Ref) ; true )),
        (   sk_search_key(N, KH, _)
        ->  forall(clause(sk_search_node(KH, _, H, SNode), true, NRef),
                   ( attribute_free_variant(SNode, N) -> erase(NRef) ; true ))
        ;   true ),
        retractall(pw_up(Id, _)),
        pw_bump(pw_size, R, -1),
        ( pw_size(R, 0) -> pw_drop_rep(R) ; true )
    ;   true
    ).

pw_drop_rep(R) :-
    retractall(sk_child_debt(R, _)), retractall(sk_retire_component(R)),
    ( pw_pending_rep(R) -> D = -1 ; D = 0 ),
    forall(retract(pw_out(R, Y, _)), ( retract(pw_in(Y, R, _)), pw_deg_add(Y, 0, -1) )),
    findall(P, retract(pw_in(R, P, _)), Ps),
    forall(member(P, Ps), ( retract(pw_out(P, R, _)), pw_deg_add(P, -1, 0) )),
    retractall(pw_size(R, _)), retractall(pw_work(R, _)), retractall(pw_pend(R, _)), retractall(pw_deg(R, _, _)),
    forall(member(P, Ps), ( D =:= 0 -> true ; pw_add_pend(P, D) )).

