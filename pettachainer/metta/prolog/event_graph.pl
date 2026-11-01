% Admitted conditional graphs: docs/metta/event_node_contract.md.
:- use_module(library(ugraphs)).
:- dynamic event_graph_plan/5, event_graph_input/4, event_graph_epoch/3.
% A source with no likelihoods remains a count. Only posterior answers cross
% the propagated-moment boundary; unsupported reads retain the ordinary value.
'event-network-read'(Key, Filter, Exclude, Ev, Out) :-
    ( graph_plan(Key, graph(Models, Factors, Watched)), Key = ['sk-key', Goal, Scope],
      ( Factors == [], memberchk(model(Goal, root, [Source]), Models)
      ->
         'index-hash'(Key, H), 'sk-leaf-view'(H, Source, Candidate),
         Candidate = ['sk-val', _, Evidence, _],
         'premise-evidence-overlap?'(Ev, Evidence, false),
         'sk-admits?'(Filter, Exclude, Candidate, true)
      ; forall(( member(model(Type, _, _), Models) ; member([Type|_], Factors) ),
               ( Type == Goal -> true ; 'index-hash'(['sk-key', Type, Scope], H), \+ memberchk(H, Exclude) )),
        graph_proof(Models, Factors, Scope, [node, [conjunction|Proofs]], Evidence, D0),
        'premise-evidence-overlap?'(Ev, Evidence, false),
        'evidence-union'(Ev, Evidence, Cavity),
        maplist(graph_parameter(Scope, Cavity, Exclude), Models, Groups, Priors),
        append(Groups, Vars), length(Vars, NV), NV =< 12,
        findall(P-D, member(['sk-val', [_, _, P, _], _, D], Priors), PDs),
        pairs_keys_values(PDs, Ps, Ds), append(Proofs, Ps, All), 'deps-join'([D0|Ds], Deps),
        graph_answer(Models, Factors, Goal, Vars, TV),
        ( TV == inconsistent
        -> 'sk-open-filter?'(Filter, true), Candidate = 'sk-none'
        ; TV = ['STV', S, _], (S =:= 0 ; S =:= 1),
          member(model(Goal, _, Fs), Models), member(Source, Fs), Source = [_, _, _, ['STV', S0, C]],
          C >= 1, S =:= S0
        -> 'index-hash'(Key, H), 'sk-leaf-view'(H, Source, Candidate),
           'sk-admits?'(Filter, Exclude, Candidate, true)
        ; Fact = [Goal, Scope, [node, [conjunction|All]], TV],
          Candidate = ['sk-val', Fact, Evidence, Deps],
          'sk-admits?'(Filter, Exclude, Candidate, true) ) ),
      forall(member(Type, Watched),
             ( Type == Goal -> true ; 'sk-add-use!'(['sk-key', Type, Scope], Key, _) ))
    -> Out = ['event-posterior', Candidate] ; Out = 'no-event-model' ).

graph_plan(Key, Plan) :-
    Key = ['sk-key', _, Scope], ground(Key), Scope = [_, _, _],
    ( context_active(Frame) -> true ; Frame = main ),
    Scope = [KB|_], source_catalog_stamp(KB, Generation),
    ( event_graph_epoch(KB, Frame, Generation) -> true
    ; retractall(event_graph_epoch(KB, Frame, _)), assertz(event_graph_epoch(KB, Frame, Generation)),
      retractall(event_graph_plan(_, Frame, _, ['sk-key', _, [KB|_]], _)),
      retractall(event_graph_input(_, Frame-_, ['sk-key', _, [KB|_]], _)),
      retractall(event_graph_memo(_, _, _)) ),
    term_hash(Key, Hash),
    ( event_graph_plan(Hash, PF, PG, PK, Cached), PF-PG-PK=Frame-Generation-Key -> true
    ; Key = ['sk-key', Goal, Scope],
      graph_observations([Goal], Scope, Goal, Frame-Generation, [], [], Discovery),
      ( Discovery = observed(Observed, Watched), graph_model(Key, Observed, Watched, Frame-Generation, Model)
      -> Cached = Model ; Cached = none ),
      assertz(event_graph_plan(Hash, Frame, Generation, Key, Cached)) ),
    Plan = Cached.

graph_model(['sk-key', Goal, Scope], Observed, Watched, Stamp, graph(Models, Factors, Watched)) :-
        include([T]>>(T = [H|_], connective_head(H)), Observed, Compounds),
        node_formula(['And', Goal|Observed], _, [], Seeds),
        graph_atoms(Seeds, Scope, Stamp, [], Models0), sort(Models0, Models),
        findall(T-P, (member(model(T, conditional(Parent, _, _, _), _), Models),
                        node_formula(Parent, _, [], Ps), member(P, Ps)), Edges),
        vertices_edges_to_ugraph([], Edges, Graph), top_sort(Graph, _),
        findall(Fact, ( member(Type, Compounds), source_catalog_sources(Type, Scope, Fs), member(Fact, Fs) ), CompoundFacts),
        findall(Fact, ( member(model(_, conditional(_, _, _, _), Fs), Models), member(Fact, Fs) ), Reports),
        append(CompoundFacts, Reports, Factors0), sort(Factors0, Unique),
        exclude(graph_settled_factor(Models), Unique, Factors),
        ( Factors \== [] ; memberchk(model(Goal, root, [_]), Models) ).

% A compound already settled by its root inputs carries no information about
% its remaining parts. Keep a zero-weight factor so contradictions still fail.
graph_settled_factor(Models, [Type, _, _, TV]) :-
    Type = [Head|_], connective_head(Head), graph_fixed(Type, Models, Bit),
    'evidence-confidence-k'(K), pearl_factor(K, TV, M),
    ( Bit =:= 1 -> M > 0 ; M < 1 ).

graph_fixed(['Not', T], Models, B) :- !, graph_fixed(T, Models, A), B is 1-A.
graph_fixed(['And'|Ts], Models, B) :- !,
    ( member(T, Ts), graph_fixed(T, Models, 0) -> B = 0
    ; maplist({Models}/[T]>>graph_fixed(T, Models, 1), Ts), B = 1 ).
graph_fixed(['Or'|Ts], Models, B) :- !,
    ( member(T, Ts), graph_fixed(T, Models, 1) -> B = 1
    ; maplist({Models}/[T]>>graph_fixed(T, Models, 0), Ts), B = 0 ).
graph_fixed(T, Models, B) :-
    memberchk(model(T, root, Fs), Models), member([_, _, _, ['STV', S, C]], Fs), C >= 1,
    ( S =:= 0 -> B = 0 ; S =:= 1, B = 1 ).

% Input snapshots are shared across goals, but never across an input epoch
% or overlay. They contain raw sources and templates, not derived summaries.
graph_input(Type, Scope, Stamp, Input) :-
    Key = ['sk-key', Type, Scope], term_hash(Key, H),
    ( event_graph_input(H, IS, IK, Cached), IS-IK=Stamp-Key -> Input = Cached
    ; ( source_catalog_template(Type, Scope, Model),
        \+ ( Type = [Head|_], connective_head(Head), Model \== root ),
        source_catalog_sources(Type, Scope, Facts)
      -> source_catalog_neighbours(Type, Scope, Neighbours), Cached = input(Model, Facts, Neighbours)
      ; Cached = unsupported ),
      assertz(event_graph_input(H, Stamp, Key, Cached)), Input = Cached ).

graph_observations([], _, _, _, Seen, Ks, observed(Observed, Watched)) :- sort(Ks, Observed), sort(Seen, Watched).
graph_observations([T|Ts], Scope, Goal, Stamp, Seen, Ks, Discovery) :-
    ( memberchk(T, Seen)
    -> graph_observations(Ts, Scope, Goal, Stamp, Seen, Ks, Discovery)
    ; length(Seen, N), N < 24, graph_input(T, Scope, Stamp, input(Model, Facts, Neighbours))
    -> ( T \== Goal, T = [Head|_], connective_head(Head), Facts == [], Model == root
       -> Next = [], NewKs = Ks
       ; ( Facts = [_|_] -> NewKs = [T|Ks] ; NewKs = Ks ),
         ( T = [Head|Children], connective_head(Head) -> append(Children, Neighbours, Next) ; Next = Neighbours ) ),
       append(Ts, Next, Todo), graph_observations(Todo, Scope, Goal, Stamp, [T|Seen], NewKs, Discovery)
    ; Discovery = unsupported ).

graph_atoms([], _, _, Models, Models).
graph_atoms([Type|Rest], Scope, Stamp, M0, Models) :-
    (   memberchk(model(Type, _, _), M0)
    ->  graph_atoms(Rest, Scope, Stamp, M0, Models)
    ;   length(M0, N), N < 12,
        ( Type = [Head|_] -> 'reserved-head?'(Head, false) ; true ),
        graph_input(Type, Scope, Stamp, input(Model, Facts, _)),
        ( Model = conditional(Parent, _, _, _)
        -> node_formula(Parent, _, Rest, Next) ; Next = Rest ),
        graph_atoms(Next, Scope, Stamp, [model(Type, Model, Facts)|M0], Models) ).

graph_parameter(Scope, Ev, Exclude, model(Type, root, Facts), [Type-Dist], Prior) :-
    ( Facts == [] -> 'sk-part-prior'(['sk-key', Type, Scope], Ev, Exclude, Prior) ; Prior = 'sk-none' ),
    ( Facts == [], Prior == 'sk-none', Scope = [KB|_], 'positive-only-pattern?'(KB, Type, true) -> fail ; true ),
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
    ( event_graph_memo(Hash, Stored, TV), Stored=Input -> true
    ; ( graph_moments(Models, Factors, Goal, Vars, TV) -> true
      ; TV = inconsistent, format(user_error, 'event-evidence-impossible: ~q~n', [Goal]) ),
      assertz(event_graph_memo(Hash, Input, TV)) ).

graph_moments(Models, Factors, Goal, Vars, TV) :-
    graph_terms(Models, Factors, Goal, Vars, Terms),
    event_node_moments(Vars, Terms, [1], [a(S, V0, Kind)]),
    ( Kind == bound -> V = bound ; V = V0 ),
    'evidence-confidence-k'(K), node_stv(K, S, V, TV).

graph_terms(Models, Factors, Goal, Vars, Terms) :-
    findall(LW-Lits-Hits,
            ( maplist([model(T, _, _), T-B]>>member(B, [0, 1]), Models, Bits),
              foldl(graph_factor(Bits), Factors, 0.0, LF), LF \== ninf,
              maplist(graph_literal(Bits), Models, All),
              foldl(node_fixed_literal(Vars), All, LF-[], LW-Lits), LW \== ninf,
              ( graph_holds(Goal, Bits) -> Hits = [1] ; Hits = [] ) ), Worlds),
    Worlds \== [],
    foldl([LW-_-_, M0, M]>>(M is max(M0, LW)), Worlds, -1.0e300, Top),
    maplist({Top}/[LW-Lits-Hits, (Lits-Hits)-C]>>(C is exp(LW - Top)), Worlds, Weighted),
    keysort(Weighted, Ordered), group_pairs_by_key(Ordered, Groups),
    maplist([ (Lits-Hits)-Cs, t(C, Lits, Hits) ]>>(sum_list(Cs, C)), Groups, Terms).

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
              'next-search-id'(proof_id, Pid),
              'record-proof!'(Pid, Id, [by, Name, cpu], Ev, 0, [], Proof) ), Rules),
    append(Leaves, Rules, Sources), pairs_keys_values(Sources, Proofs, Evs),
    foldl([Ev, E0, E]>>'evidence-union'(E0, Ev, E), Evs, ['ev-set', 0], Evidence),
    findall(D, ( ( member(model(Type, root, _), Models) ; member([Type|_], Factors) ),
                 'index-hash'(['sk-key', Type, Scope], H), 'deps-key'(H, D) ), Ds),
    'deps-join'(Ds, Deps).

% Cache lifecycle belongs to the graph; force-reset requests this operation.
event_graph_reset :-
    retractall(event_graph_memo(_,_,_)), retractall(event_graph_input(_,_,_,_)),
    retractall(event_graph_epoch(_,_,_)), retractall(event_graph_plan(_,_,_,_,_)).
