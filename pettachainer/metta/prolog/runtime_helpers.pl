% Native bootstrap and controller services. Physical state and numerical
% kernels have separate owners below the inference controllers.
:- use_module(library(heaps)).
:- use_module(library(assoc)).
:- use_module(library(nb_set)).
:- use_module(library(yall)).
:- ensure_loaded(context_overlay).
:- ensure_loaded(ingestion).
:- ensure_loaded(sorts).
:- use_module(event_node).
:- ensure_loaded('../compiler/source_ingress').
:- ensure_loaded(source_catalog).
:- ensure_loaded(proof_semantics).
:- ensure_loaded(statistical_ledger).
:- ensure_loaded(event_graph).

:- ensure_loaded(event_values).
:- ensure_loaded(runtime_state).
:- ensure_loaded(application_support).

'sk-force-reset!'([]) :-
    event_graph_reset,
    ( context_active(C) -> true ; C=main ),
    forall(retract(sk_forced_seen(C,Trie)),trie_destroy(Trie)).

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
%
% 'hypothesis-failure-candidates' keeps those that conclude Fact (a false
% fact is the consequent of its candidates, never an antecedent) and whose
% consequent no live hypothesis concludes: Live holds the [Antecedent,
% Consequent] of the live hypotheses concluding Fact's patterns. A single's
% Sighting is marked failed, so it recurs only among failures.
'hypothesis-candidates'(Fact, Layer, Features, Candidates) :-
    hypothesis_features_role(any, Features, Role, Context), hypothesis_candidates(Role, Fact, Layer, Context, Candidates).
'hypothesis-failure-candidates'(Fact, Layer, Features, Live, Candidates) :-
    hypothesis_features_role(concluding, Features, Role, Context), hypothesis_candidates(Role, Fact, Layer, Context, All),
    findall([A, C, Sighting],
            ( member([A, C, S], All), \+ ( member([_, LC], Live), LC =@= C ),
              ( S == none -> Sighting = none ; S = [I, X], Sighting = [failed, I, X] ) ),
            Candidates).

hypothesis_features_role(Role, [link_replay|Features], temporal(Role), Features) :- !.
hypothesis_features_role(Role, Features, Role, Features).

hypothesis_candidates(Role, Fact, Layer, Features, Candidates) :-
    findall(Single, hypothesis_single(Role, Fact, Layer, Features, Single), Singles),
    findall(F-L, ( Role \= temporal(_), member([F, L, now], Features) ), Now),
    findall([A, C, none],
            ( (   pair_below(Now, Layer, Pair), Consequent = Fact
              ;   Role == any, select(Consequent-LC, Now, Rest), Layer < LC,
                  member(B-LB, Rest), LB < LC, msort([Fact, B], Pair) ),
              hypothesis_pair_rule(Pair, Consequent, [A, C]) ),
            Pairs),
    append(Singles, Pairs, Candidates).

hypothesis_single(Role, Fact, Layer, Features, [A, C, [Instance, Context]]) :-
    member([F, L, Relation], Features),
    ( Role = temporal(_) -> Relation \== now ; true ),
    single_order(Relation, Fact, Layer, F, L, Antecedents, Consequent, Above),
    ( (Role == any ; Role == temporal(any)) -> true ; Consequent == Fact ),
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
    ( Features = [link_replay|_] -> Pairs = [] ; hypothesis_exception_pairs(Fact, Layer, Features, Live, Pairs) ).
hypothesis_exception_pairs(Fact, Layer, Features, Live, Pairs) :-
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
    maplist(hypothesis_generalize_argument(Subst), Args, General).
hypothesis_generalize_argument(Subst, Arg, General) :-
    ( atomic(Arg), memberchk(Arg-Var, Subst) -> General = Var ; General = Arg ).

% Observed predicates (runtime/observed_predicates.metta): the ground
% statements of Head at time point Time that a rule of KB concludes (its
% conclusion with the argument at Head's predicate time a variable and every
% other argument ground) and that KB stores no fact of, each as a false fact
% named by its hash.
'closed-world-gaps'(KB, Head, Time, Facts) :-
    (   current_predicate(ccls_index/3), time_layer(Head, KB, Position, _)
    ->  findall(S, ( ccls_index([T, [KB|_], _, _], _, _), T = [Head|_], copy_term(T, S),
                     nth0(Position, S, V), var(V), V = Time, ground(S) ), Found),
        sort(Found, Statements)
    ;   Statements = [] ),
    findall([':', Name, S, ['STV', 0.0, 1.0]],
            ( member(S, Statements), \+ '&kb'(S, [KB|_], _, _),
              term_hash(S, H), atom_concat('unobserved-', H, Name) ),
            Facts).

% A ground statement's place in time, [Time, Layer]: the constant at its
% predicate's time position and its layer (set-predicate-time); [] when
% there is none.
'hypothesis-place'(KB, Statement, Place) :-
    (   is_list(Statement), ground(Statement), Statement = [Head|Args],
        time_layer(Head, KB, Position, Layer),
        nth1(Position, Args, Time), atomic(Time), Time \== []
    ->  Place = [Time, Layer] ; Place = [] ).

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
% A late link considers observations at just its two ends. Keep the same
% shared-constant and true-feature policy as fact ingestion, and the same
% feature bound. Replaying a candidate never recounts an outcome.
'hypothesis-link-observations'(Link, Ends, Max, Observations) :-
    findall(['hm-observation', Fact, Strength, Layer, [link_replay|Features]],
            ( member([_, Time, Fact, Strength, Layer], Ends),
              findall([Seq, Other, T, L],
                      ( member([Seq, T, Other, S, L], Ends), S > 0.5,
                        shared_constants(Fact, Other, Shared), Shared \== [] ), Rows),
              'hypothesis-features'(Fact, Time, Rows, [Link], Max, Features) ),
            Observations).

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
                              time_layer(Head, KB, _, Layer) ), Keyed),
    keysort(Keyed, Sorted), group_pairs_by_key(Sorted, ByLayer), pairs_values(ByLayer, Groups).

% How many of the live hypotheses under review no review had read, which
% this review reads: their &hm_unread rows are removed.
'hypothesis-read!'(KB, Live, Count) :-
    aggregate_all(count, ( member(['hm-reviewed', Name|_], Live), retract('&hm_unread'(Name, KB)) ), Count).
