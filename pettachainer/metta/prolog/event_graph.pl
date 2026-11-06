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
        append(Groups, Uses), pairs_keys_values(Uses, Ids, Laws), pairs_keys(Laws, Owners),
        pairs_keys_values(Bindings, Ids, Owners), sort(Laws, Params), pairs_keys(Params, Keys), sort(Keys, Keys),
        graph_fold(Models, Factors, Goal, Bindings, Folded, FoldedFactors, FoldedGoal, FoldedBindings),
        findall(P-D, member(['sk-val', [_, _, P, _], _, D], Priors), PDs),
        pairs_keys_values(PDs, Ps, Ds), append(Proofs, Ps, All), 'deps-join'([D0|Ds], Deps),
        graph_answer(Key, Folded, FoldedFactors, FoldedGoal, FoldedBindings-Params, TV), TV \== unpaid,
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
      retractall(event_graph_input(_, Frame-_, ['sk-key', _, [KB|_]], _)) ),
    term_hash(Key, Hash),
    ( event_graph_plan(Hash, PF, PG, PK, Cached), PF-PG-PK=Frame-Generation-Key -> true
    ; Key = ['sk-key', Goal, Scope],
      node_formula(Goal, _, [], Seeds),
      graph_observations([Goal|Seeds], Scope, Goal, Frame-Generation, [], [], Discovery),
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
        % A sourceless root goal nothing reads is independent of the evidence.
        \+ ( memberchk(model(Goal, root, []), Models),
             \+ ( ( member([T|_], Factors) ; member(model(_, conditional(T, _, _, _), _), Models) ),
                  node_formula(T, _, [], As), memberchk(Goal, As) ) ),
        ( Factors \== [] ; memberchk(model(Goal, root, [_]), Models)
        ; member(model(_, conditional(Parent, _, _, base), _), Models), node_formula(Parent, _, [], As),
          member(A, As), memberchk(model(A, root, [_|_]), Models) ),
        % Enumeration is bounded after folding: at most twelve bits that can
        % vary, so 4,096 worlds and as many monomials. A block is one bit.
        graph_blocks(Models, Factors, Goal, Blocks),
        pairs_values(Blocks, Tss), append(Tss, Blocked), length(Blocks, NB),
        include({Models, Blocked, Factors}/[model(T, M, _)]>>(
                    \+ memberchk(T, Blocked), ( M == root, graph_fixed(T, Models, B) -> true ; true ),
                    graph_choices(T, B, Factors, [_, _]) ), Models, Varying),
        length(Varying, NV), NV + NB =< 12.

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
% A root is fixed when the law of its revised sources is a certain endpoint:
% the law its parameter has, so the cap bills what the enumerator expands.
graph_fixed(T, Models, B) :-
    memberchk(model(T, root, Fs), Models), Fs \== [], graph_revised(Fs, ['STV', S, C]),
    'evidence-confidence-k'(K), event_node_dist(stored, S, C, K, Law), graph_fixed_law(Law, B).

graph_fixed_law(point(P), B) :- ( P =:= 0 -> B = 0 ; P =:= 1, B = 1 ).

% A bit's values: one when a certain observation on it or its law (Fixed)
% decides it, else both. The cap bills and the enumerator expands these.
graph_choices(T, Fixed, Factors, Bs) :-
    (   member([F, _, _, ['STV', S, C]], Factors), F == T, C >= 1, (S =:= 0 ; S =:= 1) -> B is integer(S), Bs = [B]
    ;   nonvar(Fixed) -> Bs = [Fixed]
    ;   Bs = [0, 1] ).

graph_revised(Facts, TV) :-
    foldl([[_T, _C, _P, T], T0, T1]>>'revision-merge-tv'(T0, T, T1), Facts, ['STV', 0.5, 0.0], TV).

% Goals share snapshots of raw sources and templates within the same input epoch and overlay.
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
    ; length(Seen, N), N < 256, graph_input(T, Scope, Stamp, input(Model, Facts, Neighbours))
    -> ( T \== Goal, T = [Head|_], connective_head(Head), Facts == [], Model == root
       -> Next = [], NewKs = Ks
       ; ( Facts = [_|_] -> NewKs = [T|Ks] ; NewKs = Ks ),
         ( T = [Head|Children], connective_head(Head) -> append(Children, Neighbours, Next) ; Next = Neighbours ) ),
       append(Ts, Next, Todo), graph_observations(Todo, Scope, Goal, Stamp, [T|Seen], NewKs, Discovery)
    ; T \== Goal, graph_barren([T], Scope, Seen, Barren)
    -> graph_observations(Ts, Scope, Goal, Stamp, Barren, Ks, Discovery)
    ; Discovery = unsupported ).

% A model-less statement whose region beyond the discovered ones holds no
% evidence (a source with a non-constant likelihood, compound reports
% included) sums out exactly; a model needing it as a parent still fails in
% graph_atoms. The region is watched, so a source there plans again.
graph_barren([], _, Region, Region).
graph_barren([T|Ts], Scope, R0, Region) :-
    ( memberchk(T, R0) -> R = R0, Next = []
    ; length(R0, N), N < 256, source_catalog_sources(T, Scope, Facts),
      'evidence-confidence-k'(K), forall(member([_, _, _, TV], Facts), pearl_factor(K, TV, 0.5)),
      source_catalog_neighbours(T, Scope, Neighbours),
      ( T = [Head|Children], connective_head(Head) -> append(Children, Neighbours, Next) ; Next = Neighbours ),
      R = [T|R0] ),
    append(Ts, Next, Todo), graph_barren(Todo, Scope, R, Region).

graph_atoms([], _, _, Models, Models).
graph_atoms([Type|Rest], Scope, Stamp, M0, Models) :-
    (   memberchk(model(Type, _, _), M0)
    ->  graph_atoms(Rest, Scope, Stamp, M0, Models)
    ;   length(M0, N), N < 256,
        ( Type = [Head|_] -> 'reserved-head?'(Head, false) ; true ),
        graph_input(Type, Scope, Stamp, input(Model, Facts, _)),
        ( Model = conditional(Parent, _, _, _)
        -> node_formula(Parent, _, Rest, Next) ; Next = Rest ),
        graph_atoms(Next, Scope, Stamp, [model(Type, Model, Facts)|M0], Models) ).

% Independent roots may share one bit only when every occurrence is the same
% signed literal under the same And/Or. Paths distinguish nested occurrences;
% a literal goal or a separate report prevents folding that root.
graph_blocks(Models, Factors, Goal, Blocks) :-
    findall(F, (F=Goal ; member([F|_], Factors) ; member(model(_,conditional(F,_,_,_),_), Models)), Forms),
    findall(Signature-T,
        ( member(model(T,root,_), Models),
          findall(S, (nth0(I,Forms,F), graph_occurrence(T,F,[I],S)), Ss), sort(Ss,Signature),
          Signature=[_-(H-B)|_], memberchk(H,['And','Or']),
          forall(member(_-HB,Signature), HB == H-B) ), Pairs),
    keysort(Pairs, Sorted), group_pairs_by_key(Sorted, Groups),
    include([_-[_,_|_]]>>true, Groups, Blocks).

graph_fold(Models, Factors, Goal, Bindings, Folded, Fs, G, Bs) :-
    graph_blocks(Models, Factors, Goal, Blocks),
    foldl(graph_block, Blocks, state(Models,Bindings,[]), state(Ms,Bs,Map)),
    maplist({Map}/[model(T,P,_),model(T,Q,[])]>>(
        P=conditional(A,_,_,_) -> graph_formula(Map,A,B), Q=conditional(B,[],[],[]) ; Q=P), Ms, Folded),
    maplist({Map}/[[T,_,_,TV],[U,[],[],TV]]>>graph_formula(Map,T,U), Factors, Fs),
    graph_formula(Map, Goal, G).

graph_occurrence(T, F, Path, Signature) :-
    ( F == T -> Signature=Path-literal
    ; F=[H|Cs], (connective_head(H) ; H == 'Not'), nth0(I,Cs,C),
      ( C == T -> Signature=Path-(H-1)
      ; C == ['Not',T] -> Signature=Path-(H-0)
      ; graph_occurrence(T,C,[I|Path],Signature) ) ).

% A block's bit holds with the product of its parts' literals, kept in their
% parameters: a parameter read elsewhere, or twice, keeps its powers.
graph_block([_-(H-B)|_]-Ts, state(M0,V0,Map0), state([model(Block,root,[])|Ms],[Block-w(Lits)|Vs],Map)) :-
    Block=block(Ts),
    ( (H-B == 'And'-0 ; H-B == 'Or'-1) -> Bit=0 ; Bit=1 ),
    findall(O-Bit, (member(T,Ts),memberchk(T-O,V0)), Lits),
    ( H == 'Or' -> Replacement=['Not',Block] ; Replacement=Block ),
    findall(T-R, (member(T,Ts),( B=:=0 -> R=['Not',Replacement] ; R=Replacement )), Added),
    exclude({Ts}/[model(T,_,_)]>>memberchk(T,Ts), M0, Ms),
    exclude({Ts}/[T-_]>>memberchk(T,Ts), V0, Vs), append(Added,Map0,Map).

graph_formula(Map, F, G) :-
    ( memberchk(F-G,Map) -> true
    ; F=[H|Cs], (connective_head(H) ; H == 'Not') -> maplist(graph_formula(Map),Cs,Ds), sort(Ds,Es), G=[H|Es]
    ; G=F ).

% Each use maps an event bit to its parameter's owner and law. Members read
% from one population prior share its rate; uses of one refined rule share
% its branch rates. Every read has the same cavity, so an owner has one law.
% A statement's own counts and an application's stated branches stay local.
graph_parameter(Scope, Ev, Exclude, model(Type, root, Facts), [Type-(Owner-Dist)], Prior) :-
    ( Facts == [] -> 'sk-part-prior'(['sk-key', Type, Scope], Ev, Exclude, Prior) ; Prior = 'sk-none' ),
    ( Facts == [], Prior == 'sk-none', Scope = [KB|_], 'positive-only-pattern?'(KB, Type, true) -> fail ; true ),
    ( Prior = ['sk-val', [_, _, Proof, TV], _, _] -> TV = ['STV', S, C],
      'sk-step-proof'(Proof, ['population-prior', Pattern]), graph_owner(population(Pattern), Owner)
    ; graph_revised(Facts, ['STV', S, C]), Owner = Type ),
    'evidence-confidence-k'(K), event_node_dist(stored, S, C, K, Dist).
graph_parameter(Scope, _, Exclude, model(Type, conditional(_, _, ['rule-truth', Truth], refined), _),
                [branch(Type, 1)-(O1-D1), branch(Type, 0)-(O0-D0)], Value) :-
    'sk-value'(['sk-key', Truth, Scope], 'sk-any-filter', Exclude, Value),
    Value = ['sk-val', [_, _, _, ['CTV', ['STV', S1, C1], ['STV', S0, C0]]], _, _],
    graph_owner(rule(Truth, 1), O1), graph_owner(rule(Truth, 0), O0),
    'evidence-confidence-k'(K), event_node_dist(stored, S1, C1, K, D1), event_node_dist(stored, S0, C0, K, D0).
graph_parameter(Scope, Ev, Exclude, model(Type, conditional(_, _, ['STV', S1, C1], Neg), _),
                [branch(Type, 1)-(branch(Type, 1)-D1), branch(Type, 0)-Law0], Prior) :-
    'evidence-confidence-k'(K), event_node_dist(stored, S1, C1, K, D1),
    ( Neg == base -> graph_parameter(Scope, Ev, Exclude, model(Type, root, []), [_-Law0], Prior)
    ; Neg = ['STV', S0, C0], event_node_dist(stored, S0, C0, K, D0), Law0 = branch(Type, 0)-D0, Prior = 'sk-none' ).

% Alpha-renamed patterns name one owner.
graph_owner(Term, Owner) :- copy_term_nat(Term, Owner), numbervars(Owner, 0, _).

:- dynamic event_graph_memo/4.
% A computed answer is a free read. A key is admitted to the graph once a
% query with budget needs or reads it, for one evaluation unit if it has a
% model then; an admitted key's later answers refresh as the nodes a search
% built absorb new facts, paid from the reading query's graph tier
% (graph_take), so a query without steps refreshes nothing. Otherwise the key
% reads as the ordinary evaluator has it, so a read without budget returns
% only what exists. Plans are structural. A query's need admits its root
% keys, which it reads after its evaluation has spent the allowance.
:- dynamic event_graph_admitted/2.
'event-graph-prepay!'(Keys, true) :-
    forall(member(Key, Keys), ignore(graph_admit(Key))).

graph_admit(Key) :-
    term_hash(Key, H),
    ( event_graph_admitted(H, Stored), Stored == Key -> true
    ; 'search-id-value'(sk_eval_budget, B), B > 0,
      ( graph_plan(Key, graph(_, _, _)) -> Left is B - 1, nb_setval(sk_eval_budget, Left) ; true ),
      assertz(event_graph_admitted(H, Key)) ).

% Each key keeps its latest answer, reused while its numerical input is unchanged.
graph_answer(Key, Models, Factors, Goal, Vars, TV) :-
    Input = Models-Factors-Goal-Vars, term_hash(Key, Hash),
    ( event_graph_memo(Hash, Key, Stored, TV), Stored=Input -> true
    ; \+ graph_admit(Key) -> TV = unpaid
    ; query_metric_increment('graph-evaluations', _),
      ( graph_moments(Models, Factors, Goal, Vars, TV) -> true
      ; TV = inconsistent, format(user_error, 'event-evidence-impossible: ~q~n', [Goal]) ),
      % A refusal is not an answer: a later read with budget computes it.
      ( TV == unpaid -> true
      ; retractall(event_graph_memo(Hash, Key, _, _)), assertz(event_graph_memo(Hash, Key, Input, TV)) ) ).

% Components that share no bit and no uncertain parameter are independent:
% each is enumerated and integrated alone and their moments multiply. The goal
% splits into its top-level conjuncts; a component without one has N = Z.
graph_moments(Models, Factors, Goal, Bindings-Params, TV) :-
    findall(Group, graph_link(Models, Factors, Goal, Bindings, Params, Group), Groups),
    foldl([G, S0, [M|Rest]]>>( partition({G}/[S]>>(member(X, G), memberchk(X, S)), S0, Touch, Rest),
                               append([G|Touch], A), sort(A, M) ), Groups, [], Sets),
    foldl(graph_component(Models, Factors, Goal, Bindings, Params), Sets, m(1, 1, 1, 1, 1), Moments),
    % Work the remaining allowance cannot pay is refused like unpaid work.
    ( Moments == unaffordable -> TV = unpaid
    ; event_node_answer(Moments, a(S, V, _)), 'evidence-confidence-k'(K), node_stv(K, S, V, TV) ).

graph_component(_, _, _, _, _, _, unaffordable, unaffordable) :- !.
graph_component(Models, Factors, Goal, Bindings, Params, Set, m(A0, B0, C0, D0, E0), Moments) :-
    include({Set}/[model(T, _, _)]>>memberchk(T, Set), Models, Ms),
    include({Set}/[[F|_]]>>( graph_atom(F, A), memberchk(A, Set) ), Factors, Fs),
    findall(C, ( graph_conjunct(Goal, C), graph_atom(C, A), memberchk(A, Set) ), Cs),
    include({Bindings, Params, Fs}/[M]>>graph_bit_choices(Bindings, Params, Fs, M, [_, _]), Ms, Varying),
    length(Varying, NV), length(Ms, NM), length(Fs, NF), Worlds is (1 << NV) * (NM + NF),
    (   \+ graph_take(Worlds)
    ->  Part = unaffordable
    ;   graph_terms(Ms, Fs, ['And'|Cs], Bindings, Params, Terms),
        event_node_expectations(Params, Terms, [1], graph_take, Part) ),
    (   Part = [m(A, B, C, D, E)]
    ->  A1 is A0 * A, B1 is B0 * B, C1 is C0 * C, D1 is D0 * D, E1 is E0 * E, Moments = m(A1, B1, C1, D1, E1)
    ;   Part == unaffordable, Moments = unaffordable ).

% Elements that must share a component: a bit with its parameters and parent
% atoms, a factor's atoms, a goal conjunct's atoms. Points tie nothing.
graph_link(Models, _, _, Bindings, Params, [T|Links]) :-
    member(model(T, M, _), Models),
    findall(O, ( member(Id-E, Bindings), ( Id == T ; Id = branch(U, _), U == T ),
                 ( E = w(Lits) -> member(O-_, Lits) ; O = E ), \+ memberchk(O-point(_), Params) ), Os),
    findall(A, ( M = conditional(P, _, _, _), graph_atom(P, A) ), As), append(Os, As, Links).
graph_link(_, Factors, _, _, _, As) :- member([F|_], Factors), findall(A, graph_atom(F, A), As).
graph_link(_, _, Goal, _, _, As) :- graph_conjunct(Goal, C), findall(A, graph_atom(C, A), As).

graph_bit_choices(Bindings, Params, Factors, model(T, M, _), Bs) :-
    ( M == root, memberchk(T-O, Bindings), memberchk(O-Law, Params), graph_fixed_law(Law, F) -> true ; true ),
    graph_choices(T, F, Factors, Bs).

% Graph numeric work pays from the invocation's graph tier, an allowance as
% large as the evaluation's, at 1/256 unit per scalar operation, before it is
% done. Root reads after the search has spent its allowance still have it.
graph_take(Ops) :-
    'search-id-value'(sk_graph_budget, B), Units is Ops / 256, Units =< B,
    Left is B - Units, nb_setval(sk_graph_budget, Left).

graph_conjunct(Goal, C) :- ( Goal = ['And'|Cs] -> member(C, Cs) ; C = Goal ).
graph_atom(F, A) :- ( F = [H|Cs], (connective_head(H) ; H == 'Not') -> member(C, Cs), graph_atom(C, A) ; A = F ).

graph_terms(Models, Factors, Goal, Bindings, Params, Terms) :-
    findall(LW-Lits-Hits,
            ( maplist({Bindings, Params, Factors}/[Model, T-B]>>(
                  Model = model(T, _, _), graph_bit_choices(Bindings, Params, Factors, Model, Bs), member(B, Bs) ),
                  Models, Bits),
              foldl(graph_factor(Bits), Factors, 0.0, LF), LF \== ninf,
              maplist({Bits, Bindings}/[M, O-B]>>( graph_literal(Bits, M, Id-B), memberchk(Id-O, Bindings) ), Models, All),
              foldl(node_fixed_literal(Params), All, LF-[], LW-Lits), LW \== ninf,
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
            ( member(model(Type, conditional(_, Owners, _, _), _), Models), member(Id-Name, Owners),
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
    retractall(event_graph_input(_,_,_,_)),
    retractall(event_graph_epoch(_,_,_)), retractall(event_graph_plan(_,_,_,_,_)).
