% Admitted conditional graphs: docs/metta/event_node_contract.md.
:- use_module(library(ugraphs)).
:- dynamic event_graph_plan/5, '&prem_prefix'/4.
% A lone authored hard endpoint fixes the queried event in every surviving
% world. Read it directly, including while population folds read old labels.
'event-network-read'(Key, Filter, Exclude, Ev, _Value, Out) :-
    Key = ['sk-key', Goal, Scope], ground(Key), Scope = [_, 'MAIN', _], \+ context_active(_),
    findall([Goal, Scope, P, TV], '&kb'(Goal, Scope, P, TV), [Fact]),
    Fact = [_, _, _, ['STV', S, C]], C >= 1, ( S =:= 0 ; S =:= 1 ),
    'index-hash'(Key, H), \+ '&sk_forward_stored'(H, _, Fact, _, _),
    'sk-summary-fact?'(Fact, false),
    \+ '&materialized_facts'('materialized-row', _, _, _, Fact, _),
    'sk-leaf-view'(H, Fact, Leaf),
    Leaf = ['sk-val', _, Evidence, _], 'premise-evidence-overlap?'(Ev, Evidence, false),
    'sk-admits?'(Filter, Exclude, Leaf, true), !, Out = Leaf.
% With no likelihoods, a stored root remains a source count. It must not
% cross the propagated-moment boundary before another rule consumes it.
'event-network-read'(Key, Filter, Exclude, Ev, _Value, Out) :-
    graph_plan(Key, graph(Models, [])), Key = ['sk-key', Goal, _],
    memberchk(model(Goal, root, [Fact]), Models),
    'index-hash'(Key, H), 'sk-leaf-view'(H, Fact, Leaf),
    Leaf = ['sk-val', _, Evidence, _], 'premise-evidence-overlap?'(Ev, Evidence, false),
    'sk-admits?'(Filter, Exclude, Leaf, true), !, Out = Leaf.
'event-network-read'(Key, Filter, Exclude, Ev, Value, Out) :-
    (   graph_plan(Key, graph(Models, Factors)), Factors \== [],
        Key = ['sk-key', Goal, Scope],
        forall(( member(model(Type, _, _), Models) ; member([Type|_], Factors) ),
               ( Type == Goal -> true ; 'index-hash'(['sk-key', Type, Scope], H), \+ memberchk(H, Exclude) )),
        graph_proof(Models, Factors, Scope, [node, [conjunction|Proofs]], Evidence, D0),
        'premise-evidence-overlap?'(Ev, Evidence, false),
        'evidence-union'(Ev, Evidence, Cavity),
        maplist(graph_parameter(Scope, Cavity, Exclude), Models, Groups, Priors),
        append(Groups, Vars), length(Vars, NV), NV =< 12,
        findall(P-D, member(['sk-val', [_, _, P, _], _, D], Priors), PDs),
        pairs_keys_values(PDs, Ps, Ds), append(Proofs, Ps, All),
        'deps-join'([D0|Ds], Deps),
        graph_answer(Models, Factors, Goal, Vars, TV),
        Fact = [Goal, Scope, [node, [conjunction|All]], TV],
        'sk-admits?'(Filter, Exclude, ['sk-val', Fact, Evidence, Deps], true)
    ->  forall(( member(model(Type, _, _), Models) ; member([Type|_], Factors) ),
               ( Type == Goal -> true ; 'sk-add-use!'(['sk-key', Type, Scope], Key, _) )),
        Out = ['sk-val', Fact, Evidence, Deps]
    ;   Out = Value ).

graph_plan(Key, Plan) :-
    Key = ['sk-key', _, Scope], ground(Key), Scope = [_, _, _],
    ( context_active(Frame) -> true ; Frame = main ),
    'sk-input-epoch'(Key, Epoch),
    Generation = Epoch,
    term_hash(Key, Hash),
    ( event_graph_plan(Hash, Frame, Generation, Key, Cached) -> true
    ; ( graph_model(Key, Model) -> Cached = Model ; Cached = none ),
      assertz(event_graph_plan(Hash, Frame, Generation, Key, Cached)) ),
    Plan = Cached.

graph_model(['sk-key', Goal, Scope], graph(Models, Factors)) :-
        graph_observations([Goal], Scope, Goal, [], [], Observed),
        include([T]>>(T = [H|_], connective_head(H)), Observed, Compounds),
        node_formula(['And', Goal|Observed], _, [], Seeds),
        graph_atoms(Seeds, Scope, [], Models0), sort(Models0, Models),
        findall(T-P, member(model(T, conditional(P, _, _, _), _), Models), Edges),
        vertices_edges_to_ugraph([], Edges, Graph), top_sort(Graph, _),
        ( Compounds \== []
        ; member(model(_, conditional(_, _, _, _), _), Models)
        ; member(T, Observed),
          Scope = [KB|_], 'statement-prefix-keys'(KB, T, Hashes),
          member(H, Hashes), '&prem_prefix'(H, [T, Scope, _, _], Id, Index),
          rules('runtime-rule-row', Id, [Child, Scope, [by, _, _], _], Ps),
          nth0(Index, Ps, [T, Scope, _, _]), ground(Child),
          graph_template(Child, Scope, conditional(_, _, _, _)) ),
        node_formula(Goal, _, [], GoalAtoms),
        forall(member(T, GoalAtoms), memberchk(model(T, _, _), Models)),
        findall(Fact, ( member(Type, Compounds), graph_sources(Type, Scope, Fs), member(Fact, Fs) ), CompoundFacts),
        findall(Fact, ( member(model(_, conditional(_, _, _, _), Fs), Models), member(Fact, Fs) ), Reports),
        append(CompoundFacts, Reports, Factors0), sort(Factors0, Factors),
        ( Factors \== [] ; memberchk(model(Goal, root, [_]), Models) ).

graph_observations([], _, _, _, Ks, Compounds) :- sort(Ks, Compounds).
graph_observations([T|Ts], Scope, Goal, Seen, Ks, Compounds) :-
    ( memberchk(T, Seen) -> graph_observations(Ts, Scope, Goal, Seen, Ks, Compounds)
    ; T \== Goal, T = [Head|_], connective_head(Head),
      graph_sources(T, Scope, []), graph_template(T, Scope, root)
    -> graph_observations(Ts, Scope, Goal, [T|Seen], Ks, Compounds)
    ; length(Seen, N), N < 24,
      graph_template(T, Scope, _), graph_sources(T, Scope, Sources),
      ( Sources = [_|_] -> NewKs = [T|Ks] ; NewKs = Ks ),
      findall(P, ( ccls_index([T, Scope, _, _], Id, Ps),
                   'rule-live?'(Id, true), 'context-rule-visible?'(Id, true),
                   member([P, Scope, _, _], Ps), ground(P) ), Inputs),
      Scope = [KB|_], 'statement-prefix-keys'(KB, T, Hashes),
      findall(Child,
              ( member(H, Hashes), '&prem_prefix'(H, [T, Scope, _, _], Id, Index),
                'rule-live?'(Id, true), 'context-rule-visible?'(Id, true),
                rules('runtime-rule-row', Id, [Child, Scope, [by, _, _], _], Ps),
                nth0(Index, Ps, [T, Scope, _, _]), ground(Child) ), Outputs),
      append(Inputs, Outputs, Neighbours),
      ( T = [Head|Children], connective_head(Head) -> append(Children, Neighbours, Next) ; Next = Neighbours ),
      append(Ts, Next, Todo), graph_observations(Todo, Scope, Goal, [T|Seen], NewKs, Compounds) ).

graph_atoms([], _, Models, Models).
graph_atoms([Type|Rest], Scope, M0, Models) :-
    (   memberchk(model(Type, _, _), M0)
    ->  graph_atoms(Rest, Scope, M0, Models)
    ;   length(M0, N), N < 12,
        ( Type = [Head|_] -> 'reserved-head?'(Head, false) ; true ),
        graph_template(Type, Scope, Model),
        graph_sources(Type, Scope, Facts),
        ( Model = conditional(Parent, _, _, _) -> Next = [Parent|Rest] ; Next = Rest ),
        graph_atoms(Next, Scope, [model(Type, Model, Facts)|M0], Models) ).

% All forward producers in a discovered component must have one explicit
% CTV template. Inverse and compound-reader rows are views of these sources.
graph_template(Type, Scope, Model) :-
    findall(producer(Id, Name, Ps),
            ( ccls_index([Type, Scope, [by, Name, _], _], Id, Ps),
              'rule-live?'(Id, true), 'context-rule-visible?'(Id, true) ), Producers),
    ( Producers == [] -> Model = root
    ; Producers = [producer(Id, Name, Ps)], Name \= [no_inverse|_],
      exclude([P]>>(P = ['CPU', 'ContextRule'|_]), Ps,
              [[Parent, Scope, _, PTV], ['CPU', 'CTVModusPonensFormula', [PTV, ['CTV', Pos, Neg]], _]]),
      ground([Parent, Pos, Neg]),
      \+ ( ccls_index([Parent, Scope, [[inverted, Name, with, PriorToken, _], _], _], _, _),
           PriorToken \== cpu ),
      Model = conditional(Parent, Id-Name, Pos, Neg) ).

% Authored leaves only; derived copies are not observations.
graph_sources(Type, Scope, Facts) :-
    Key = ['sk-key', Type, Scope], 'index-hash'(Key, H),
    'sk-key-leaves'(Key, 'sk-any-filter', Leaves),
    \+ ( member(Summary, Leaves), 'sk-summary-fact?'(Summary, true) ),
    findall(Fact, ( member(Fact, Leaves), Fact = [_, _, _, ['STV', _, C]], C > 0,
                    \+ '&sk_forward_stored'(H, _, Fact, _, _),
                    'sk-summary-fact?'(Fact, false),
                    \+ '&materialized_facts'('materialized-row', _, _, _, Fact, _) ), Facts).

graph_parameter(Scope, Ev, Exclude, model(Type, root, Facts), [Type-Dist], Prior) :-
    ( Facts == [] -> 'sk-part-prior'(['sk-key', Type, Scope], Ev, Exclude, Prior) ; Prior = 'sk-none' ),
    ( Prior = ['sk-val', [_, _, _, TV], _, _] -> TV = ['STV', S, C]
    ; foldl([[_T, _C, _P, T], T0, T1]>>'revision-merge-tv'(T0, T, T1), Facts,
            ['STV', 0.5, 0.0], ['STV', S, C]) ),
    'evidence-confidence-k'(K), event_node_dist(stored, S, C, K, Dist).
graph_parameter(_, _, _, model(Type, conditional(_, _, ['STV', S1, C1], ['STV', S0, C0]), _),
                [branch(Type, 1)-D1, branch(Type, 0)-D0], 'sk-none') :-
    'evidence-confidence-k'(K),
    event_node_dist(stored, S1, C1, K, D1), event_node_dist(stored, S0, C0, K, D0).


:- dynamic event_graph_memo/3.
graph_answer(Models, Factors, Goal, Vars, TV) :-
    Input = Models-Factors-Goal-Vars, term_hash(Input, Hash),
    ( event_graph_memo(Hash, Input, TV) -> true
    ; graph_moments(Models, Factors, Goal, Vars, TV), assertz(event_graph_memo(Hash, Input, TV)) ).

graph_moments(Models, Factors, Goal, Vars, TV) :-
    ( graph_tree_terms(Models, Factors, Goal, Terms) -> true
    ; graph_terms(Models, Factors, Goal, Vars, Terms) ),
    event_node_moments(Vars, Terms, [1], [a(S, V0, Kind)]),
    ( Kind == bound -> V = bound ; V = V0 ),
    'evidence-confidence-k'(K), node_stv(K, S, V, TV).

% Atomic evidence on a single-parent tree with fixed rule branches reduces
% to four monomials of its root parameter. Each child sends its likelihood
% and joint-goal mass for both parent states; common scales cancel.
graph_tree_terms(Models, Factors, Goal, Terms) :-
    findall(T, member(model(T, root, _), Models), [Root]),
    memberchk(model(Goal, _, _), Models),
    forall(member([T|_], Factors), memberchk(model(T, _, _), Models)),
    forall(member(model(_, conditional(P, _, ['STV', _, C1], ['STV', _, C0]), _), Models),
           ( C1 >= 1, C0 >= 1, memberchk(model(P, _, _), Models) )),
    graph_tree(Root, Models, Factors, Goal, z(Z0, N0, Z1, N1)),
    E0 is max(0.0, Z0 - N0), E1 is max(0.0, Z1 - N1),
    Terms = [t(N0, [Root-0], [1]), t(E0, [Root-0], []),
             t(N1, [Root-1], [1]), t(E1, [Root-1], [])].

graph_tree(Type, Models, Factors, Goal, z(Z0, N0, Z1, N1)) :-
    ( Type == Goal -> Hit = 1.0 ; Hit = 0.0 ),
    findall(child(T, P1, P0),
            member(model(T, conditional(Type, _, ['STV', P1, _], ['STV', P0, _]), _), Models), Children),
    foldl(graph_tree_child(Models, Factors, Goal), Children, z(1.0, 0.0, 1.0, Hit), z(A0, B0, A1, B1)),
    foldl(graph_tree_factor(Type), Factors, 0.0-0.0, L0-L1),
    log_sum(L0, L1, L), L \== ninf,
    exp_diff(L0, L, F0), exp_diff(L1, L, F1),
    Scale is max(A0 * F0, A1 * F1), Scale > 0,
    Z0 is A0 * F0 / Scale, N0 is B0 * F0 / Scale,
    Z1 is A1 * F1 / Scale, N1 is B1 * F1 / Scale.

graph_tree_child(Models, Factors, Goal, child(Type, P1, P0), z(A0, B0, A1, B1), z(Z0, N0, Z1, N1)) :-
    graph_tree(Type, Models, Factors, Goal, z(C0, D0, C1, D1)),
    W0 is (1 - P0) * C0 + P0 * C1, H0 is (1 - P0) * D0 + P0 * D1,
    W1 is (1 - P1) * C0 + P1 * C1, H1 is (1 - P1) * D0 + P1 * D1,
    Z0 is A0 * W0, N0 is B0 * W0 + A0 * H0,
    Z1 is A1 * W1, N1 is B1 * W1 + A1 * H1.

graph_tree_factor(Type, [T, _, _, TV], A0-A1, L0-L1) :-
    ( T == Type
    -> 'evidence-confidence-k'(K), pearl_factor(K, TV, M), Q is 1 - M,
       safe_log(Q, F0), safe_log(M, F1), log_add(A0, F0, L0), log_add(A1, F1, L1)
    ; L0 = A0, L1 = A1 ).

graph_terms(Models, Factors, Goal, Vars, Terms) :-
    findall(LW-Lits-Hits,
            ( maplist([model(T, _, _), T-B]>>member(B, [0, 1]), Models, Bits),
              foldl(graph_factor(Bits), Factors, 0.0, LF), LF \== ninf,
              maplist(graph_literal(Bits), Models, All),
              foldl(graph_fixed(Vars), All, LF-[], LW-Lits), LW \== ninf,
              ( graph_holds(Goal, Bits) -> Hits = [1] ; Hits = [] ) ), Worlds),
    Worlds \== [],
    foldl([LW-_-_, M0, M]>>(M is max(M0, LW)), Worlds, -1.0e300, Top),
    maplist({Top}/[LW-Lits-Hits, (Lits-Hits)-C]>>(C is exp(LW - Top)), Worlds, Weighted),
    keysort(Weighted, Ordered), group_pairs_by_key(Ordered, Groups),
    maplist([ (Lits-Hits)-Cs, t(C, Lits, Hits) ]>>(sum_list(Cs, C)), Groups, Terms).

% Integrate point parameters into the coefficient before quadrature. Worlds
% with the same remaining monomial and goal can then be summed exactly.
graph_fixed(Vars, Id-B, W0-L0, W-L) :-
    memberchk(Id-Dist, Vars),
    ( Dist = point(P)
    -> ( B =:= 1 -> F = P ; F is 1 - P ), safe_log(F, LF), log_add(W0, LF, W), L = L0
    ; W = W0, L = [Id-B|L0] ).

graph_literal(Bits, model(Type, root, _), Type-B) :- memberchk(Type-B, Bits).
graph_literal(Bits, model(Type, conditional(Parent, _, _, _), _), branch(Type, P)-B) :-
    ( graph_holds(Parent, Bits) -> P = 1 ; P = 0 ), memberchk(Type-B, Bits).

graph_factor(Bits, [Type, _, _, TV], L0, L) :-
    'evidence-confidence-k'(K), pearl_factor(K, TV, M),
    ( graph_holds(Type, Bits) -> F = M ; F is 1 - M ), safe_log(F, LF), log_add(L0, LF, L).

graph_holds(['Not', T], Bits) :- !, \+ graph_holds(T, Bits).
graph_holds(['And'|Ts], Bits) :- !, forall(member(T, Ts), graph_holds(T, Bits)).
graph_holds(['Or'|Ts], Bits) :- !, member(T, Ts), graph_holds(T, Bits), !.
graph_holds(T, Bits) :- memberchk(T-1, Bits).

graph_proof(Models, Factors, Scope, [node, [conjunction|Proofs]], Evidence, Deps) :-
    findall(Fact, ( member(model(_, _, Fs), Models), member(Fact, Fs) ), Inputs),
    append(Inputs, Factors, All), sort(All, Facts),
    maplist({Scope}/[Fact, Proof-Ev]>>( Fact = [Type|_], 'index-hash'(['sk-key', Type, Scope], H),
                              'sk-leaf-view'(H, Fact, ['sk-val', [_, _, Proof, _], Ev, _]) ), Facts, Leaves),
    findall(Proof-Ev,
            ( member(model(Type, conditional(_, Id-Name, _, _), _), Models),
              'rule-result-evidence'([Type, Scope, [by, Name, cpu], ['STV', 0.5, 0.0]], ['ev-set', 0], Ev),
              'sk-store-proof!'(Id, [by, Name, cpu], Ev, Proof) ), Rules),
    append(Leaves, Rules, Sources), pairs_keys_values(Sources, Proofs, Evs),
    foldl([Ev, E0, E]>>'evidence-union'(E0, Ev, E), Evs, ['ev-set', 0], Evidence),
    findall(D, ( ( member(model(Type, root, _), Models) ; member([Type|_], Factors) ),
                 'index-hash'(['sk-key', Type, Scope], H), 'deps-key'(H, D) ), Ds),
    'deps-join'(Ds, Deps).
