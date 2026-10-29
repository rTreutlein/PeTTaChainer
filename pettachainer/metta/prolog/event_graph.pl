% Admitted conditional graphs: docs/metta/event_node_contract.md.
:- use_module(library(ugraphs)).
:- dynamic event_graph_scope/4, event_graph_plan/5.
'event-network-read'(Key, Filter, Exclude, Ev, Value, Out) :-
    (   graph_plan(Key, graph(Models, Factors)),
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
    Key = ['sk-key', _, Scope], ground(Key), Scope = [KB, Context, Parameters],
    ( context_active(Frame) -> true ; Frame = main ),
    term_hash(Scope, SH), 'sk-input-epoch'(Key, Epoch),
    'search-id-value'(sk_row_seq, Rows), Generation = Epoch-Rows,
    ( event_graph_scope(SH, Frame-Generation, Scope, Available) -> true
    ; ( member(Head, ['And', 'Or']),
        ( '&kb'([Head|_], Scope, _, ['STV', _, C])
        ; Context \== 'MAIN', '&kb'([Head|_], [KB, 'MAIN', Parameters], _, ['STV', _, C]) ), C > 0
      ; Context == 'MAIN', Frame \== main,
        context_seed(_, Frame, [[Head|_], Scope, _, ['STV', _, C]]),
        memberchk(Head, ['And', 'Or']), C > 0 )
    -> Available = true, assertz(event_graph_scope(SH, Frame-Generation, Scope, true))
    ; Available = false, assertz(event_graph_scope(SH, Frame-Generation, Scope, false)) ),
    Available == true,
    term_hash(Key, Hash),
    ( event_graph_plan(Hash, Frame, Generation, Key, Cached) -> true
    ; ( graph_model(Key, Model) -> Cached = Model ; Cached = none ),
      assertz(event_graph_plan(Hash, Frame, Generation, Key, Cached)) ),
    Plan = Cached.

graph_model(['sk-key', Goal, Scope], graph(Models, Factors)) :-
        graph_observations([Goal], Scope, [], [], Observed),
        include([T]>>(T = [H|_], connective_head(H)), Observed, Compounds), Compounds \== [],
        node_formula(['And'|Observed], _, [], Seeds),
        graph_atoms(Seeds, Scope, [], Models),
        findall(T-P, member(model(T, conditional(P, _, _, _), _), Models), Edges),
        vertices_edges_to_ugraph([], Edges, Graph), top_sort(Graph, _),
        member(model(_, conditional(_, _, _, _), _), Models),
        node_formula(Goal, _, [], GoalAtoms),
        forall(member(T, GoalAtoms), memberchk(model(T, _, _), Models)),
        findall(Fact, ( member(Type, Compounds), graph_sources(Type, Scope, Fs), member(Fact, Fs) ), CompoundFacts),
        findall(Fact, ( member(model(_, conditional(_, _, _, _), Fs), Models), member(Fact, Fs) ), Reports),
        append(CompoundFacts, Reports, Factors0), sort(Factors0, Factors).

graph_observations([], _, _, Ks, Compounds) :- sort(Ks, Compounds).
graph_observations([T|Ts], Scope, Seen, Ks, Compounds) :-
    ( memberchk(T, Seen) -> graph_observations(Ts, Scope, Seen, Ks, Compounds)
    ; length(Seen, N), N < 24,
      ( graph_sources(T, Scope, [_|_]) -> NewKs = [T|Ks] ; NewKs = Ks ),
      Key = ['sk-key', T, Scope], 'index-hash'(Key, Hash),
      findall(P, ( '&sk_row'(Hash, Key, _, ['sk-row', ['sk-ident', Id|_], _, Ps, _]),
                   'rule-live?'(Id, true), member([P, Scope, _, _], Ps), ground(P) ), Inputs),
      ( T = [Head|Children], connective_head(Head) -> append(Children, Inputs, Next) ; Next = Inputs ),
      append(Ts, Next, Todo), graph_observations(Todo, Scope, [T|Seen], NewKs, Compounds) ).

graph_atoms([], _, Models, Models).
graph_atoms([Type|Rest], Scope, M0, Models) :-
    (   memberchk(model(Type, _, _), M0)
    ->  graph_atoms(Rest, Scope, M0, Models)
    ;   length(M0, N), N < 12,
        ( Type = [Head|_] -> 'reserved-head?'(Head, false) ; true ),
        findall(producer(Id, Name, Ps),
                ( ccls_index([Type, Scope, [by, Name, _], _], Id, Ps),
                  'rule-live?'(Id, true), 'context-rule-visible?'(Id, true) ), Producers),
        graph_sources(Type, Scope, Facts),
        (   Producers = [producer(Id, Name, Ps)],
            exclude([P]>>(P = ['CPU', 'ContextRule'|_]), Ps,
                    [[Parent, Scope, _, PTV], ['CPU', 'CTVModusPonensFormula', [PTV, ['CTV', Pos, Neg]], _]]),
            ground([Parent, Pos, Neg])
        ->  Model = conditional(Parent, Id-Name, Pos, Neg), Next = [Parent|Rest]
        ;   Producers == [], Model = root, Next = Rest ),
        graph_atoms(Next, Scope, [model(Type, Model, Facts)|M0], Models) ).

% Authored leaves only; derived copies are not observations.
graph_sources(Type, Scope, Facts) :-
    Key = ['sk-key', Type, Scope], 'index-hash'(Key, H),
    'sk-key-leaves'(Key, 'sk-any-filter', Leaves),
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
    findall(LW-Bits-Lits-Hits,
            ( maplist([model(T, _, _), T-B]>>member(B, [0, 1]), Models, Bits),
              maplist(graph_literal(Bits), Models, Lits),
              foldl(graph_factor(Bits), Factors, 0.0, LW), LW \== ninf,
              ( graph_holds(Goal, Bits) -> Hits = [1] ; Hits = [] ) ), Worlds),
    Worlds \== [],
    foldl([LW-_-_-_, M0, M]>>(M is max(M0, LW)), Worlds, -1.0e300, Top),
    maplist({Top}/[LW-_-Lits-Hits, t(C, Lits, Hits)]>>(C is exp(LW - Top)), Worlds, Terms),
    event_node_moments(Vars, Terms, [1], [a(S, V0, Kind)]),
    ( Kind == bound -> V = bound ; V = V0 ),
    'evidence-confidence-k'(K), node_stv(K, S, V, TV).

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
