% Event-node semantics and numerical contracts: docs/metta/event_node_contract.md.
:- use_module(library(heaps)).
:- use_module(library(assoc)).
:- use_module(library(nb_set)).
:- use_module(library(yall)).
:- dynamic support_identity/3, support_identity_owner/1.
:- ensure_loaded(context_overlay).
:- ensure_loaded(ingestion).
:- ensure_loaded(sorts).
:- use_module(event_node).
:- ensure_loaded(event_graph).

'event-node-message'(Formula, Index, K, [KProof, KTV], Siblings, Proofs, Keys,
                     ['node-message-result', TV, Likelihood]) :-
    observed(KProof, KTV),
    pearl_factor(K, KTV, Factor),
    Factor =\= 0.5,
    atom_dists(K, Formula, Index, Siblings, Proofs, Dists),
    nth0(Index, AllKeys, target, Keys),
    Likelihood = [likelihood, Formula, Index, Factor, AllKeys, Dists],
    'pearl-moments'(K, cpu, uniform, [Likelihood], TV).

'event-node-jeffrey'(Formula, Index, K, [KProof, KTV], Siblings, Proofs, _Keys,
                     ['node-jeffrey-result', TV, [conditionals, [F1, V1], [F0, V0]]]) :-
    \+ observed(KProof, KTV),
    KTV = ['STV', Ps, Pc], Pc > 0.0,
    atom_dists(K, Formula, Index, Siblings, Proofs, Dists0),
    nth0(Index, Dists0, _, Others),
    nth0(Index, D1, point(1.0), Others), node_answer(Formula, D1, 0.5, [Formula], [a(F1, V1, _)]),
    nth0(Index, D0, point(0.0), Others), node_answer(Formula, D0, 0.5, [Formula], [a(F0, V0, _)]),
    abs(F1 - F0) > 1.0e-12,
    VarU is 1.0 / 12,
    jeffrey_posterior(K, 0.5, VarU, Ps, Pc, F1, V1, F0, V0, S, V, _),
    node_stv(K, S, V, TV).

'event-node-value'(Formula, Index, K, [KProof, KTV], Siblings, Proofs, Keys, TV) :-
    (   observed(KProof, KTV)
    ->  'event-node-message'(Formula, Index, K, [KProof, KTV], Siblings, Proofs, Keys,
                             ['node-message-result', TV, _])
    ;   'event-node-jeffrey'(Formula, Index, K, [KProof, KTV], Siblings, Proofs, Keys,
                             ['node-jeffrey-result', TV, _]) ).

% K's own connective over all its children in another order is K.
'event-node-joint'([Head|Children], [Head|Goal], _, [_, KTV], _, _, _, KTV) :-
    msort(Children, Sorted), msort(Goal, Sorted), !.
'event-node-joint'(Formula, Goal, K, [KProof, KTV], Atoms, Proofs, _Keys, TV) :-
    KTV = ['STV', _, Ck], Ck > 0.0,
    maplist(part_dist(K), Atoms, Proofs, Dists),
    (   observed(KProof, KTV)
    ->  KTV = ['STV', Sk, _], \+ ( Ck < 1.0, Sk =:= 0.5 ),
        pearl_factor(K, KTV, Factor), node_answer(Formula, Dists, Factor, [Goal], [a(S, V0, Kind)]),
        ( Kind == bound -> V = bound ; V = V0 ),
        node_stv(K, S, V, TV)
    ;   jeffrey_joint(Formula, Dists, K, KTV, Goal, S, V), node_stv(K, S, V, TV) ).

% The atoms' distributions with the atom at Index neutral, failing where the
% other atoms settle K whatever the atom is.
atom_dists(K, Formula, Index, Siblings, Proofs, Dists) :-
    maplist(part_dist(K), Siblings, Proofs, Others),
    nth0(Index, Dists, point(0.5), Others),
    \+ settled_by_siblings(Formula, Index, Dists).

settled_by_siblings(Formula, Index, Dists) :-
    \+ ( maplist(possible_bit, Dists, Bits0),
         nth0(Index, Bits0, _, Rest),
         nth0(Index, B1, 1, Rest), nth0(Index, B0, 0, Rest),
         ( formula_holds(Formula, B1) -> \+ formula_holds(Formula, B0) ; formula_holds(Formula, B0) ) ).

possible_bit(point(X), B) :- !, ( X =< 0.0 -> B = 0 ; X >= 1.0 -> B = 1 ; member(B, [0, 1]) ).
possible_bit(_, B) :- member(B, [0, 1]).

formula_holds(I, Bits) :- integer(I), !, nth0(I, Bits, 1).
formula_holds(['Not', F], Bits) :- !, \+ formula_holds(F, Bits).
formula_holds(['And'|Fs], Bits) :- !, forall(member(F, Fs), formula_holds(F, Bits)).
formula_holds(['Or'|Fs], Bits) :- member(F, Fs), formula_holds(F, Bits), !.

connective_head(Head) :- atom(Head), memberchk(Head, ['And', 'Or']).

'node-formula'(Statement, [Formula, Atoms]) :- node_formula(Statement, Formula, [], Atoms).

node_formula([Head|Args], [Head|Fs], A0, A) :- connective_head(Head), !, foldl(node_formula, Args, Fs, A0, A).
node_formula([Head, X], ['Not', F], A0, A) :- Head == 'Not', !, node_formula(X, F, A0, A).
node_formula(S, I, A0, A) :- ( nth0(I, A0, S0), S0 == S -> A = A0 ; length(A0, I), append(A0, [S], A) ).

part_dist(_, _, 'unknown-part', beta(1.0, 1.0)) :- !.
part_dist(_, 'no-evidence', _, beta(1.0, 1.0)) :- !.
part_dist(K, ['STV', S, C], Proof, Dist) :-
    ( stored_proof(Proof) -> Kind = stored ; Kind = view ),
    event_node_dist(Kind, S, C, K, Dist).

observed(KProof, ['STV', _, Ck]) :- ( Ck >= 1.0 -> true ; stored_proof(KProof) ).

stored_proof(Proof) :-
    nonvar(Proof),
    ( Proof = ['proof-ref', Pid], user:'&proof'(Pid, Stored, _, _) -> true ; Stored = Proof ),
    (   Stored = ['fact-source', _, _] -> true
    ;   Stored = ['@', _, Merge] -> stored_proof(Merge)
    ;   Stored = ['merge/revision', Left, Right], stored_proof(Left), stored_proof(Right) ).

% An observation's factor on the worlds where K holds, and 1 - it elsewhere:
% its predictive strength, or its strength when certain.
pearl_factor(K, ['STV', Sk, Ck], M) :-
    Ck > 0.0,
    ( Ck >= 1.0 -> M = Sk ; N is K * Ck / (1 - Ck), M is (N * Sk + 1) / (N + 2) ).

jeffrey_joint(Formula, Dists, K, ['STV', Ps, Pc], Goal, S, V) :-
    node_answer(Formula, Dists, 0.5, [Formula], [a(Pp, Vp, _)]),
    revised_target(K, Pp, Vp, Ps, Pc, Pstar, Nsum),
    ( Pstar > 0.0 -> node_answer(Formula, Dists, 1.0, [Goal], [a(S1, V1, _)]) ; S1 = 0.0, V1 = 0.0 ),
    ( Pstar < 1.0 -> node_answer(Formula, Dists, 0.0, [Goal], [a(S0, V0, _)]) ; S0 = 0.0, V0 = 0.0 ),
    S is Pstar * S1 + (1 - Pstar) * S0,
    V is (Pstar * sqrt(V1) + (1 - Pstar) * sqrt(V0)) ** 2 + (S1 - S0) ** 2 * Pstar * (1 - Pstar) / (Nsum + 1).

revised_target(K, Pp, Vp, Ps, Pc, Pstar, Nsum) :-
    ( Vp > 0.0 -> Np is max(0.0, Pp * (1 - Pp) / Vp - 1) ; Np = 1.0e12 ),
    ( Pc >= 1.0 -> Nr = 1.0e12 ; Nr is K * Pc / (1 - Pc) ),
    Nsum is Np + Nr,
    ( Nsum > 0.0 -> Pstar is (Np * Pp + Nr * Ps) / Nsum ; Pstar = Pp ).

% The node over atoms: K holds in the worlds where Formula does, weighted M,
% the others 1 - M; the goals are formulas over the same atoms.
node_answer(Formula, Dists, M, Goals, Answers) :-
    length(Dists, Count), Last is Count - 1, numlist(0, Last, Is),
    maplist([I, Id-D, D]>>atom_concat(c, I, Id), Is, Vars, Dists),
    findall(t(Coef, Lits, Hits),
            ( length(Bits, Count), maplist([B]>>member(B, [0, 1]), Bits),
              ( formula_holds(Formula, Bits) -> Coef = M ; Coef is 1 - M ),
              Coef > 0,
              maplist([I, B, Id-B]>>atom_concat(c, I, Id), Is, Bits, Lits),
              findall(G, ( nth1(G, Goals, Goal), formula_holds(Goal, Bits) ), Hits) ),
            Terms),
    length(Goals, NG), numlist(1, NG, GoalIds),
    event_node_moments(Vars, Terms, GoalIds, Answers),
    Answers \== inconsistent.

'pearl-moments'(K, BaseProof, Prior, Likelihoods0, TV) :-
    msort(Likelihoods0, Likelihoods),
    prior_dist(K, BaseProof, Prior, PDist),
    (   separable(Likelihoods)
    ->  maplist(literal_factor, Likelihoods, Factors),
        separable_moments(PDist, Factors, S, V, Max)
    ;   union_node(PDist, Likelihoods, S, V), Max is S * (1 - S) ),
    node_stv(K, S, V, Max, TV).

prior_dist(_, _, uniform, beta(1.0, 1.0)) :- !.
prior_dist(K, BaseProof, ['STV', S, C], Dist) :-
    (   ( stored_proof(BaseProof) ; 'sk-step-proof'(BaseProof, ['population-prior'|_]) )
    ->  Kind = stored ; Kind = view ),
    event_node_dist(Kind, S, C, K, Dist).

% Every compound a connective over distinct literals, no other atom shared.
separable(Likelihoods) :-
    maplist([[likelihood, F|_]]>>literal_formula(F), Likelihoods),
    foldl(sibling_keys, Likelihoods, [], All),
    sort(All, Distinct), same_length(All, Distinct).
sibling_keys([likelihood, _, I, _, Keys, _], S0, S) :- nth0(I, Keys, _, Others), append(Others, S0, S).
literal_formula([C|Ls]) :- memberchk(C, ['And', 'Or']), maplist(literal, Ls, Is), sort(Is, Distinct), same_length(Is, Distinct).
literal(I, I) :- integer(I).
literal(['Not', I], I) :- integer(I).
literal_of(I, L) :- literal(L, I).

literal_factor([likelihood, [C|Ls], I, M, _, Dists], f(W, L1, L0)) :-
    partition(literal_of(I), Ls, [TargetLit], Others),
    maplist(literal_dist(Dists), Others, OtherDists),
    (   C == 'And'
    ->  product_dist(OtherDists, W), A1 = l(Mc, B1), Mc is 1 - M, B1 is 2 * M - 1, A0 = l(Mc, 0.0)
    ;   maplist(complement_dist, OtherDists, Comps), product_dist(Comps, W),
        A1 = l(M, 0.0), A0 = l(M, B0), B0 is 1 - 2 * M ),
    ( TargetLit = ['Not', _] -> L1 = A0, L0 = A1 ; L1 = A1, L0 = A0 ).

literal_dist(Dists, I, D) :- integer(I), !, nth0(I, Dists, D).
literal_dist(Dists, ['Not', I], D) :- nth0(I, Dists, D0), complement_dist(D0, D).

separable_moments(PDist, Factors, S, V, Max) :-
    dist_mean(PDist, Mu),
    maplist([f(W, _, _), Mw]>>moments(W, Mw, _), Factors, Ws),
    log_lambdas(Factors, Ws, LL1, LL0),
    log_weighted(Mu, LL1, A), log_weighted_complement(Mu, LL0, B),
    log_sum(A, B, LZ),
    LZ \== ninf,
    exp_diff(A, LZ, S),
    ( ( A == ninf ; B == ninf ) -> Max = 0.0 ; Max is exp(A + B - 2 * LZ) ),
    maplist(narrowed, Factors, Narrowed),
    include([f(W, _, _)]>>( W \= point(_) ), Narrowed, Wide),
    ( PDist = point(_) -> PDims = [] ; PDims = [PDist] ),
    findall(W, member(f(W, _, _), Wide), WDists),
    append(PDims, WDists, Dims0),
    ( Dims0 = [beta(Ab, Bb)], Ab >= 1.0, Bb >= 1.0, Ab + Bb =< 10.0 -> Dims = [broad(beta(Ab, Bb))] ; Dims = Dims0 ),
    length(Dims, D),
    (   ( D =:= 0 ; Max =:= 0.0 )
    ->  V = 0.0
    ;   D > 4
    ->  V = bound
    ;   Dims = [broad(Dist)]
    ->  graded_points(Dist, Points), second_moment(PDist, Narrowed, LZ, Points, E), V is max(0.0, E - S * S)
    ;   first_rule(D, N),
        separable_variance(PDist, Narrowed, Dims, N, LZ, S, V0),
        separable_refined(PDist, Narrowed, Dims, D, N, V0, LZ, S, V) ).

% A factor whose lambdas change by less than 1e-9 of themselves over its W's
% whole range is constant to that precision: its W is a point at its mean.
narrowed(f(W, L1, L0), f(Point, L1, L0)) :-
    W \= point(_), moments(W, Mw, _),
    forall(member(L, [L1, L0]), lambda_flat(L, Mw)), !, Point = point(Mw).
narrowed(F, F).

lambda_flat(L, Mw) :-
    lambda_at(L, Mw, X), lambda_at(L, 0.0, X0), lambda_at(L, 1.0, X1),
    ( X =:= 0.0 -> X0 =:= 0.0, X1 =:= 0.0 ; abs(X0 - X) =< 1.0e-9 * X, abs(X1 - X) =< 1.0e-9 * X ).

graded_points(beta(A, B), Points) :-
    numlist(1, 12, Ks),
    maplist([K, X]>>(X is 10.0 ** (-K)), Ks, Lows0), reverse(Lows0, Lows),
    maplist([X, Y]>>(Y is 1 - X), Lows0, Highs),
    append([[0.0], Lows, [0.5], Highs, [1.0]], Breaks),
    dist_rule(beta(1.0, 1.0), 16, rule(Us, Ws)),
    LogBeta is lgamma(A) + lgamma(B) - lgamma(A + B),
    findall(Wt-[X],
            ( nextto(Lo, Hi, Breaks), nth1(I, Us, U), nth1(I, Ws, Wu),
              X is Lo + (Hi - Lo) * U,
              Wt is Wu * (Hi - Lo) * exp((A - 1) * log(X) + (B - 1) * log(1 - X) - LogBeta) ),
            Points).

second_moment(PDist, Factors, LZ, Points, E) :-
    ( PDist = point(P0) -> PFixed = yes(P0) ; PFixed = no ),
    foldl(second_term(PFixed, Factors, LZ), Points, 0.0, E).

first_rule(1, 33).
first_rule(2, 17).
first_rule(3, 9).
first_rule(4, 5).

separable_refined(PDist, Factors, Dims, D, N, V0, LZ, S, V) :-
    N1 is 2 * N - 1,
    (   ( N1 > 257 ; N1 ** D > 70000 )
    ->  V = bound
    ;   catch(separable_variance(PDist, Factors, Dims, N1, LZ, S, V1), error(evaluation_error(_), _), fail)
    ->  (   agree_variance(V0, V1) -> V = V1
        ;   separable_refined(PDist, Factors, Dims, D, N1, V1, LZ, S, V) )
    ;   V = bound ).

separable_variance(PDist, Factors, Dims, N, LZ, S, V) :-
    second_tensor(PDist, Factors, Dims, N, LZ, E), V is max(0.0, E - S * S).

agree_variance(V1, V2) :- abs(V1 - V2) =< 0.01 * max(V1, V2) + 1.0e-300.

% Logs with ninf for log 0.
safe_log(X, L) :- ( X > 0.0 -> L is log(X) ; L = ninf ).
log_add(ninf, _, ninf) :- !.
log_add(_, ninf, ninf) :- !.
log_add(A, B, C) :- C is A + B.
log_sum(ninf, B, B) :- !.
log_sum(A, ninf, A) :- !.
log_sum(A, B, C) :- M is max(A, B), C is M + log(exp(A - M) + exp(B - M)).
exp_diff(ninf, _, 0.0) :- !.
exp_diff(A, B, X) :- X is exp(A - B).
log_weighted(P, LL, A) :- safe_log(P, LP), log_add(LP, LL, A).
log_weighted_complement(P, LL, B) :- Q is 1 - P, safe_log(Q, LQ), log_add(LQ, LL, B).

% The factors' log lambda products at the W values Ws.
log_lambdas(Factors, Ws, LL1, LL0) :-
    foldl([f(_, A1, A0), Wv, L10-L00, L1-L0]>>( lambda_at(A1, Wv, X1), lambda_at(A0, Wv, X0),
                                               safe_log(X1, G1), safe_log(X0, G0),
                                               log_add(L10, G1, L1), log_add(L00, G0, L0) ),
          Factors, Ws, 0.0-0.0, LL1-LL0).

lambda_at(l(A, B), W, X) :- X is A + B * W.

complement_dist(point(X), point(Y)) :- Y is 1 - X.
complement_dist(bernoulli(M), bernoulli(N)) :- N is 1 - M.
complement_dist(beta(A, B), beta(B, A)).

moments(point(X), X, X2) :- X2 is X * X.
moments(bernoulli(M), M, M).
moments(beta(A, B), M, X2) :- M is A / (A + B), X2 is A * (A + 1) / ((A + B) * (A + B + 1)).

% The product of independent parts: a point when every part is one, else
% the Beta with the product's two moments (its distribution is not a Beta).
product_dist([], point(1.0)) :- !.
product_dist([D], D) :- !.
product_dist(Ds, point(M)) :- maplist([point(_)]>>true, Ds), !,
    foldl([point(X), P0, P]>>(P is P0 * X), Ds, 1.0, M).
product_dist(Ds, beta(A, B)) :-
    foldl([D, M0-X0, M1-X1]>>( moments(D, M, X2), M1 is M0 * M, X1 is X0 * X2 ), Ds, 1.0-1.0, M-X2),
    Var is max(X2 - M * M, 1.0e-300),
    T is max(0.0, M * (1 - M) / Var - 1), A is max(1.0e-6, M * T), B is max(1.0e-6, (1 - M) * T).

second_tensor(PDist, Factors, Dims, N, LZ, E) :-
    maplist(sized_rule(N), Dims, Rules),
    findall(W-Xs, tensor_point(Rules, 1.0, W, Xs), Points),
    second_moment(PDist, Factors, LZ, Points, E).

sized_rule(N, Dist, Rule) :- dist_rule(Dist, N, Rule).

tensor_point([], W, W, []).
tensor_point([rule(Xs, Ws)|Rules], W0, W, [X|Rest]) :-
    nth1(I, Xs, X), nth1(I, Ws, Wi), W1 is W0 * Wi,
    tensor_point(Rules, W1, W, Rest).

second_term(PFixed, Factors, LZ, W-Xs, E0, E) :-
    (   PFixed = yes(P) -> Ws0 = Xs ; Xs = [P|Ws0] ),
    point_ws(Factors, Ws0, Ws),
    log_lambdas(Factors, Ws, LL1, LL0),
    log_weighted(P, LL1, A), log_weighted_complement(P, LL0, B),
    log_sum(A, B, LZp),
    (   ( A == ninf ; LZp == ninf ; W =< 0.0 ) -> E = E0
    ;   E is E0 + exp(log(W) + 2 * A - LZp - LZ) ).

% Each factor's W at a tensor point: its point value, or the next wide value.
point_ws([], [], []).
point_ws([f(point(Wv), _, _)|Fs], Wide, [Wv|Ws]) :- !, point_ws(Fs, Wide, Ws).
point_ws([_|Fs], [Wv|Wide], [Wv|Ws]) :- point_ws(Fs, Wide, Ws).

union_node(PDist, Likelihoods, S, V) :-
    foldl(union_atoms, Likelihoods, [target-PDist], Atoms),
    length(Atoms, Count), Count =< 12,
    maplist(local_map(Atoms), Likelihoods, Maps),
    Last is Count - 1, numlist(0, Last, Is),
    maplist([I, _-D, Id-D]>>atom_concat(c, I, Id), Is, Atoms, Vars),
    findall(LW-Bits,
            ( length(Bits, Count), maplist([B]>>member(B, [0, 1]), Bits),
              foldl(world_log_factor(Bits), Likelihoods, Maps, 0.0, LW), LW \== ninf ),
            Worlds),
    Worlds \== [],
    foldl([LW-_, M0, M]>>(M is max(M0, LW)), Worlds, -1.0e300, Top),
    findall(t(Coef, Lits, Hits),
            ( member(LW-Bits, Worlds), Coef is exp(LW - Top),
              maplist([I, B, Id-B]>>atom_concat(c, I, Id), Is, Bits, Lits),
              ( Bits = [1|_] -> Hits = [1] ; Hits = [] ) ),
            Terms),
    event_node_moments(Vars, Terms, [1], [a(S, V0, Kind)]),
    ( Kind == bound -> V = bound ; V = V0 ).

union_atoms([likelihood, _, I, _, Keys, Dists], A0, A) :-
    foldl([Key, D, B0, B]>>( ( Key == target ; memberchk(Key-_, B0) ) -> B = B0 ; append(B0, [Key-D], B) ),
          Keys, Dists, A0, A),
    nth0(I, Keys, target).

% A message's atoms' indices in the union.
local_map(Atoms, [likelihood, _, _, _, Keys, _], Map) :- maplist(union_index(Atoms), Keys, Map).
union_index(Atoms, Key, J) :- nth0(J, Atoms, Key0-_), Key0 == Key, !.

world_log_factor(Bits, [likelihood, Formula, _, M, _, _], Map, L0, L) :-
    maplist(bit_of(Bits), Map, Local),
    ( formula_holds(Formula, Local) -> X = M ; X is 1 - M ),
    safe_log(X, G), log_add(L0, G, L).


'jeffrey-posterior'(K, Bs, Bc, ['STV', Ps, Pc], [conditionals, [F1, V1], [F0, V0]], TV) :-
    ideal_variance(K, Bs, Bc, VarP),
    jeffrey_posterior(K, Bs, VarP, Ps, Pc, F1, V1, F0, V0, S, V, _),
    node_stv(K, S, V, TV).

jeffrey_posterior(K, P, VarP, Ps, Pc, F1, V1, F0, V0, S, V, Pstar) :-
    Pp is P * F1 + (1 - P) * F0,
    (   ( Pp =< 1.0e-12 ; Pp >= 1 - 1.0e-12 )
    ->  S = P, V = VarP, Pstar = Pp
    ;   % the exact variance of p f1 + (1 - p) f0 over independent p, f1, f0
        % (node_answer's moments), the products' Var(p) Var(f) included
        Vp is (F1 - F0) ** 2 * VarP + (P ** 2 + VarP) * V1 + ((1 - P) ** 2 + VarP) * V0,
        revised_target(K, Pp, Vp, Ps, Pc, Pstar, _),
        kinematics(Vp, K, P, Ps, Pc, F1, F0, S),
        ideal_variance(K, Ps, Pc, VarS),
        Inputs = [P-VarP, F1-V1, F0-V0, Ps-VarS],
        foldl(kinematics_variance(K, P, Ps, Pc, F1, F0, Vp), [1, 2, 3, 4], Inputs, 0.0, V) ).

% The posterior as a function of its inputs, the parts' count fixed at the
% variance the inputs give.
kinematics(Vp, K, P, Ps, Pc, F1, F0, S) :-
    Pp is P * F1 + (1 - P) * F0,
    (   ( Pp =< 1.0e-12 ; Pp >= 1 - 1.0e-12 )
    ->  S = P
    ;   revised_target(K, Pp, Vp, Ps, Pc, Pstar, _),
        S is Pstar * P * F1 / Pp + (1 - Pstar) * P * (1 - F1) / (1 - Pp) ).

kinematics_variance(K, P, Ps, Pc, F1, F0, Vp, I, _-Var, V0, V) :-
    H = 1.0e-6,
    nth1(I, [P, F1, F0, Ps], X),
    Xu is min(1.0, X + H), Xd is max(0.0, X - H),
    perturbed(I, Xu, P, Ps, F1, F0, Pu, Psu, F1u, F0u),
    perturbed(I, Xd, P, Ps, F1, F0, Pd, Psd, F1d, F0d),
    kinematics(Vp, K, Pu, Psu, Pc, F1u, F0u, Su),
    kinematics(Vp, K, Pd, Psd, Pc, F1d, F0d, Sd),
    ( Xu > Xd -> D is (Su - Sd) / (Xu - Xd) ; D = 0.0 ),
    V is V0 + D * D * Var.

perturbed(1, X, _, Ps, F1, F0, X, Ps, F1, F0).
perturbed(2, X, P, Ps, _, F0, P, Ps, X, F0).
perturbed(3, X, P, Ps, F1, _, P, Ps, F1, X).
perturbed(4, X, P, _, F1, F0, P, X, F1, F0).

'jeffrey-order'(Values, Ordered) :-
    map_list_to_pairs(jeffrey_order_key, Values, Keyed),
    keysort(Keyed, Sorted),
    pairs_values(Sorted, Ordered).

jeffrey_order_key(['sk-val', [_, _, Proof, _], Ev|_], Key) :-
    'sk-step-proof'(Proof, [['node-jeffrey', Index, _KProof, Prediction, Conditionals]|_]),
    'evidence-entries'(Ev, Entries), msort(Entries, Sources),
    Key = Prediction-Conditionals-Index-Sources.

'observed-rate-evidence'(Facts, Exclude, Ev, ['BaseRateEvidence', W, M]) :-
    'evidence-entries'(Ev, Entries),
    findall(S-C,
            ( member([P, Ctx, Proof, TV], Facts),
              \+ memberchk(['fact-ev', Ctx, Proof, _], Entries),
              'index-hash'(['sk-key', P, Ctx], H), \+ memberchk(H, Exclude),
              positive_tv(TV, S, C) ),
            Members),
    foldl([S-C, W0-M0, W1-M1]>>( W1 is W0 + S * C, M1 is M0 + C ), Members, 0.0-0.0, W-M).

positive_tv(['STV', S, C], S, C).
positive_tv(['CTV', ['STV', S, C], _], S, C).

node_stv(K, S, V, TV) :- ( V == bound -> Max = 0.0 ; Max is S * (1 - S) ), node_stv(K, S, V, Max, TV).
node_stv(_, S, bound, _, ['STV', S, 0.0]) :- !.
node_stv(_, S, V, _, ['STV', S, 0.9999]) :- V =< 0.0, !.
node_stv(K, S, V, Max, ['STV', S, C]) :-
    ( V >= Max -> C = 0.0 ; N is Max / V - 1, C is N / (N + K) ).

% master's ideal-var: s(1 - s)/(n + 1), n = k c/(1 - c); 1/12 at c = 0.
ideal_variance(_, _, C, 0.0) :- C >= 1.0, !.
ideal_variance(_, _, C, V) :- C =< 0.0, !, V is 1.0 / 12.
ideal_variance(K, S, C, V) :- N is K * C / (1 - C), Sc is min(1 - 1.0e-6, max(1.0e-6, S)), V is Sc * (1 - Sc) / (N + 1).


'node-joint-goals'([Head|Children], Goals) :-
    node_formula([Head|Children], [Head|Fs], [], Atoms),
    length(Atoms, NA),
    (   NA > 4
    ->  Goals = []
    ;   findall(F, sub_compound([Head|Fs], F), Inner),
        connective_combos(Head, Fs, Combos),
        LastAtom is NA - 1, numlist(0, LastAtom, AtomIs),
        connective_combos(none, AtomIs, AtomCombos),
        append([Inner, Combos, AtomCombos], All),
        foldl(new_formula, All, [[Head|Fs]], [_|Formulas]),
        maplist(formula_goal(Atoms), Formulas, Goals) ).

% Each And and Or over two or more of Formulas in every order, but Head over
% all of them in their own order.
connective_combos(Head, Formulas, Combos) :-
    length(Formulas, N), Last is N - 1, numlist(0, Last, Is),
    findall([C|GFs],
            ( member(C, ['And', 'Or']), node_subset(Is, Subset), length(Subset, L), L >= 2,
              permutation(Subset, P), \+ ( C == Head, P == Is ), maplist(bit_of(Formulas), P, GFs) ),
            Combos).

new_formula(F, Fs0, Fs) :- ( memberchk(F, Fs0) -> Fs = Fs0 ; append(Fs0, [F], Fs) ).
bit_of(List, I, X) :- nth0(I, List, X).

formula_goal(Atoms, F, [F, S]) :- formula_statement(Atoms, F, S).
formula_statement(Atoms, I, S) :- integer(I), !, nth0(I, Atoms, S).
formula_statement(Atoms, [H|Fs], [H|Ss]) :- maplist(formula_statement(Atoms), Fs, Ss).

% The compounds inside a formula: each And or Or below its top, through Not.
sub_compound([H|Fs], F) :-
    memberchk(H, ['And', 'Or', 'Not']), member(C, Fs),
    ( C = [CH|_], memberchk(CH, ['And', 'Or']), F = C ; sub_compound(C, F) ).

node_subset([], []).
node_subset([X|Xs], [X|Ys]) :- node_subset(Xs, Ys).
node_subset([_|Xs], Ys) :- node_subset(Xs, Ys).

% Rank claims by depth, cost and age, then their pending enumeration sequence.
% Never compare the payload: its hashes include the process's random KB id.
'sk-order-claims'(Claims, Sorted) :-
    findall([Depth,Cost,Age,Sequence]-Claim,
        ( nth0(Sequence,Claims,Claim), Claim=['sk-claim',Depth,Cost,Age,_] ), Pairs),
    keysort(Pairs, Ranked), pairs_values(Ranked, Sorted).

% Membership is evaluation-local and unordered. The pending journal still
% preserves first-arrival order; MAIN and every assumption own distinct tries.
'sk-force-causes!'(Key, Row, Causes, []) :-
    ( context_active(C) -> true ; C=main ),
    ( sk_forced_seen(C,Trie) -> true
    ; trie_new(Trie), assertz(sk_forced_seen(C,Trie)) ),
    forall(member(Cause,Causes),
        ( trie_insert(Trie,forced(Key,Row,Cause))
        -> 'context-add!'('&sk_forced',[Key,Row,Cause],true)
        ; true )).

'sk-force-reset!'([]) :-
    retractall(event_graph_memo(_, _, _)),
    retractall(event_graph_scope(_, _, _, _)),
    retractall(event_graph_plan(_, _, _, _, _)),
    ( context_active(C) -> true ; C=main ),
    forall(retract(sk_forced_seen(C,Trie)),trie_destroy(Trie)).

% Data-only spaces have no function definitions or compiler metadata. In
% particular, an open first column must not enter remove-atom's function case.
'remove-data-rows!'(Space, Pattern, true) :-
    context_store(Space,_,_), context_active(_), !, 'context-remove!'(Space,Pattern,true).
'remove-data-rows!'(Space, Pattern, true) :-
    Row =.. [Space|Pattern],
    retractall(Row).

% Add a row that add-atom could not prove against the space's declared type
% when compiled: the space is named at run time, or a column's type is only
% known then. add-atom checks such a row on every call, which costs more than
% the add itself (PeTTa's analysis hooks raise and catch an exception per
% checked column); the callers build rows of the declared shape.
'add-space-atom!'(Space, Row, true) :-
    context_store(Space,_,_), !, 'context-add!'(Space,Row,true).
'add-space-atom!'(Space, Row, true) :-
    Term =.. [Space|Row],
    assertz(Term).

% Erase the one stored row that is a variant of Row. A removal by unification
% could also take a different row with the same coarse hash; a variant cannot.
'remove-variant-row!'(Space, Row, true) :-
    context_store(Space,_,_), context_active(C), !,
    ( Row=[Hash|_], ground(Hash) -> Lookup=Hash ; true ),
    forall((clause(context_entry(Lookup,C,Space,Stored,_),true,Ref), Stored =@= Row), erase(Ref)),
    ( ground(Lookup) -> Index=Lookup ; Index=all ),
    assertz(context_hidden(Index,C,Space,Row,variant)).
'remove-variant-row!'('&sk_wait', [H, N, W], true) :- !,
    ( sk_wait_ref(H, N, W, Ref) -> erase(Ref) ; true ).
% Find candidates through the caller's bound indexes, but inspect the
% original stored head before erasing: lookup unification can instantiate
% an open stored row and must not turn it into a false variant match.
'remove-variant-row!'(Space, Row, true) :-
    Head =.. [Space|Row],
    copy_term_nat(Head,Lookup),
    ( clause(Lookup,true,Ref), clause(Stored,true,Ref), Stored =@= Head
    -> erase(Ref) ; true ).

% PeTTa arrows have one result position. Package SWI's three relational
% get_from_heap/4 outputs into one positional product.
heap_pop(Heap, [Priority, Value, Rest]) :-
    get_from_heap(Heap, Priority, Value, Rest).

% Test before popping, so a caller can pop without collecting the result: a
% collected pop copies the whole remaining heap.
'heap-empty?'(Heap, Empty) :-
    (   empty_heap(Heap) -> Empty = true ; Empty = false ).

% A statically imported rule dump stores its rule ids without advancing the
% live counter, so the counter's next id may already be taken: a new live rule
% then takes the id past every stored live one. Temp ids start at 10^9.
'fresh-rule-id'(Next, Id) :-
    (   catch(rules('runtime-rule-row', Next, _, _), error(existence_error(procedure, _), _), fail)
    ->  aggregate_all(max(I), (rules('runtime-rule-row', I, _, _), I < 1000000000), Max),
        Id is Max + 1
    ;   Id = Next
    ).

% Whether a rule's hazard may have changed since the last evaluation: a head
% gained or lost a stage position (prolog/sorts.pl), or a KB's rule-change
% hazard was set. The evaluation then brings every standing instance tally to
% its rule's hazard (sk-rehazard-tallies!).
:- dynamic hazards_changed/0.
'hazards-changed!'(true) :- ( hazards_changed -> true ; assertz(hazards_changed) ).
'take-hazards-changed'(Result) :- ( retract(hazards_changed) -> Result = true ; Result = false ).

% A term with the constant arguments of its atoms replaced by variables, one
% per constant, so the samples of one link share one pattern; heads and
% numbers stay.
'generalize-constants'(Term, General) :-
    generalize_constants(Term, General, [], _).

generalize_constants(Term, Term, Seen, Seen) :- var(Term), !.
generalize_constants([Head|Args], [Head|GArgs], Seen0, Seen) :- atom(Head), !,
    foldl(generalize_argument, Args, GArgs, Seen0, Seen).
generalize_constants(Terms, General, Seen0, Seen) :- is_list(Terms), !,
    foldl(generalize_constants, Terms, General, Seen0, Seen).
generalize_constants(Term, Term, Seen, Seen).

generalize_argument(Arg, General, Seen0, Seen) :-
    (   atom(Arg)
    ->  ( memberchk(Arg-Var, Seen0) -> General = Var, Seen = Seen0 ; Seen = [Arg-General|Seen0] )
    ;   generalize_constants(Arg, General, Seen0, Seen) ).

% Hash a lookup column with every variable replaced by one marker, so a row
% keeps an integer SWI can JIT-index; =alpha on the stored key still decides.
'index-hash'(Term, Hash) :-
    (   ground(Term)
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

% Each successive head on the antecedent's first-child path is a more
% selective prefix. Stop at a variable: every unifying ground query includes
% the prefixes of its open templates, including Not's nested predicate.
implication_antecedent_prefixes(Term, Path, Hashes0, Hashes) :-
    (   nonvar(Term), Term = [Head|Args], atomic(Head)
    ->  Next = [Head|Path],
        term_hash(['implication-antecedent-prefix'|Next], Hash),
        (   Args = [First|_]
        ->  implication_antecedent_prefixes(First, Next, [Hash|Hashes0], Hashes)
        ;   Hashes = [Hash|Hashes0]
        )
    ;   Hashes = Hashes0
    ).

% A statement with variables is stored under the hash of exactly its longest
% ground prefix: the head's when it has none, 0 when its head is not an atom.
% A pattern with a ground prefix finds the entries whose longest prefix is at
% least as long as its own through its longest prefix in the prefix index, and
% the others under its shorter prefixes, its head and 0: a bounded number of
% indexed lookups however many entries share its head.
% Fact indexes also retain the nested antecedent's head path. Skeleton node
% indexes keep their existing prefix and scheduling semantics.
'kb-fact-prefix-hashes'(Statement, Hashes) :-
    'statement-prefix-hashes'(Statement, Prefixes),
    (   nonvar(Statement), Statement = [Head|Args], Head == 'Implication',
        nonvar(Args), Args = [Antecedent|_]
    ->  implication_antecedent_prefixes(Antecedent, [], [], Nested),
        append(Prefixes, Nested, Hashes)
    ;   Hashes = Prefixes
    ).

'statement-open-hash'(Statement, Hash) :-
    statement_index_hashes('statement-prefix-hashes', Statement, [Hash|_]).

'statement-open-probes'(Statement, Hashes) :-
    statement_index_hashes('statement-prefix-hashes', Statement, [_|Hashes]).

'kb-fact-open-hash'(Statement, Hash) :-
    statement_index_hashes('kb-fact-prefix-hashes', Statement, [Hash|_]).

'kb-fact-open-probes'(Statement, Hashes) :-
    statement_index_hashes('kb-fact-prefix-hashes', Statement, [_|Hashes]).

statement_index_hashes(PrefixFunction, Statement, Hashes) :-
    (   nonvar(Statement), Statement = [Head|_], atomic(Head)
    ->  call(PrefixFunction, Statement, Prefixes),
        term_hash(Head, HeadHash),
        append(Prefixes, [HeadHash, 0], Hashes)
    ;   Hashes = [0]
    ).

% Outer arguments cannot be filled with a binder's private slots.
'existential-outer-values?'(Values, Valid) :-
    ( sub_term(Term, Values), is_list(Term), Term = [Head, _], Head == 'exists-slot'
    -> Valid = false ; Valid = true ).

% A final tie uses alpha-normalized statement keys, not allocation/proof ids.
'existential-key-before?'(A, B, Before) :-
    copy_term(A, CA), numbervars(CA, 0, _),
    copy_term(B, CB), numbervars(CB, 0, _),
    ( CA @< CB -> Before = true ; Before = false ).

'rule-premise'(Index, Premises, Premise) :- nth0(Index, Premises, Premise).

% Open only canonical slots, preserving free outer variables and co-reference.
% The map belongs to this binder alone; callers never unify source binders.
'existential-source'(Canonical, Source) :-
    (   nonvar(Canonical), Canonical = [Head, Body], Head == 'ExistentialClaim'
    ->  empty_assoc(Empty),
        existential_source(Body, Open, Empty, Slots),
        assoc_to_values(Slots, Vars),
        Source = ['Exists', Vars, Open]
    ;   nonvar(Canonical), Canonical = [Head, A, B], Head == 'Implication'
    ->  'existential-source'(A, SA), 'existential-source'(B, SB),
        Source = ['Implication', SA, SB]
    ;   Source = Canonical ).

existential_source(Term, Source, Before, After) :-
    (   nonvar(Term), Term = [Head, I], Head == 'exists-slot', integer(I)
    ->  ( get_assoc(I, Before, Source) -> After = Before
        ; put_assoc(I, Before, Source, After) )
    ;   is_list(Term)
    ->  foldl(existential_source, Term, Source, Before, After)
    ;   Source = Term, After = Before ).

% The shape a fold's member is compiled for (sk-shape-members). A user
% predicate compiles to its own lookup goal, and a connective over user
% predicates to adapters that only its structure decides, so the predicates'
% ground arguments become variables: folds that differ only in constants,
% such as one per decision step, share one compilation. Variables stay
% shared. Any other pattern (chainer vocabulary) is its own shape. A
% connective with such a child cannot fall through as a user predicate:
% abstracting its children would change what its member compiler receives.
'pattern-shape'(Pattern, Shape) :-
    (   statement_shape(Pattern, Shape) -> true ; Shape = Pattern ).

connective_shape(Pattern, Shape) :-
    nonvar(Pattern), Pattern = [Connective|Children], Children \== [],
    atom(Connective), memberchk(Connective, ['And', 'Or', 'Not']),
    maplist(statement_shape, Children, Shapes),
    Shape = [Connective|Shapes].

statement_shape(Statement, Shape) :-
    (   connective_shape(Statement, Shape) -> true
    ;   nonvar(Statement), Statement = [Head|Args], atom(Head),
        \+ memberchk(Head, ['And', 'Or', 'Not', 'ImplicationInstanceSample', 'RuleTruth', 'Implication', 'Equivalence',
            'BiImplication', 'ForAll', 'Exists', 'WithPrior', 'Evaluation', 'Similarity',
            'Compute', 'CPU', 'FoldAll', 'FoldAllValue', 'FoldAllTruth', 'MapDist', 'Map2Dist',
            'AverageDist', 'KnownExistential', 'ExistentialResidual', 'GreaterThan', '>',
            'Assuming', 'LikelierThan', 'ExistentialAlternatives']),
        maplist(argument_shape, Args, ArgShapes),
        Shape = [Head|ArgShapes] ).

argument_shape(Arg, Shape) :-
    (   ground(Arg) -> true
    ;   Shape = Arg ).

% The hypothetical context a key lies in, 'MAIN' for the main context (or one
% left open); a fold scoped to a context lies in it. Only an Assuming query's
% contexts are query-local: an implication's contexts hold the derivation of a
% main-context belief and stay. Fields are read without binding anything, so
% a key is not copied.
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

% The last rule application of a proof, its premise proofs still references:
% a stored proof's own step, any other proof itself. Read by every merge and
% fold step, so one clause lookup instead of a collected match.
'sk-step-proof'(Proof, Step) :-
    ( nonvar(Proof), Proof = ['proof-ref', Pid], user:'&proof'(Pid, Value, _, _) -> Stored = Value ; Stored = Proof ),
    ( nonvar(Stored), Stored = ['fact-source',_,Source] -> Step = Source
    ; nonvar(Stored), Stored = ['zero-likelihood',Source] -> Step = Source
    ; nonvar(Stored), Stored = ['unsettled-summary',_,Source] -> 'sk-step-proof'(Source, Step)
    ; Step = Stored ).

'proof-zero-likelihood?'(Proof, Zero) :-
    ( proof_ref_id(Proof,Pid), user:'&proof'(Pid,Value,_,_) -> Stored=Value ; Stored=Proof ),
    ( nonvar(Stored), Stored=['unsettled-summary',_,Source] -> 'proof-zero-likelihood?'(Source,Zero)
    ; nonvar(Stored), Stored=['zero-likelihood',_] -> Zero=true ; Zero=false ).

% Confidence weakening follows immediate proof references without revisiting
% history. Memoized per immutable proof; collection removes the memo with it.
:- dynamic proof_unsettled_memo/2.
'proof-unsettled-sources'(Proof, Sources) :-
    ( proof_ref_id(Proof, Pid)
    -> ( proof_unsettled_memo(Pid, Known) -> Sources=Known
       ; user:'&proof'(Pid, Stored, _, _), 'proof-unsettled-sources'(Stored, Sources),
         assertz(proof_unsettled_memo(Pid, Sources)) )
    ; findall(Source,
        ( sub_term(Child, Proof), nonvar(Child),
          ( Child=['unsettled-summary',Source,_], number(Source)
          ; proof_ref_id(Child, Id), 'proof-unsettled-sources'(['proof-ref',Id],Nested), member(Source,Nested) ) ),
        All), sort(All, Sources) ).

% A retained ordinary view can seed the lazy representative channel only
% when none of its premise keys combined several views. Otherwise replay that
% row with representative premises rather than relabelling the union proof.
:- dynamic proof_representative_memo/2.
'proof-representative?'(Proof, Single) :-
    ( proof_ref_id(Proof, Pid)
    -> ( proof_representative_memo(Pid, Known) -> Single=Known
       ; user:'&proof'(Pid, Stored, _, _), 'proof-representative?'(Stored, Single),
         assertz(proof_representative_memo(Pid, Single)) )
    ; ( sub_term(Child,Proof), nonvar(Child),
        ( Child=[Tag|_], nonvar(Tag), memberchk(Tag,['factored-revision','merge/revision',combination,'class-mixture'])
        ; proof_ref_id(Child,Id), 'proof-representative?'(['proof-ref',Id],false) ) )
    -> Single=false
    ; Single=true ).

% Pure row classification stays opaque to PeTTa's CPU argument specialization.
% A reference cannot certify an endpoint without a Bayes update. Unknown goal
% heads/functions remain eligible; this test never binds the stored template.
'sk-row-has-bayes?'(Hash, Key, Rhash, Has) :-
    ( user:'&sk_row'(Hash, Stored, Rhash, ['sk-row', _, _, Premises, _]), Stored =@= Key,
      member(Premise, Premises),
      ( var(Premise)
      ; Premise=[Tag, Fun|_], (var(Tag) ; Tag=='CPU', (var(Fun) ; Fun=='CTVBayesFormula')) )
    -> Has=true ; Has=false ).

% A hard fact read as a completion's given sibling carries no dependence
% between that context and another update. Keep the full signed source set;
% the MeTTa consumer checks the facts' current certainty in their exact scope.
% Each immutable reference's context is computed once from its immediate
% children. The memo follows the proof store's collector, like its rule memo.
:- dynamic proof_given_memo/2.

'proof-given-evidence'(Proof, ['ev-set', Set]) :-
    proof_given_evidence(Proof, Set).

proof_given_evidence(Proof, Set) :-
    (   proof_ref_id(Proof, Pid)
    ->  (   proof_given_memo(Pid, Known) -> Set = Known
        ;   user:'&proof'(Pid, Stored, _, _), proof_given_evidence(Stored, Set),
            assertz(proof_given_memo(Pid, Set)) )
    ;   nonvar(Proof), Proof = [FactTag, _, _], FactTag == 'fact-source' -> Set = 0
    ;   nonvar(Proof), Proof = [NegTag, Inner], NegTag == negated
    ->  proof_given_evidence(Inner, InnerSet),
        'evidence-negated'(['ev-set', InnerSet], ['ev-set', Set])
    ;   nonvar(Proof), Proof = [Head, Compound], nonvar(Head), Head = [Completion | _],
        Completion == 'antecedent-completion', nonvar(Compound), Compound = [Conjunction | Witnesses],
        Conjunction == conjunction
    ->  append(Siblings, [_Observation], Witnesses),
        'proof-term-evidence'('proof-walk-in-kb', [conjunction | Siblings], ['ev-set', Given]),
        proof_given_children(Proof, Nested), ev_union(Given, Nested, Set)
    ;   is_list(Proof) -> proof_given_children(Proof, Set)
    ;   Set = 0 ),
    refs_gc_touch_set(Set).

proof_given_children([], 0).
proof_given_children([Child | Rest], Set) :-
    proof_given_evidence(Child, ChildSet), proof_given_children(Rest, RestSet),
    ev_union(ChildSet, RestSet, Set).

% Different result keys can intern the same proof under different ids. Compare
% the proof DAG without its result metadata or constructing an expanded tree.
% Repeated reference pairs are visited once; variables are never unified.
'same-proof?'(A, B, Same) :-
    empty_nb_set(Seen),
    ( same_proof_terms(A, B, Seen) -> Same = true ; Same = false ).

same_proof_terms(A, B, Seen) :-
    (   A == B -> true
    ;   proof_ref_id(A, I), proof_ref_id(B, J)
    ->  (   add_nb_set(I-J, Seen, true)
        ->  user:'&proof'(I, AP, AE, _), user:'&proof'(J, BP, BE, _), AE == BE,
            \+ opaque_proof_step(AP), \+ opaque_proof_step(BP),
            same_proof_terms(AP, BP, Seen)
        ;   true )
    ;   proof_ref_id(A, I)
    ->  user:'&proof'(I, AP, _, _), same_proof_terms(AP, B, Seen)
    ;   proof_ref_id(B, J)
    ->  user:'&proof'(J, BP, _, _), same_proof_terms(A, BP, Seen)
    ;   nonvar(A), nonvar(B), A = [AH|AT], B = [BH|BT],
        same_proof_terms(AH, BH, Seen), same_proof_terms(AT, BT, Seen)
    ).

proof_ref_id(Proof, Id) :-
    is_list(Proof), Proof = [Head, Id], Head == 'proof-ref', integer(Id).

% cpu omits the computation's arguments (a fold's population, for example).
% Distinct stored computations therefore retain their reference identity.
opaque_proof_step(Step) :-
    ( Step == cpu -> true ; is_list(Step), member(Cell, Step), Cell == cpu ), !.

% Hash sets (exclusion lists, unifier sets) are SWI ordered sets of key
% hashes, so union and membership are linear merges over short lists.
'hash-set'(Hashes, Set) :- sort(Hashes, Set).
'hash-union'(Left, Right, Set) :- ord_union(Left, Right, Set).
'hash-subset?'(Left, Right, Result) :- ( ord_subset(Left, Right) -> Result = true ; Result = false ).
'hash-intersection'(Left, Right, Both) :- ord_intersection(Left, Right, Both).

% A value's dependency set is an interned node id, so a value stays one
% integer however long the derivation behind it (docs/metta/
% dependency_tracking_design.md). 0 is the empty set; a key is a leaf; a union
% is a node over its operands' ids, interned by that sorted list. Nodes never
% change, so an id names one set forever. Each node keeps a bitmask of its
% keys' hashes, the OR of its children's, so a membership walk skips every
% child whose mask lacks the key's bit.
:- dynamic deps_leaf/2, deps_node/4, deps_size_memo/2, deps_cut/2.

% A frozen key's views stand for its summary (forgetting.metta): a node cut
% to another is walked as that one, so what a value read before the key was
% frozen depends on the key's window, not its whole past.
'deps-cut!'(Ids, Replacement, true) :-
    forall(( member(Id, Ids), deps_node(Id, _, _, _), \+ deps_cut(Id, _), Id \== Replacement ),
           assertz(deps_cut(Id, Replacement))).
% Drops every dependency node no live value reaches. Roots are the sets the
% stores hold; marking follows cuts; a dropped key leaf is interned anew when
% a key is read again.
'deps-gc!'(Roots, true) :-
    empty_nb_set(Live),
    forall(member(Root, Roots), deps_mark(Root, Live)),
    size_nb_set(Live, Kept), flag(deps_gc_kept, _, Kept),
    length(Roots, Read), flag(deps_gc_roots, _, Read),
    flag(deps_next_id, Next, Next), flag(deps_gc_next, _, Next),
    forall(( member(Head, [deps_node(Id, _, _, _), deps_cut(Id, _), deps_size_memo(Id, _), deps_leaf(Id, _)]),
             clause(Head, true, Ref), \+ add_nb_set(Id, Live, false) ), erase(Ref)).
% A collection is due once more ids were interned since the last one than it
% kept and roots it read (at least 4096), so its cost, a walk of the stores
% that hold the roots and of the ids, stays proportional to what was interned.
'deps-gc-due?'(Result) :-
    flag(deps_next_id, Next, Next), flag(deps_gc_next, Last, Last), flag(deps_gc_kept, Kept, Kept),
    flag(deps_gc_roots, Read, Read),
    (   Next - Last > max(Kept + Read, 4096) -> Result = true ; Result = false ).

% Stored proofs and evidence sets nothing refers to are collected in cycles
% spread over queries (docs/metta/evidence_sets.md, "Collection"). A cycle
% keeps what the stores reached when it started and everything created since:
% it scans the holder columns, follows each marked proof to the proofs and
% evidence sets it holds, then sweeps the proof store, the memoized unions
% and the evidence sets, unions first: a union kept while its result is gone
% would hand the erased set to a later query. A slice does a bounded number
% of these units, so a
% query pays for a share of a collection, never for the whole store. Two
% barriers keep a reachable value from being lost meanwhile: a holder row
% removed while marking runs is scanned as it goes, and an interned evidence
% set found again is marked until the cycle ends. Stored proofs are found
% only through references, so one nothing reached cannot be reached again.

% The spaces whose rows can hold a proof reference or an evidence set, their
% arity, and the columns that can. A fact stored in &kb with a referenced
% proof is held by &sk_forward_stored (a forward run's copy) or by
% &materialized_facts as well.
refs_holder('&sk_latest', 3, [3]).
refs_holder('&sk_view', 4, [4]).
refs_holder('&sk_representative', 6, [6]).
refs_holder('&sk_summary_reference', 7, [6, 7]).
refs_holder('&sk_branch', 6, [6]).
refs_holder('&sk_merged', 5, [4]).
refs_holder('&sk_forward_taken', 3, [3]).
refs_holder('&sk_forward_stored', 5, [3, 4]).
refs_holder('&sk_summary', 5, [3, 4]).
refs_holder('&materialized_facts', 6, [5, 6]).
refs_holder('&forward_aggregate_observation', 6, [3]).
refs_holder('&combination_pending', 4, [4]).
refs_holder('&query_proofs', 1, [1]).
refs_holder(context_entry, 5, [4]).
refs_holder(context_hidden, 5, [4]).
refs_holder(context_propagated, 4, [4]).

:- dynamic refs_gc_proof/1, refs_gc_set/1, refs_gc_grey/1, refs_gc_rule/1, refs_gc_rule_grey/1.

% The cycle's phase is idle, roots(Holders), mark, or sweep(Stores); its
% limits are the first proof id and the first evidence set id it did not see
% exist; its work is the clause references of the store being scanned or
% swept, the next one to take in flag refs_gc_next.
refs_gc_active :- nb_current(refs_gc_phase, Phase), Phase \== idle.

% A collection is due once the garbage expected among the proofs, or proof
% words, stored since the last one exceeds what it kept and the holder rows it
% scanned (at least 4096). The garbage expected is the share of them the last
% cycle collected (all before the first), at least 1/16, so garbage stays
% bounded by the live store while a store that keeps nearly all it holds is
% not scanned again and again. Exact-fold proofs grow with their members, so
% counting only proofs retained large histories. A cycle's work is those rows
% and proofs, so each stored proof pays a constant share of it however long
% the history: holder rows grow with the keys, one per decision in Pong,
% while the proofs kept need not.
refs_gc_due :-
    (   refs_gc_active -> true
    ;   'search-id-value'(proof_id, Next), flag(refs_gc_last, Last, Last), flag(refs_gc_kept, Kept, Kept),
        flag(refs_gc_rows, Rows, Rows),
        flag(withdraw_epoch, Epoch, Epoch), flag(refs_gc_retired_last, RetiredLast, RetiredLast),
        flag(refs_gc_words, Words, Words), flag(refs_gc_words_last, LastWords, LastWords),
        flag(refs_gc_words_kept, KeptWords, KeptWords),
        flag(refs_gc_retained, Retained, Retained), flag(refs_gc_words_retained, RetainedWords, RetainedWords),
        ( (Next - Last) * max(1 - Retained, 0.0625) > max(Kept + Rows, 4096)
        ; (Words - LastWords) * max(1 - RetainedWords, 0.0625) > max(KeptWords + Rows, 4096)
        ; Epoch - RetiredLast > 512 ) ).

% One slice, starting a cycle when one is due. Its units grow with the proofs
% stored, their size and rules retired since the last slice, so a cycle ends before as many again are
% stored, and a query that stores none pays a small constant.
'stored-refs-gc-step!'(true) :-
    'search-id-value'(proof_id, Next), flag(refs_gc_seen, Seen, Next),
    flag(withdraw_epoch, Epoch, Epoch), flag(refs_gc_retire_seen, RetiredSeen, Epoch),
    flag(refs_gc_words, Words, Words), flag(refs_gc_words_seen, SeenWords, Words),
    (   refs_gc_due
    ->  ( refs_gc_active -> true ; refs_gc_start ),
        Units is 512 + 8 * (max(0, Next - Seen) + max(0, Epoch - RetiredSeen) + max(0, Words - SeenWords) // 32),
        refs_gc_run(Units)
    ;   true ).

% A whole collection now: the running cycle is finished, then one that starts
% now collects everything nothing reaches.
'stored-refs-gc!'(true) :-
    ( refs_gc_active -> refs_gc_run(inf) ; true ),
    refs_gc_start, refs_gc_run(inf).

refs_gc_start :-
    flag(refs_gc_words, Words, Words), nb_setval(refs_gc_word_limit, Words),
    flag(refs_gc_marked_words, _, 0),
    'search-id-value'(proof_id, ProofLimit), flag(ev_next_set, Sets, Sets), SetLimit is Sets + 1,
    nb_setval(refs_gc_limits, limits(ProofLimit, SetLimit)),
    retractall(refs_gc_proof(_)), retractall(refs_gc_set(_)), retractall(refs_gc_grey(_)),
    retractall(refs_gc_rule(_)), retractall(refs_gc_rule_grey(_)),
    flag(rule_set_next, Rules, Rules), RuleLimit is Rules + 1, nb_setval(refs_gc_rule_limit, RuleLimit),
    flag(withdraw_epoch, Epoch, Epoch), nb_setval(refs_gc_retire_floor, Epoch),
    nb_setval(refs_gc_retire_epoch, Epoch),
    findall(holder(Head, Columns),
            ( refs_holder(Space, Arity, Columns), current_predicate(user:Space/Arity), functor(Head, Space, Arity) ),
            Holders),
    forall(member(holder(Head, Columns), Holders), prolog_listen(user:Head, refs_gc_removed(Columns))),
    aggregate_all(sum(N), ( member(holder(Head, _), Holders), predicate_property(user:Head, number_of_clauses(N)) ), Rows),
    flag(refs_gc_rows, _, Rows),
    nb_setval(refs_gc_holders, Holders),
    nb_setval(refs_gc_phase, roots(Holders)),
    refs_gc_take(none).

refs_gc_removed(Columns, retract, Ref) :- !,
    (   clause(Head, true, Ref) -> refs_gc_mark_columns(Columns, Head) ; true ).
refs_gc_removed(_, _, _).

refs_gc_mark_columns(Columns, Row) :-
    forall(member(Column, Columns), ( arg(Column, Row, Value), refs_gc_mark_term(Value) )).

refs_gc_mark_term(Term) :-
    forall(( sub_term(Sub, Term), nonvar(Sub), Sub = [Tag, Id], atom(Tag), integer(Id) ), refs_gc_mark(Tag, Id)).

refs_gc_mark('proof-ref', Pid) :- !,
    nb_getval(refs_gc_limits, limits(ProofLimit, _)),
    (   Pid < ProofLimit, \+ refs_gc_proof(Pid) -> assertz(refs_gc_proof(Pid)), assertz(refs_gc_grey(Pid)) ; true ).
refs_gc_mark('ev-set', Set) :- !, refs_gc_mark_set(Set).
refs_gc_mark(_, _).

refs_gc_mark_set(Set) :-
    nb_getval(refs_gc_limits, limits(_, SetLimit)),
    (   Set > 0, Set < SetLimit, \+ refs_gc_set(Set) -> assertz(refs_gc_set(Set)) ; true ).

% An evidence set found again by its entries or a memoized union.
refs_gc_touch_set(Set) :- ( refs_gc_active -> refs_gc_mark_set(Set) ; true ).

% The work of the next store: its clause references, taken in order.
refs_gc_take(Refs) :-
    (   Refs == none -> Work = none ; Work =.. [refs|Refs] ),
    nb_setval(refs_gc_work, Work), flag(refs_gc_next, _, 1).

refs_gc_run(Units) :-
    (   ( Units == 0 ; \+ refs_gc_active ) -> true
    ;   nb_getval(refs_gc_phase, Phase), refs_gc_units(Phase, Units, Left), refs_gc_run(Left) ).

% Units of each phase: a holder row scanned, a marked proof followed, a stored
% proof, set or memoized union swept.
refs_gc_units(roots([]), Units, Units) :- nb_setval(refs_gc_phase, mark).
refs_gc_units(roots([holder(Head, Columns)|Rest]), Units, Left) :-
    refs_gc_through(roots(Rest), Head, Units, Left, Ref,
        ( clause(Head, true, Ref) -> refs_gc_mark_columns(Columns, Head) ; true )).
refs_gc_units(mark, Units, Left) :-
    (   refs_gc_grey(_) -> refs_gc_follow_loop(Units, Left)
    ;   nb_getval(refs_gc_holders, Holders),
        forall(member(holder(Head, Columns), Holders), prolog_unlisten(user:Head, refs_gc_removed(Columns))),
        nb_setval(refs_gc_phase, sweep([proofs, unions, sets])), Left = Units ).
refs_gc_units(sweep([]), Units, Units) :- nb_setval(refs_gc_phase, rule_memos).
refs_gc_units(sweep([Store|Stores]), Units, Left) :-
    nb_getval(refs_gc_limits, limits(ProofLimit, SetLimit)),
    refs_gc_store(Store, Head),
    refs_gc_through(sweep(Stores), Head, Units, Left, Ref,
        ( clause(Head, true, Ref), refs_gc_dead(Store, Head, ProofLimit, SetLimit) -> refs_gc_erase(Store, Head, Ref) ; true )).

% Provenance collection shares the same unit budget as proof/evidence GC.
% Each root, tree node and swept entry consumes one unit. Proof cache entries
% and summary users leave in refs_gc_erase, not in a second orphan-proof scan.
refs_gc_units(rule_memos, Units, Left) :-
    refs_gc_through(rule_roots([proofs, summaries, stores]), summary_rules(Hash, Epoch, _), Units, Left, Ref,
        ( clause(summary_rules(Hash, Epoch, _), true, Ref),
          \+ user:'&sk_summary'(Hash, _, [_, _, [forgotten, Hash, Epoch], _], _, _),
          \+ summary_ref(Hash, Epoch, _) -> erase(Ref) ; true )).
refs_gc_units(rule_roots([]), Units, Units) :- nb_setval(refs_gc_phase, rule_mark).
refs_gc_units(rule_roots([Store|Stores]), Units, Left) :-
    rule_gc_root(Store, Head, Set),
    refs_gc_through(rule_roots(Stores), Head, Units, Left, Ref,
        ( clause(Head, true, Ref) -> refs_gc_mark_rule(Set) ; true )).
refs_gc_units(rule_mark, Units, Left) :-
    ( refs_gc_follow_rules(Units, Left) -> true
    ; nb_setval(refs_gc_phase, rule_sweep([sets, unions, retirements, marks])), Left = Units ).
refs_gc_units(rule_sweep([]), Units, Units) :- refs_gc_finish.
refs_gc_units(rule_sweep([Store|Stores]), Units, Left) :-
    ( refs_gc_follow_rules(Units, Left) -> true
    ; rule_gc_store(Store, Head),
      refs_gc_through(rule_sweep(Stores), Head, Units, Left, Ref,
          ( clause(Head, true, Ref), rule_gc_dead(Store, Head) -> rule_gc_erase(Store, Head, Ref) ; true )) ).

rule_gc_root(proofs, proof_rules_memo(_, Set), Set).
rule_gc_root(summaries, summary_rules(_, _, Set), Set).
rule_gc_root(stores, stored_rules(_, _, _, _, Set), Set).
rule_gc_store(sets, rule_set(_, _, _, _, _)).
rule_gc_store(unions, rule_union(_, _, _)).
rule_gc_store(retirements, retired_epoch(_, _)).
rule_gc_store(marks, refs_gc_rule(_)).

refs_gc_mark_rule(0) :- !.
refs_gc_mark_rule(Set) :-
    ( refs_gc_rule(Set) -> true
    ; assertz(refs_gc_rule(Set)), assertz(refs_gc_rule_grey(Set)) ).
refs_gc_follow_rules(Units, Left) :-
    refs_gc_rule_grey(_), !,
    ( Units == 0 -> Left = 0
    ; retract(refs_gc_rule_grey(Set)),
      ( rule_set(Set, Kind, Children, _, Count)
      -> forall(member(Child, Children), refs_gc_mark_rule(Child)),
         % A long-unread set can use its leaves instead of older events.
         ( Kind = leaf(_) -> true
         ; ( proof_live_memo(Set, Checked, Live) -> true ; Checked = 0, Live = true ),
           ( Live == false -> true
           ; nb_getval(refs_gc_retire_epoch, Epoch), Floor is max(Checked, Epoch - Count),
             nb_getval(refs_gc_retire_floor, Previous), NextFloor is min(Previous, Floor),
             nb_setval(refs_gc_retire_floor, NextFloor) ))
      ; true ),
      ( Units == inf -> Next = inf ; Next is Units - 1 ),
      ( refs_gc_follow_rules(Next, Left) -> true ; Left = Next ) ).

rule_gc_live(Set) :-
    ( Set =:= 0 ; nb_getval(refs_gc_rule_limit, Limit), Set >= Limit ; refs_gc_rule(Set) ), !.
rule_gc_dead(marks, refs_gc_rule(_)).
rule_gc_dead(sets, rule_set(Set, _, _, _, _)) :- \+ rule_gc_live(Set).
rule_gc_dead(unions, rule_union(A, B, Set)) :-
    \+ ( rule_gc_live(A), rule_gc_live(B), rule_gc_live(Set) ).
% An event for an identity in no surviving set is unnecessary too. A later
% cold proof builds its leaf with current indexed retirement status. Such
% holes need not force existing sets to use a full leaf check.
rule_gc_dead(retirements, retired_epoch(Epoch, Rule)) :-
    ( nb_getval(refs_gc_retire_floor, Floor), Epoch =< Floor ; \+ rule_leaf(Rule, _) ).
rule_gc_erase(sets, rule_set(Set, Kind, Children, _, _), Ref) :- !,
    erase(Ref),
    forall(member(Child, Children), retractall(rule_parent(Child, Set))),
    ( Kind = leaf(Rule) -> retractall(rule_leaf(Rule, Set))
    ; Kind = branch(Bit, _), Children = [Left, Right], term_hash([Bit, Left, Right], Hash),
      retractall(rule_branch(Hash, Bit, Left, Right, Set)) ),
    retractall(proof_live_memo(Set, _, _)).
rule_gc_erase(retirements, retired_epoch(Epoch, _), Ref) :- !,
    erase(Ref), nb_getval(refs_gc_retire_floor, Floor),
    ( Epoch =< Floor -> flag(rule_retired_floor, Old, max(Old, Epoch)) ; true ).
rule_gc_erase(_, _, Ref) :- erase(Ref).

% Takes a store's clause references when its turn comes, runs Goal on at most
% Units of them, and moves on to the phase after once all were taken.
refs_gc_through(After, Head, Units, Left, Ref, Goal) :-
    nb_getval(refs_gc_work, Work0),
    (   Work0 == none -> findall(R, clause(Head, true, R), Refs), refs_gc_take(Refs), nb_getval(refs_gc_work, Work)
    ;   Work = Work0 ),
    functor(Work, _, Size), flag(refs_gc_next, First, First),
    (   Units == inf -> Last = Size ; Last is min(Size, First + Units - 1) ),
    forall(between(First, Last, I), ( arg(I, Work, Ref), \+ \+ Goal )),
    Next is Last + 1, flag(refs_gc_next, _, Next),
    (   Units == inf -> Left = inf ; Left is Units - (Last - First + 1) ),
    (   Next > Size -> nb_setval(refs_gc_phase, After), refs_gc_take(none) ; true ).

% Follows marked proofs to what they hold.
refs_gc_follow_loop(Units, Left) :-
    (   Units == 0 -> Left = 0
    ;   retract(refs_gc_grey(Pid))
    ->  (   user:'&proof'(Pid, Stored, Leaves, _)
        ->  term_size(Stored, Size), flag(refs_gc_marked_words, Marked, Marked + Size),
            refs_gc_mark_term(Stored), refs_gc_mark_term(Leaves),
            ( proof_given_memo(Pid, Given) -> refs_gc_mark_set(Given) ; true )
        ;   true ),
        (   Units == inf -> Next = inf ; Next is Units - 1 ),
        refs_gc_follow_loop(Next, Left)
    ;   Left = Units ).

refs_gc_store(proofs, user:'&proof'(_, _, _, _)).
refs_gc_store(sets, ev_set(_, _, _, _, _)).
refs_gc_store(unions, ev_union_memo(_, _)).

refs_gc_dead(proofs, user:'&proof'(Pid, _, _, _), ProofLimit, _) :- Pid < ProofLimit, \+ refs_gc_proof(Pid).
refs_gc_dead(sets, ev_set(Set, _, _, _, _), _, SetLimit) :- \+ refs_gc_live_set(Set, SetLimit).
refs_gc_dead(unions, ev_union_memo(Key, Union), _, SetLimit) :-
    Left is Key >> 32, Right is Key /\ 0xffffffff,
    \+ ( refs_gc_live_set(Left, SetLimit), refs_gc_live_set(Right, SetLimit), refs_gc_live_set(Union, SetLimit) ).

refs_gc_live_set(Set, SetLimit) :- ( Set =:= 0 ; Set >= SetLimit ; refs_gc_set(Set) ), !.

refs_gc_erase(proofs, user:'&proof'(Pid, _, _, _), Ref) :- !,
    erase(Ref), retractall(user:'&proof_fact'(Pid, _, _)), retractall(proof_rules_memo(Pid, _)),
    retractall(proof_given_memo(Pid, _)),
    retractall(proof_unsettled_memo(Pid, _)),
    retractall(proof_representative_memo(Pid, _)),
    forget_summary_user(Pid).
refs_gc_erase(sets, ev_set(Set, _, _, _, _), Ref) :- !,
    erase(Ref), retractall(ev_given_memo(Set, _)), retractall(ev_inherited_memo(Set, _)).
refs_gc_erase(_, _, Ref) :- erase(Ref).

% The share kept of what existed when the cycle started: what the last cycle
% kept and what was stored between the two.
refs_gc_finish :-
    flag(refs_gc_words, Words, Words), flag(refs_gc_words_last, LastWords, Words),
    flag(refs_gc_marked_words, MarkedWords, MarkedWords), nb_getval(refs_gc_word_limit, LimitWords),
    flag(refs_gc_words_kept, KeptWords, MarkedWords + Words - LimitWords),
    flag(refs_gc_words_retained, _, min(1, MarkedWords / max(1, KeptWords + LimitWords - LastWords))),
    nb_getval(refs_gc_retire_epoch, Epoch), flag(refs_gc_retired_last, _, Epoch),
    aggregate_all(count, refs_gc_proof(_), Marked),
    nb_getval(refs_gc_limits, limits(ProofLimit, _)), 'search-id-value'(proof_id, Next),
    flag(refs_gc_last, Last, Next), flag(refs_gc_kept, KeptBefore, Marked + Next - ProofLimit),
    flag(refs_gc_retained, _, min(1, Marked / max(1, KeptBefore + ProofLimit - Last))),
    retractall(refs_gc_proof(_)), retractall(refs_gc_set(_)),
    nb_setval(refs_gc_phase, idle), refs_gc_take(none).

deps_mark(0, _) :- !.
deps_mark(Id, Live) :-
    (   add_nb_set(Id, Live, true)
    ->  (   deps_cut(Id, Replacement) -> deps_mark(Replacement, Live)
        ;   deps_node(Id, _, Children, _) -> forall(member(Child, Children), deps_mark(Child, Live))
        ;   true )
    ;   true ).

deps_children(Id, Children) :-
    (   deps_cut(Id, Replacement) -> Children = [Replacement] ; deps_node(Id, _, Children, _) ).
% The mask width trades stored bytes per node against collisions in dominance
% (docs/metta/dependency_tracking_design.md, "Mask width").
deps_mask_bits(4096).

deps_bit(Hash, Bit) :- deps_mask_bits(W), Bit is 1 << (Hash mod W).

deps_mask(0, 0) :- !.
deps_mask(Id, Mask) :- deps_leaf(Id, Hash), !, deps_bit(Hash, Mask).
deps_mask(Id, Mask) :- deps_node(Id, _, _, Mask).

'deps-key'(Hash, Id) :-
    (   deps_leaf(Id, Hash) -> true
    ;   flag(deps_next_id, Last, Last + 1), Id is Last + 1,
        assertz(deps_leaf(Id, Hash)) ).

'deps-union'(Left, Right, Id) :- 'deps-join'([Left, Right], Id).

'deps-join'(Ids, Id) :-
    sort(Ids, Sorted), exclude(==(0), Sorted, Children),
    (   Children == [] -> Id = 0
    ;   Children = [Only] -> Id = Only
    ;   term_hash(Children, Key),
        (   deps_node(Id, Key, Children, _) -> true
        ;   flag(deps_next_id, Last, Last + 1), Id is Last + 1,
            foldl([Child, Acc0, Acc]>>(deps_mask(Child, M), Acc is Acc0 \/ M), Children, 0, Mask),
            assertz(deps_node(Id, Key, Children, Mask)) ) ).

% Whether a set holds a key: the walk enters only children whose mask has the
% key's bit and visits each node once.
deps_has(Id, Hash) :- deps_bit(Hash, Bit), empty_nb_set(Seen), deps_has(Id, Hash, Bit, Seen).
deps_has(Id, Hash, Bit, Seen) :-
    deps_mask(Id, Mask), Mask /\ Bit =\= 0,
    (   deps_leaf(Id, Leaf) -> Leaf =:= Hash
    ;   add_nb_set(Id, Seen, true),
        deps_children(Id, Children),
        member(Child, Children), deps_has(Child, Hash, Bit, Seen), ! ).

'deps-has?'(Id, Hash, Result) :- ( deps_has(Id, Hash) -> Result = true ; Result = false ).
'deps-excluded'(Hashes, Id, Excluded) :- include(deps_has(Id), Hashes, Excluded).

% Whether a set holds any of the keys: one walk, entering only children whose
% mask has one of the keys' bits.
'deps-meet?'(Hashes, Id, Result) :-
    foldl([Hash, Bits0, Bits]>>(deps_bit(Hash, Bit), Bits is Bits0 \/ Bit), Hashes, 0, Bits),
    empty_nb_set(Seen),
    (   deps_meets(Id, Hashes, Bits, Seen) -> Result = true ; Result = false ).
deps_meets(Id, Hashes, Bits, Seen) :-
    deps_mask(Id, Mask), Mask /\ Bits =\= 0,
    (   deps_leaf(Id, Leaf) -> memberchk(Leaf, Hashes)
    ;   add_nb_set(Id, Seen, true),
        deps_children(Id, Children),
        member(Child, Children), deps_meets(Child, Hashes, Bits, Seen), ! ).

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
    ->  (   deps_leaf(Id, Hash) -> add_nb_set(Hash, Keys, _)
        ;   deps_children(Id, Children), forall(member(Child, Children), deps_collect(Child, Nodes, Keys)) )
    ;   true ).
deps_covered(Id, Nodes, Keys, Seen) :-
    (   add_nb_set(Id, Nodes, false) -> true
    ;   add_nb_set(Id, Seen, false) -> true
    ;   add_nb_set(Id, Seen, true),
        (   deps_leaf(Id, Hash) -> add_nb_set(Hash, Keys, false)
        ;   deps_children(Id, Children), forall(member(Child, Children), deps_covered(Child, Nodes, Keys, Seen)) ) ).

% The number of keys in a set; a node's count never changes once computed.
'deps-size'(0, 0) :- !.
'deps-size'(Id, Size) :-
    (   deps_cut(Id, Replacement) -> 'deps-size'(Replacement, Size)
    ;   deps_leaf(Id, _) -> Size = 1
    ;   deps_size_memo(Id, Size) -> true
    ;   empty_nb_set(Nodes), empty_nb_set(Keys), deps_collect(Id, Nodes, Keys),
        size_nb_set(Keys, Size), assertz(deps_size_memo(Id, Size)) ).

% The keys near the top of at least two of the sets: each set's keys within
% two levels of its node (a value's own key and the keys of the premises its
% row read), held by two of the sets. Entangled premises of a row
% (sk-entangle) are found so by masked lookups, without collecting the sets.
'deps-entangled'(Ids, Hashes) :-
    foldl(deps_near_child(2), Ids, [], Near0), sort(Near0, Near),
    include(deps_held_twice(Ids), Near, Hashes).
deps_near(0, _, []) :- !.
deps_near(Id, _, [Hash]) :- deps_leaf(Id, Hash), !.
deps_near(Id, Depth, Near) :-
    Depth > 0, deps_children(Id, Children), !,
    Next is Depth - 1,
    foldl(deps_near_child(Next), Children, [], Near).
deps_near(_, _, []).
deps_near_child(Depth, Child, Acc0, Acc) :- deps_near(Child, Depth, Found), append(Found, Acc0, Acc).
deps_held_twice(Ids, Hash) :-
    aggregate_all(count, (member(Id, Ids), deps_has(Id, Hash)), Count), Count >= 2.

% One-step filtering: the keys within two levels of at least two of the sets
% (near in both), the one-step horizon of a key merge's views.
'deps-near-shared'(Ids, Hashes) :-
    maplist([Id, Near]>>(deps_near(Id, 2, Near0), sort(Near0, Near)), Ids, Nears),
    append(Nears, All), msort(All, Sorted), clumped(Sorted, Runs),
    findall(Hash, (member(Hash-Count, Runs), Count > 1), Hashes).

% The keys two sets both hold, in order.
'deps-shared'(A, B, Hashes) :-
    empty_nb_set(NodesA), empty_nb_set(KeysA), deps_collect(A, NodesA, KeysA),
    empty_nb_set(NodesB), empty_nb_set(KeysB), deps_collect(B, NodesB, KeysB),
    nb_set_to_list(KeysB, InB), include(deps_in(KeysA), InB, Hashes).
deps_in(Keys, Hash) :- add_nb_set(Hash, Keys, false).

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
:- dynamic ev_entry/3, ev_set/5, ev_union_memo/2.

% A fact's entries are also indexed by the hash of its stored proof, the name
% a row's leaf premise reads it by (evidence-condition), and a condition's by
% the fact it is given.
ev_entry_id(Entry, Id) :-
    'index-hash'(Entry, Hash),
    (   ev_entry(Id, Hash, Stored), Stored =@= Entry -> true
    ;   flag(ev_next_entry, Last, Last + 1), Id is Last + 1,
        assertz(ev_entry(Id, Hash, Entry)), ev_index_entry(Entry, Id) ).
ev_index_entry([Tag, _, Proof, _], Id) :- memberchk(Tag, ['fact-ev', 'not-fact-ev']), !,
    'index-hash'(Proof, ProofHash), assertz(ev_proof_entry(ProofHash, Id)).
ev_index_entry(['given-ev', K, P, T], Id) :- !, ev_entry_id(['fact-ev', K, P, T], Fact), assertz(ev_given_fact(Id, Fact)).
ev_index_entry(['not-ev', ['given-ev', K, P, T]], Id) :- !, ev_entry_id(['not-fact-ev', K, P, T], Fact), assertz(ev_given_fact(Id, Fact)).
ev_index_entry(_, _).
:- dynamic ev_proof_entry/2, ev_given_fact/2.

ev_order(0, []) :- !.
ev_order(Set, Ids) :- ev_set(Set, _, Order, _, _), string_codes(Order, Ids).
ev_sorted(0, []) :- !.
ev_sorted(Set, Ids) :- ev_set(Set, _, _, Sorted, _), string_codes(Sorted, Ids).
ev_excluded(0, []) :- !.
ev_excluded(Set, Excluded) :- ev_set(Set, _, _, _, Excluded).

ev_intern([], _, _, 0) :- !.
ev_intern(Ids, Sorted, Excluded, Set) :-
    string_codes(Order, Ids), term_hash(Order, Hash),
    (   ev_set(Set, Hash, Order, _, _) -> refs_gc_touch_set(Set)
    ;   flag(ev_next_set, Last, Last + 1), Set is Last + 1, string_codes(SortedString, Sorted),
        assertz(ev_set(Set, Hash, Order, SortedString, Excluded)) ).

% The set of a list of ids without repeats, in its order.
ev_of_ids(Ids, Set) :-
    findall(Rule, ( member(Id, Ids), ev_entry(Id, _, ['rule-excluded', Kb, Name]), ev_entry_id(['rule-ev', Kb, Name], Rule) ), Rules),
    sort(Ids, Sorted), sort(Rules, Excluded), ev_intern(Ids, Sorted, Excluded, Set).

ev_in_assoc(Assoc, Id) :- get_assoc(Id, Assoc, _).

% The ids of a list that are in a sorted list, in the list's order.
ev_keep(Ids, Sorted, Kept) :-
    pairs_keys_values(Pairs, Sorted, Sorted), ord_list_to_assoc(Pairs, Assoc), include(ev_in_assoc(Assoc), Ids, Kept).

ev_fact_entry(Id, Entry) :-
    ev_entry(Id, _, Entry), \+ Entry = ['rule-ev', _, _], \+ Entry = ['rule-excluded', _, _].

'evidence-set'(Entries, ['ev-set', Set]) :-
    maplist(ev_entry_id, Entries, Repeated), list_to_set(Repeated, Ids), ev_of_ids(Ids, Set).

'evidence-entries'(['ev-set', Set], Entries) :- ev_order(Set, Ids), maplist([Id, Entry]>>ev_entry(Id, _, Entry), Ids, Entries).

% A's entries followed by the entries of B that A lacks.
'evidence-union'(['ev-set', A], ['ev-set', B], ['ev-set', C]) :- ev_union(A, B, C).
ev_union(A, B, C) :-
    (   B == 0 -> C = A
    ;   A == 0 -> C = B
    ;   A == B -> C = A
    ;   Key is A << 32 \/ B, ev_union_memo(Key, Memo) -> refs_gc_touch_set(Memo), C = Memo
    ;   ev_sorted(A, SortedA), ev_sorted(B, SortedB),
        ord_subtract(SortedB, SortedA, New),
        (   New == [] -> C = A
        ;   ev_order(A, IdsA), ev_order(B, IdsB),
            ( New == SortedB -> Added = IdsB ; ev_keep(IdsB, New, Added) ),
            append(IdsA, Added, Ids), ord_union(SortedA, New, Sorted),
            ev_excluded(A, ExcludedA), ev_excluded(B, ExcludedB), ord_union(ExcludedA, ExcludedB, Excluded),
            ev_intern(Ids, Sorted, Excluded, C) ),
        Key is A << 32 \/ B, assertz(ev_union_memo(Key, C)) ).

% The union of the sets in order, interned once. Materializing every prefix
% retained quadratic evidence history when an exact fold ran repeatedly.
'evidence-join'(Sets, ['ev-set', Set]) :-
    findall(Id, (member(['ev-set', S], Sets), ev_order(S, Ids), member(Id, Ids)), Repeated),
    list_to_set(Repeated, Ids), ev_of_ids(Ids, Set).

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
% other entry is wrapped. Negation cancels a previous wrapper; rule source
% identity and exclusions do not depend on the polarity of the conclusion.
'evidence-negated'(['ev-set', A], ['ev-set', C]) :-
    ev_order(A, Ids), maplist(ev_negated_id, Ids, Negated), ev_of_ids(Negated, C).
ev_negated_id(Id, Negated) :-
    ev_entry(Id, _, Entry),
    (   Entry = ['fact-ev', Kb, Proof, Type] -> Not = ['not-fact-ev', Kb, Proof, Type]
    ;   Entry = ['not-fact-ev', Kb, Proof, Type] -> Not = ['fact-ev', Kb, Proof, Type]
    ;   Entry = ['not-ev', Inner] -> Not = Inner
    ;   Entry = ['rule-ev', _, _] -> Not = Entry
    ;   Entry = ['rule-excluded', _, _] -> Not = Entry
    ;   Not = ['not-ev', Entry] ),
    ev_entry_id(Not, Negated).

% The entries other than rules that A shares with B, in reverse of A's order.
'evidence-shared-facts'(['ev-set', A], ['ev-set', B], Entries) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ord_intersection(SortedA, SortedB, Shared),
    (   Shared == [] -> Entries = []
    ;   ev_order(A, IdsA), ev_keep(IdsA, Shared, Kept), reverse(Kept, Reversed),
        convlist(ev_fact_entry, Reversed, Entries) ).

% Physical source lists are local to one sample. Fold summaries are counters,
% never evidence sets: changing one member costs one indexed delta per source.
% A physical outcome has one lookup key regardless of proof name or polarity.
% Support handles have their own namespace: bookkeeping must not change
% evidence-entry allocation and deterministic proof traversal. MAIN identities
% persist; query-local identities leave with their worlds unless MAIN uses them.
support_identity_id(Term,Id) :-
    'index-hash'(Term,Hash),
    ( support_identity(Id,Hash,Stored), Stored =@= Term
    -> ( context_active(_) -> true ; retractall(support_identity_owner(Id)) )
    ; flag(support_next_identity,Last,Last+1), Id is Last+1,
      assertz(support_identity(Id,Hash,Term)),
      ( context_active(_) -> assertz(support_identity_owner(Id)) ; true ) ).

likelihood_source_key(Source, Key) :-
    support_identity(Source,Key,['sk-key',_,_]).

'source-list-union'(['source-list',A],['source-list',B],['source-list',Sources]) :-
    append(A,B,All), sort(All,Sources).

'observation-keys'(['source-list',Sources],Keys) :- convlist(likelihood_source_key,Sources,Keys).

'observation-sources'(Evidence, ['source-list',Sources]) :-
    ( Evidence=['ev-set',_] -> 'evidence-entries'(Evidence,Entries) ; Entries=[Evidence] ),
    convlist(likelihood_observation_source, Entries, Physical), sort(Physical,Sources).

'update-likelihood-support!'(Fold, Member, ['source-list',Sources], Pos, Neg, true) :-
    'index-hash'(Fold,FoldHash), 'index-hash'(Member,MemberHash),
    ( '&ctx_sk_sample_support'(MemberHash,FoldHash,StoredFold,Stored,['source-list',Old],OP,ON), StoredFold =@= Fold, Stored =@= Member -> true
    ; Old=[], OP=0, ON=0, StoredFold=Fold, Stored=Member ),
    ( Sources==Old, Pos=:=OP, Neg=:=ON -> true
    ; likelihood_replace_sources(Fold,Old,OP,ON,Sources,Pos,Neg),
      'remove-variant-row!'('&sk_sample_support',[MemberHash,FoldHash,StoredFold,Stored,['source-list',Old],OP,ON],_),
      ( Pos=:=0, Neg=:=0 -> true
      ; 'context-add!'('&sk_sample_support',[MemberHash,FoldHash,Fold,Member,['source-list',Sources],Pos,Neg],_) ) ).

% Ordered member-local lists yield deltas; retained sources are not rewritten.
likelihood_replace_sources(Fold,Old,OP,ON,Sources,Pos,Neg) :-
    'index-hash'(Fold,H), 'likelihood-support-counts'(Fold,C0),
    ord_subtract(Old,Sources,Removed), ord_subtract(Sources,Old,Added),
    DP is -OP, DN is -ON,
    foldl(likelihood_source_delta(Fold,H,DP,DN),Removed,C0,C1),
    foldl(likelihood_source_delta(Fold,H,Pos,Neg),Added,C1,C2),
    CP is Pos-OP, CN is Neg-ON,
    ( CP=:=0, CN=:=0 -> C=C2
    ; ord_intersection(Old,Sources,Shared),
      foldl(likelihood_source_delta(Fold,H,CP,CN),Shared,C2,C) ),
    C=['support-counts',D,A,B,RawBad,Both],
    ( Old==[], OP+ON>0 -> OldMissing=1 ; OldMissing=0 ),
    ( Sources==[], Pos+Neg>0 -> Missing=1 ; Missing=0 ),
    Bad is RawBad+Missing-OldMissing,
    Counts=['support-counts',D,A,B,Bad,Both],
    ( Counts==C0 -> true
    ; 'remove-variant-row!'('&sk_branch_support',[H,Fold,C0],_),
      ( Counts==['support-counts',0,0,0,0,0] -> true
      ; 'context-add!'('&sk_branch_support',[H,Fold,Counts],_) ) ).

% Reverse edges are unique per read hash and observation. Hash collisions
% remain conservative even when one of two colliding physical sources leaves.
'update-aggregate-sources!'(Id,Key,['source-list',Old],OP,['source-list',Sources],Pos,true) :-
    ( Sources==Old, Pos=:=OP -> true
    ; support_identity_id(['aggregate-reader',Id,Key],Reader),
      convlist(likelihood_source_key,Old,OldKeys0), sort(OldKeys0,OldKeys),
      convlist(likelihood_source_key,Sources,NewKeys0), sort(NewKeys0,NewKeys),
      ord_subtract(OldKeys,NewKeys,Removed), ord_subtract(NewKeys,OldKeys,Added),
      forall(member(K,Removed),'context-remove!'('&forward_aggregate_read',[K,Id,Reader],_)),
      forall(member(K,Added),'context-add!'('&forward_aggregate_read',[K,Id,Reader],_)),
      likelihood_replace_sources(['aggregate-support',Id],Old,OP,0,Sources,Pos,0) ).

% Keep the full reader once; reverse edges retain only scalar identities.
% Edge enumeration preserves arrival order and keeps the aggregate indexed.
'aggregate-readers'(Id,Read,Keys) :-
    findall(Key,('&ctx_forward_aggregate_read'(Read,Id,Reader),
                 support_identity(Reader,_,['aggregate-reader',Id,Key])),Keys).

'likelihood-support-counts'(Fold,Counts) :-
    'index-hash'(Fold,H),
    ( '&ctx_sk_branch_support'(H,Stored,Found), Stored =@= Fold -> Counts=Found
    ; Counts=['support-counts',0,0,0,0,0] ).

% Distinct total, positive, negative, repeated/unverified, cross-branch overlap.
likelihood_counts(Entry,P,N,[D,A,B,Bad,Both]) :-
    D is min(1,P+N), A is min(1,P), B is min(1,N), Both is A*B,
    ( (P>1 ; N>1 ; Entry=='unverified-observation',D>0) -> Bad=1 ; Bad=0 ).

likelihood_source_delta(Fold,H,DP,DN,Entry,['support-counts'|Before],['support-counts'|After]) :-
    'index-hash'([Fold,Entry],Key),
    ( '&ctx_sk_sample_source'(Key,H,Stored,Entry,OP,ON), Stored =@= Fold -> true
    ; OP=0, ON=0, Stored=Fold ),
    P is OP+DP, N is ON+DN,
    'remove-variant-row!'('&sk_sample_source',[Key,H,Stored,Entry,OP,ON],_),
    ( P=:=0, N=:=0 -> true
    ; % MAIN can retain a source list computed while an assumption was active.
      ( context_active(_) -> true ; retractall(support_identity_owner(Entry)) ),
      'context-add!'('&sk_sample_source',[Key,H,Fold,Entry,P,N],_) ),
    likelihood_counts(Entry,OP,ON,Was), likelihood_counts(Entry,P,N,Now),
    maplist(likelihood_count_delta,Before,Was,Now,After).
likelihood_count_delta(T,Old,New,Result) :- Result is T+New-Old.

% Enumerate only an estimate's own sources when it is explicitly excluded.
% This list is not interned and never contains the marginal's population.
'likelihood-sources'(Fold,Branch,['source-list',Sources]) :-
    'index-hash'(Fold,H),
    findall(Source,('&ctx_sk_sample_source'(_,H,Stored,Source,P,N),Stored =@= Fold,
        (Branch=:=0 -> true ; Branch>0 -> P>0 ; N>0)),Sources).

'likelihood-support-admissible?'(Fold,['source-list',Excluded],Result) :-
    'likelihood-support-counts'(Fold,['support-counts',Distinct,_,_,Bad,_]),
    ( Bad=:=0 -> sort(Excluded,Unique),
      aggregate_all(count,(member(Source,Unique),'index-hash'([Fold,Source],Key),
          '&ctx_sk_sample_source'(Key,_,Stored,Source,_,_),Stored =@= Fold),Hits),
      ( Distinct>Hits -> Result=true ; Result=false )
    ; Result=false ).

likelihood_observation_source(['rule-ev'|_], _) :- !, fail.
likelihood_observation_source(['rule-excluded'|_], _) :- !, fail.
likelihood_observation_source(['not-ev',Entry], Source) :- !,
    likelihood_observation_source(Entry,Source).
likelihood_observation_source([Tag,Scope,_Proof,Type], Source) :-
    memberchk(Tag,['fact-ev','not-fact-ev','given-ev']), !,
    ( ground(Scope-Type) -> support_identity_id(['sk-key',Type,Scope],Source)
    ; Source='unverified-observation' ).
likelihood_observation_source(_, 'unverified-observation').

% Whether B uses a rule that one of A's excluded-rule entries names.
'evidence-excludes?'(['ev-set', A], ['ev-set', B], Result) :-
    ev_excluded(A, Excluded),
    (   Excluded \== [], ev_sorted(B, SortedB), ord_intersect(Excluded, SortedB) -> Result = true ; Result = false ).

% Proof metadata keeps the permanent owner identity, alongside its negation
% bit. Shared transitive provenance is interned only when a retirement check
% or an exposed KB copy needs it. Epoch-zero backward reads allocate no sets;
% publishing a KB copy registers it once against its shared source set.
% A canonical Patricia tree shares branches and bounds membership by one path.
:- dynamic retired_rule/2, retired_epoch/2, proof_live_memo/3,
           summary_rules/3, rule_set/5, rule_leaf/2, rule_branch/5, rule_union/3, rule_parent/2,
           proof_rules_memo/2, summary_user/3, stored_rules/5, stored_set/2, stored_token/2, summary_ref/3.

'withdraw-rule!'(Id, true) :-
    ( retired_rule(Id, _) -> true
    ; flag(withdraw_epoch, E, E + 1), Epoch is E + 1,
      assertz(retired_rule(Id, Epoch)), assertz(retired_epoch(Epoch, Id)) ).

'rule-live?'(Id, Live) :- ( retired_rule(Id, _) -> Live = false ; Live = true ).

rule_set_leaf(Rule, Set) :-
    ( rule_leaf(Rule, Set) -> true
    ; deps_bit(Rule, Mask), rule_set_new(leaf(Rule), [], Mask, Set), assertz(rule_leaf(Rule, Set)) ).

rule_sets_join(Sets, Set) :-
    sort(Sets, Sorted), exclude(==(0), Sorted, Children),
    foldl(rule_sets_union, Children, 0, Set),
    ( refs_gc_active -> refs_gc_mark_rule(Set) ; true ).

rule_sets_union(0, B, B) :- !.
rule_sets_union(A, 0, A) :- !.
rule_sets_union(A, A, A) :- !.
rule_sets_union(A, B, Set) :-
    First is min(A, B), Second is max(A, B),
    ( rule_union(First, Second, Set) -> true
    ; rule_set(A, AK, AC, _, _), rule_set(B, BK, BC, _, _),
      ( AK = leaf(AR) -> AB = -1 ; AK = branch(AB, AR) ),
      ( BK = leaf(BR) -> BB = -1 ; BK = branch(BB, BR) ),
      ( AR =:= BR -> Split = -1 ; Split is msb(AR xor BR) ),
      Rep is min(AR, BR),
      ( Split > max(AB, BB)
      -> ( AR < BR -> Left = A, Right = B ; Left = B, Right = A ),
         rule_set_branch(Split, Rep, Left, Right, Set)
      ; AB =:= BB
      -> AC = [AL, AT], BC = [BL, BT],
         rule_sets_union(AL, BL, Left), rule_sets_union(AT, BT, Right),
         rule_set_branch(AB, Rep, Left, Right, Set)
      ; AB > BB
      -> AC = [AL, AT],
         ( BR /\ (1 << AB) =:= 0 -> rule_sets_union(AL, B, Left), Right = AT
         ; Left = AL, rule_sets_union(AT, B, Right) ),
         rule_set_branch(AB, Rep, Left, Right, Set)
      ; BC = [BL, BT],
        ( AR /\ (1 << BB) =:= 0 -> rule_sets_union(A, BL, Left), Right = BT
        ; Left = BL, rule_sets_union(A, BT, Right) ),
        rule_set_branch(BB, Rep, Left, Right, Set) ),
      assertz(rule_union(First, Second, Set)) ).

rule_set_branch(Bit, Rep, Left, Right, Set) :-
    term_hash([Bit, Left, Right], Hash),
    ( rule_branch(Hash, Bit, Left, Right, Set) -> true
    ; rule_set(Left, _, _, LM, _), rule_set(Right, _, _, RM, _), Mask is LM \/ RM,
      rule_set_new(branch(Bit, Rep), [Left, Right], Mask, Set),
      assertz(rule_branch(Hash, Bit, Left, Right, Set)) ).

% A distinct node inherits current child liveness; its first read never
% replays the historical retirement log or copies transitive rule lists.
rule_set_new(Kind, Children, Mask, Set) :-
    flag(rule_set_next, N, N + 1), Set is N + 1,
    ( Kind = leaf(_) -> Count = 1
    ; Children = [Left, Right], rule_set(Left, _, _, _, LC), rule_set(Right, _, _, _, RC), Count is LC + RC ),
    assertz(rule_set(Set, Kind, Children, Mask, Count)), flag(withdraw_epoch, Epoch, Epoch),
    forall(member(Child, Children), assertz(rule_parent(Child, Set))),
    ( Epoch =:= 0 -> true
    ; ( ( Kind = leaf(Rule) -> \+ retired_rule(Rule, _) ; forall(member(Child, Children), rule_set_live(Child, Epoch)) )
        -> Live = true ; Live = false ),
      assertz(proof_live_memo(Set, Epoch, Live)) ).

proof_rule_set(Proof, Set) :-
    findall(S, ( sub_term(Ref, Proof), nonvar(Ref), proof_source_rules(Ref, S) ), Children),
    rule_sets_join(Children, Set).

% Resolve each immutable proof DAG node once, sharing the canonical source
% sets. The cache is absent until provenance is actually read, and collected
% with its proof. This never enumerates other proofs or the retirement log.
proof_rules(Pid, Set) :-
    ( proof_rules_memo(Pid, Set) -> ( refs_gc_active -> refs_gc_mark_rule(Set) ; true )
    ; user:'&proof'(Pid, Proof, _, Flags), Code is Flags >> 1,
      proof_rule_set(Proof, Sources),
      ( Code > 0 -> Owner is Code - 1, rule_set_leaf(Owner, Own), rule_sets_join([Sources, Own], Set) ; Set = Sources ),
      assertz(proof_rules_memo(Pid, Set)), forget_summary_user(Pid) ).
'proof-ref-negated?'(Pid, Negated) :-
    ( user:'&proof'(Pid, _, _, Flags), Flags /\ 1 =:= 1 -> Negated = true ; Negated = false ).

% Publication receives the identity from the exact row being evaluated.
% Folds have identity -1; temporary query rows cannot be withdrawn. Encoding
% the owner as id+1 reserves metadata zero without losing real rule id zero.
'record-view-rule!'(Pid, Rule, Proof, Owner) :-
    term_size(Proof, Words), flag(refs_gc_words, Before, Before + Words),
    ( Rule >= 0, Rule < 1000000000 -> Owner is Rule + 1 ; Owner = 0 ),
    % A frozen summary's rows are gone. Its source identities must survive
    % physical retirement until this proof has captured its transitive set.
    forall(( sub_term(Ref, Proof), nonvar(Ref), Ref = [Tag, H, E], Tag == forgotten,
             integer(H), integer(E) ), (assertz(summary_user(Pid, H, E)), assertz(summary_ref(H, E, Pid)))).

forget_summary_user(Pid) :-
    forall(retract(summary_user(Pid, Hash, Epoch)), retractall(summary_ref(Hash, Epoch, Pid))).

'record-summary-rules!'(Hash, Epoch, Proof, true) :-
    proof_rule_set(Proof, Set), assertz(summary_rules(Hash, Epoch, Set)).

proof_source_rules([Tag, Pid], Set) :- Tag == 'proof-ref', integer(Pid), proof_rules(Pid, Set).
proof_source_rules([Tag, Hash, Epoch], Set) :- Tag == forgotten, integer(Hash), integer(Epoch), summary_rules(Hash, Epoch, Set).

'proof-live?'(Proof, Live) :-
    flag(withdraw_epoch, Epoch, Epoch),
    ( Epoch =:= 0 -> Live = true
    ; forall(( sub_term(Ref, Proof), nonvar(Ref), proof_source_rules(Ref, Set) ),
             rule_set_live(Set, Epoch)) -> Live = true
    ; Live = false ).

rule_set_live(0, _) :- !.
rule_set_live(Set, Epoch) :-
    ( proof_live_memo(Set, Checked, Live) -> true ; Checked = 0, Live = true ),
    Live == true,
    ( Checked =:= Epoch -> true
    ; rule_set(Set, Kind, _, _, Count), flag(rule_retired_floor, Floor, Floor),
      ( Kind = leaf(Owner)
      -> ( retired_rule(Owner, _) -> Next = false ; Next = true )
      ; ( Epoch - Checked > Count ; Checked < Floor )
      -> ( rule_set_leaves_live(Set) -> Next = true ; Next = false )
      ; First is Checked + 1,
        ( between(First, Epoch, E), retired_epoch(E, Rule), rule_set_has(Set, Rule) -> Next = false ; Next = true ) ),
      retractall(proof_live_memo(Set, _, _)), assertz(proof_live_memo(Set, Epoch, Next)), Next == true ).

rule_set_leaves_live(Set) :- forall(rule_set_rule(Set, Rule), \+ retired_rule(Rule, _)).
rule_set_rule(Set, Rule) :-
    rule_set(Set, Kind, Children, _, _),
    ( Kind = leaf(Rule) -> true ; member(Child, Children), rule_set_rule(Child, Rule) ).

rule_set_has(Set, Rule) :- rule_leaf(Rule, _), deps_bit(Rule, Bit), rule_set_has(Set, Rule, Bit).
rule_set_has(Set, Rule, Bit) :-
    rule_set(Set, Kind, Children, Mask, _), Mask /\ Bit =\= 0,
    ( Kind = leaf(Rule) -> true
    ; Kind = branch(Branch, Rep), Rule >> (Branch + 1) =:= Rep >> (Branch + 1),
      Children = [Left, Right],
      ( Rule /\ (1 << Branch) =:= 0 -> rule_set_has(Left, Rule, Bit) ; rule_set_has(Right, Rule, Bit) ) ).

% Each physical KB copy registers once against its canonical set. Shared
% child-to-parent edges lead from a retired rule's leaf to affected copies;
% publication/removal never enumerates that set's contributing rules.
'record-stored-rules!'(Kind, Hash, Key, Proof, true) :-
    'forget-stored-rules!'(Kind, Hash, Key, true), proof_rule_set(Proof, Set),
    flag(stored_rules_next, N, N + 1), Token is N + 1,
    assertz(stored_rules(Hash, Kind, Key, Token, Set), Ref), assertz(stored_token(Token, Ref)),
    assertz(stored_set(Set, Token)).

'forget-stored-rules!'(Kind, Hash, Key, true) :-
    forall(( stored_rules(Hash, Kind, Stored, Token, Set), Stored =@= Key ),
           ( retractall(stored_set(Set, Token)), stored_token(Token, Ref), erase(Ref), retractall(stored_token(Token, _)) )).

'withdrawn-stores!'(Ids, Stores) :-
    findall(Leaf, ( member(Id, Ids), rule_leaf(Id, Leaf) ), Leaves), empty_nb_set(Seen),
    findall(Token, ( rule_set_ancestor(Leaves, Seen, Set), stored_set(Set, Token) ), Tokens0), sort(Tokens0, Tokens),
    findall(['retired-store', Kind, Hash, Key],
            ( member(Token, Tokens), stored_token(Token, Ref),
              clause(stored_rules(Hash, Kind, Key, Token, _), true, Ref),
              'forget-stored-rules!'(Kind, Hash, Key, true) ), Stores).

% The Patricia nodes form a shared DAG across canonical sets. Visit each
% affected node once, including ancestors without a published copy of their
% own, so diamonds and multiple retired sources do not repeat subtree work.
rule_set_ancestor([Set|Rest], Seen, Ancestor) :-
    add_nb_set(Set, Seen, New),
    ( New == true
    -> ( Ancestor = Set
       ; findall(Parent, rule_parent(Set, Parent), Parents), append(Parents, Rest, Next),
         rule_set_ancestor(Next, Seen, Ancestor) )
    ; rule_set_ancestor(Rest, Seen, Ancestor) ).


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
% that a derivation exists (docs/metta/complete_predicates.md). An
% antecedent completion reads the other parts of the antecedent at their
% population prior when nothing else gives them a value (sk-start-prior!), so
% a part that no rule application concludes and that is not complete
% supports it.
:- dynamic rule_dormancy/3.

'rule-dormant?'(Id, Dormant) :-
    (   rule_dormancy(Id, Dormant, _) -> true
    ;   dormancy_analysis(Id, Dormant, Heads), assertz(rule_dormancy(Id, Dormant, Heads)) ).

dormancy_analysis(Id, Dormant, Heads) :-
    nb_setval(dormancy_budget, 2000), nb_setval(dormancy_heads, []),
    (   dormancy_row(rules('runtime-rule-row', Id, [Type, Ctx, Proof|_], Premises)),
        \+ ( 'derivation-proof?'(Type, Proof, true), dormancy_complete(Type, Ctx) ),
        member([PType, PCtx, _, _], Premises), PType \== 'CPU',
        \+ dormancy_premise_supported(Proof, PType, PCtx, Type-Ctx, [], 8)
    ->  Dormant = true
    ;   Dormant = false ),
    nb_getval(dormancy_heads, Heads0), sort(Heads0, Heads).

dormancy_supported(Type, Ctx, Forbidden, Path, Depth) :-
    nb_getval(dormancy_budget, Budget),
    (   Budget =< 0 -> true
    ;   Budget1 is Budget - 1, nb_setval(dormancy_budget, Budget1),
        (   Type-Ctx == Forbidden -> fail
        ;   dormancy_complete(Type, Ctx) -> true
        ;   member(Seen, Path), Seen =@= Type-Ctx -> fail
        ;   Depth =< 0 -> true
        ;   \+ dormancy_judged(Type, Ctx) -> true
        ;   dormancy_fact(Type, Ctx) -> true
        ;   \+ dormancy_row(rules('runtime-rule-row', _, [Type, Ctx|_], _)) -> true
        ;   dormancy_note_head(Type),
            Depth1 is Depth - 1,
            dormancy_row(rules('runtime-rule-row', _, [Type, Ctx, Proof|_], Premises)),
            (   memberchk(['CPU', 'SettlesFormula'|_], Premises) -> \+ \+ dormancy_settles(Premises)
            ;   forall(( member([PType, PCtx, _, _], Premises), PType \== 'CPU' ),
                       dormancy_premise_supported(Proof, PType, PCtx, Forbidden, [Type-Ctx|Path], Depth1)) ) ) ).

dormancy_premise_supported(Proof, Type, Ctx, Forbidden, Path, Depth) :-
    (   Type-Ctx \== Forbidden, Proof = [['antecedent-completion'|_]|_], \+ dormancy_derived(Type, Ctx) -> true
    ;   dormancy_supported(Type, Ctx, Forbidden, Path, Depth) ).

dormancy_derived(Type, Ctx) :-
    (   dormancy_complete(Type, Ctx) -> true
    ;   \+ \+ ( dormancy_row(rules('runtime-rule-row', _, [Type, Ctx, Proof|_], _)),
                 ( Proof = [by|_] ; Proof = [negated, [by|_]] ) ) ).

% A complete statement always has a value once its search settles: its rule
% applications read closed, and with none it is unfounded, false
% (docs/metta/complete_predicates.md). So it supports a reader even when its
% only derivations run through a loop back to it: a loop disjunct read closed
% is false, and the rest of its antecedent decides.
% A connective with a complete part is complete too (`complete-statement?`).
dormancy_complete(Type, [Kb|_]) :- 'complete-part?'(Kb, false, Type, true).

% A settled rule reads only a part whose certain stored fact settles its
% compound (docs/metta/connective_settling.md), so it supports its conclusion
% only through such a fact: the part's formulas run on the fact up to the
% settling check. A refined rule's truth goal is supported.
dormancy_settles([['CPU', Fun, Args, Res]|Rest]) :- !,
    append(Args, [Out], CallArgs), G =.. [Fun|CallArgs],
    catch(G, _, fail), Out = Res, ( Fun == 'SettlesFormula' -> true ; dormancy_settles(Rest) ).
dormancy_settles([[Type, _, _, _]|Rest]) :-
    nonvar(Type), Type = [Head|_], Head == 'RuleTruth', !, dormancy_settles(Rest).
dormancy_settles([[Type, Ctx, Proof, Tv]|Rest]) :-
    dormancy_row('&kb'(Type, Ctx, Proof, Tv)), Tv = ['STV', _, C], number(C), C >= 1.0,
    dormancy_settles(Rest).

% A statement no fact and no rule speaks of yet is an input still to come,
% not one only the rule's conclusion supports, so it counts as supported.
% The search judges only what it fully sees: user predicates in the main
% context (or one a rule leaves open). An assumption context supplies its own
% premises, and the chainer's own vocabulary has support the search does not
% model: rules installed when a node expands (implications), member folds and
% samples. Anything else counts as supported.
dormancy_judged(Type, [_, Context|_]) :-
    ( var(Context) ; Context == 'MAIN' ),
    \+ ( Type = [Head|_], memberchk(Head, ['ImplicationInstanceSample', 'RuleTruth', 'Implication', 'Equivalence', 'And', 'Or', 'Not',
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

statement_head(T, H) :-
    (   var(T) -> H = '$var'
    ;   T = [H0|_] -> ( var(H0) -> H = '$var' ; H = H0 )
    ;   H = T ).

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
prune_answer_instances([], []) :- !.
prune_answer_instances([Answer], [Kept]) :- !, copy_term(Answer, Kept).
prune_answer_instances(Answers, Kept) :-
    numbered_answers(Answers, 1, Numbered),
    empty_assoc(Empty),
    reverse(Numbered, Reversed),
    foldl(index_answer_proof, Reversed, Empty-Empty, Index),
    findall(Answer, (member(Position-Answer, Numbered),
                     \+ answer_instance(Index, Position, Answer)), Kept).

numbered_answers([], _, []).
numbered_answers([Answer|Answers], Position, [Position-Answer|Numbered]) :-
    Next is Position + 1,
    numbered_answers(Answers, Next, Numbered).

index_answer_proof(Position-Answer, Before-Memo, After-NextMemo) :-
    (   nonvar(Answer), Answer = [_, _, Proof, _],
        proof_identity_hash(Proof, Memo, NextMemo, Hash)
    ->  (get_assoc(Hash, Before, Previous) -> true ; Previous = []),
        put_assoc(Hash, Before, [Position-Answer|Previous], After)
    ;   After = Before, NextMemo = Memo
    ).

% Hash the semantic proof DAG once per reference, without expanding it. An
% open leaf has no identity hash and passes through; collisions are checked
% by the same nonbinding proof comparison used by merging.
proof_identity_hash(Proof, Memo, NextMemo, Hash) :-
    (   proof_ref_id(Proof, Id)
    ->  (   get_assoc(Id, Memo, Hash) -> NextMemo = Memo
        ;   user:'&proof'(Id, Stored, _, _),
            (   opaque_proof_step(Stored)
            ->  term_hash(opaque(Id), Hash), ExpandedMemo = Memo
            ;   proof_identity_hash(Stored, Memo, ExpandedMemo, Hash) ),
            put_assoc(Id, ExpandedMemo, Hash, NextMemo) )
    ;   nonvar(Proof), Proof = [Head|Tail]
    ->  proof_identity_hash(Head, Memo, HeadMemo, HeadHash),
        proof_identity_hash(Tail, HeadMemo, NextMemo, TailHash),
        term_hash(node(HeadHash, TailHash), Hash)
    ;   ground(Proof), term_hash(leaf(Proof), Hash), NextMemo = Memo
    ).

answer_instance(Index-Memo, Position, Answer) :-
    nonvar(Answer), Answer = [_, _, Proof, _],
    proof_identity_hash(Proof, Memo, _, Hash),
    get_assoc(Hash, Index, Candidates),
    member(Other-General, Candidates),
    Other \== Position,
    '=alpha'(Answer, General, false),
    copy_term(Answer, [SpecificType, _, _, _]),
    copy_term(General, [GeneralType, _, GeneralProof, _]),
    subsumes_term(GeneralType, SpecificType),
    (   Other < Position
    ->  true
    ;   \+ subsumes_term(SpecificType, GeneralType)
    ),
    empty_nb_set(Seen), same_proof_terms(Proof, GeneralProof, Seen),
    !.

% What building a skeleton row or node of a term costs, in rows of the row
% allowance or steps of the budget: one, and one more for each 400 words of the
% term, about what storing, hashing and comparing that much of a term takes
% beyond a row's fixed cost (ONA reasoningbench_num: a row of a 9,000-word
% statement took 25 ms, one of a few words about 1 ms).
'term-cost'(Term, Cost) :- term_size(Term, Size), Cost is 1 + Size // 400.

% Whether node Specific is an instance of node General whose statement binds
% one of General's variables to a compound term: the term a recursive rule
% grows, as (Num (succ $x)) grows from (Num $x), and not a mere specialization
% such as (Reward op1 $t) of (Reward $op $t). Tested on attribute-free copies,
% so typed variables run no constraints.
'grows-from?'(General, Specific, Result) :-
    copy_term_nat(General, G),
    copy_term_nat(Specific, S),
    (   subsumes_term(G, S), G = [GT|_], S = [ST|_], term_size(ST, SS), term_size(GT, GS), SS > GS
    ->  Result = true ; Result = false ).

% Links the key a join read to the premise the join bound (sk-read-step):
% each variable of General, at a position where Instance, an instance of it,
% still has a variable, is unified with that variable, unless the join bound
% two variables of General to one of Instance. Where the join bound Instance
% further, General keeps its own variable, so the row reads the key that
% answered it, and evaluation still binds Instance's open variables through it.
'link-open-variables'(General, Instance, true) :-
    (   ground(General)
    ->  true
    ;   open_variable_pairs(General, Instance, Pairs, []),
        include(one_to_one(Pairs), Pairs, Linked),
        maplist(link_pair, Linked)
    ).

open_variable_pairs(General, Instance, Pairs, Tail) :-
    (   var(General)
    ->  (   var(Instance) -> Pairs = [General-Instance|Tail] ; Pairs = Tail )
    ;   compound(General), compound(Instance)
    ->  General =.. [_|GeneralArgs],
        Instance =.. [_|InstanceArgs],
        foldl(open_variable_pairs, GeneralArgs, InstanceArgs, Pairs, Tail)
    ;   Pairs = Tail
    ).

one_to_one(Pairs, General-Instance) :-
    \+ ( member(G-I, Pairs),
          ( G == General, I \== Instance ; I == Instance, G \== General ) ).

link_pair(Variable-Variable).

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
    length(Sorted, Length), Taken is min(Budget, Length),
    length(Strongest, Taken), append(Strongest, Overflow, Sorted), pairs_values(Strongest, Anchors0),
    sort(1, @<, Anchors0, Anchors),
    absorb_overflow_particles(Overflow, Anchors, Merged),
    sort(1, @<, Merged, Ordered),
    maplist([component(_, Value, Weight), [Value, Weight]]>>true, Ordered, Result).

indexed_particle_pairs([], _, []).
indexed_particle_pairs([[Value, Weight]|Rest], Index,
        [key(NegativeWeight, Index)-component(Index, Value, Weight)|Ranked]) :-
    NegativeWeight is -Weight,
    NextIndex is Index + 1,
    indexed_particle_pairs(Rest, NextIndex, Ranked).

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
        (   Best0 = best(BestCost, _, _, _), \+ Cost < BestCost
        ->  Best1 = Best0
        ;   Best1 = best(Cost, AnchorIndex, Mean, MergedWeight) )
    ;   Best1 = Best0
    ),
    closest_particle_anchor(
        Rest, component(_, Value, Weight), Best1, Best).

replace_particle_anchor(
        [component(Index, _, _)|Rest], Index, Value, Weight,
        [component(Index, Value, Weight)|Rest]) :- !.
replace_particle_anchor([Anchor|Rest], Index, Value, Weight,
        [Anchor|Updated]) :-
    replace_particle_anchor(Rest, Index, Value, Weight, Updated).

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

% A counter's value (change-state!), 0 before it is set.
'search-id-value'(Key, Value) :- ( nb_current(Key, Stored) -> Value = Stored ; Value = 0 ).

% The ordinary readers being computed, innermost first. The stack is a
% backtrackable global: a reader pushes a copy of its identity, restores the
% stack it found when it is done, and failure or an exception restores it by
% backtracking. Neither copies the stack.
'sk-push-reader!'(Reader, Readers) :-
    ( nb_current(sk_reading, Stored) -> Readers = Stored ; Readers = [] ),
    copy_term(Reader, Copy),
    b_setval(sk_reading, [Copy|Readers]).
'sk-restore-readers!'(Readers, true) :- b_setval(sk_reading, Readers).
% Each active reader, outermost first.
'sk-active-reader'(Reader) :-
    nb_current(sk_reading, Readers), reverse(Readers, Outermost), member(Reader, Outermost).

% Inference time, process-wide, in seconds: activation, search and evaluation
% of backward queries, and forward runs. A caller splits the wall time of its
% calls into inference and overhead with it; it costs two clock reads a call.
'inference-clock'(Time) :- get_time(Time).
'inference-add!'(Start, true) :-
    get_time(Now),
    flag(pettachainer_inference_seconds, Seconds, Seconds + Now - Start).
inference_seconds(Seconds) :- flag(pettachainer_inference_seconds, Seconds, Seconds).

% Optional query counters sit on backward-search hot paths. Keep their disabled
% check and enabled scalar updates native so diagnostics do not distort normal
% query performance with thousands of MeTTa state or space operations.
query_metrics_enabled(Enabled) :-
    ( nb_current(pettachainer_query_metrics_enabled, Stored) -> Enabled = Stored ; Enabled = false ).
query_metrics_set_enabled(Enabled, Enabled) :- nb_setval(pettachainer_query_metrics_enabled, Enabled).
query_metric_value(Key, Value) :- atom_concat(pettachainer_query_metric_, Key, G), 'search-id-value'(G, Value).
query_metric_set(Key, Value, Value) :-
    ( query_metrics_enabled(true) -> atom_concat(pettachainer_query_metric_, Key, G), nb_setval(G, Value) ; true ).
query_metric_increment(Key, Result) :-
    (   query_metrics_enabled(true)
    ->  query_metric_value(Key, Old), Result is Old + 1,
        atom_concat(pettachainer_query_metric_, Key, G), nb_setval(G, Result)
    ;   Result = 0
    ).

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

% Regimes of one branch, P(B|A) or P(B|not A), of a refined rule's instance
% tally (docs/metta/hypothesis_rules.md, "Regimes"). The branch's rate is
% constant between change points nobody announces, each sample a change with
% the prior probability H, the hazard. Its samples are kept, in arrival order,
% as segments ['regime-segment', Id, W, M], each the sums of its samples'
% outcomes W and masses M: an old regime (once there was a change), the
% current one, and last a candidate, the run of samples since a possible
% change (id 0 while empty). A hypothesis assigns the segments to regimes;
% the branch's evidence is the posterior mixture, over the hypotheses, of the
% newest sample's regime's Beta posterior. With H = 0 there is one regime,
% and one segment holds every sample.

% Log marginal likelihood of weighted Bernoulli sums under Beta(1/2, 1/2).
regime_log_ml(W, M, L) :-
    A is max(W, 0.0) + 0.5, B is max(M - W, 0.0) + 0.5,
    L is lgamma(A) + lgamma(B) - lgamma(A + B) - log(pi).

% A hypothesis: a regime label per segment, as a restricted growth string.
regime_labels([], _, []).
regime_labels([_|Segs], Max, [L|Ls]) :-
    Top is Max + 1, between(0, Top, L), Max1 is max(Max, L),
    regime_labels(Segs, Max1, Ls).

% Its prior: between consecutive segments, no change with 1 - H, or a change
% with H to a new regime or back to an earlier one, each alike.
regime_log_prior(H, [L|Ls], P) :- regime_log_prior(Ls, L, [L], H, 0.0, P).
regime_log_prior([], _, _, _, P, P).
regime_log_prior([L|Ls], Prev, Seen, H, P0, P) :-
    (   L =:= Prev -> P1 is P0 + log(1.0 - H)
    ;   length(Seen, N), P1 is P0 + log(H) - log(N)
    ),
    ( memberchk(L, Seen) -> Seen1 = Seen ; Seen1 = [L|Seen] ),
    regime_log_prior(Ls, L, Seen1, H, P1, P).

regime_block(Segs, Labels, Label, W, M) :- regime_block(Segs, Labels, Label, 0.0, 0.0, W, M).
regime_block([], [], _, W, M, W, M).
regime_block([['regime-segment', _, W1, M1]|Segs], [L|Ls], Label, W0, M0, W, M) :-
    (   L =:= Label -> W2 is W0 + W1, M2 is M0 + M1 ; W2 = W0, M2 = M0 ),
    regime_block(Segs, Ls, Label, W2, M2, W, M).

% Each hypothesis's log posterior (unnormalised), labels, and the sums of the
% newest segment's regime.
regime_hypotheses(H, Segs, Hyps) :-
    findall(LP-Labels-Wc-Mc,
            ( regime_labels(Segs, -1, Labels),
              regime_log_prior(H, Labels, Prior),
              max_list(Labels, Top),
              aggregate_all(sum(L), ( between(0, Top, Label),
                                      regime_block(Segs, Labels, Label, W, M),
                                      regime_log_ml(W, M, L) ), Lik),
              LP is Prior + Lik,
              last(Labels, Cur),
              regime_block(Segs, Labels, Cur, Wc, Mc) ),
            Hyps).

regime_posteriors(Hyps, Posts) :-
    aggregate_all(max(LP), member(LP-_-_-_, Hyps), Max),
    aggregate_all(sum(E), ( member(LP-_-_-_, Hyps), E is exp(LP - Max) ), Z),
    findall(P-Labels-Wc-Mc, ( member(LP-Labels-Wc-Mc, Hyps), P is exp(LP - Max) / Z ), Posts).

regime_empty(['regime-segment', _, _, M]) :- M =< 0.0.

% The branch's evidence: one segment's sums, or the posterior mixture's: its
% strength W / M is the posterior mean of the hypotheses' strengths, its mass
% M the posterior mean of their regimes' masses, the evidence the estimate
% stands on.
'regime-evidence'(H, Segs0, ['BaseRateEvidence', W, M]) :-
    exclude(regime_empty, Segs0, Segs),
    (   Segs = [] -> W = 0.0, M = 0.0
    ;   Segs = [['regime-segment', _, W, M]] -> true
    ;   regime_hypotheses(H, Segs, Hyps),
        regime_posteriors(Hyps, Posts),
        aggregate_all(sum(P), member(P-_-_-_, Posts), Z),
        aggregate_all(sum(P * Wc / Mc), member(P-_-Wc-Mc, Posts), PS),
        aggregate_all(sum(P * Mc), member(P-_-_-Mc, Posts), PM),
        M is PM / Z,
        W is PS / Z * M
    ).

% A tally less one contribution plus another; a mass left by rounding is none.
regime_shift(W, M, OW, OM, NW, NM, W1, M1) :-
    Mass is M - OM + NM,
    (   Mass < 0.000000001 -> W1 = 0.0, M1 = 0.0 ; W1 is W - OW + NW, M1 = Mass ).

% The segment a sample's segment was merged into.
regime_root(Hash, Seg, Root) :-
    (   catch('&ctx_sk_instance_regime'(Hash, Seg, To), error(existence_error(procedure, _), _), fail)
    ->  regime_root(Hash, To, Root)
    ;   Root = Seg
    ).

% A member's sample in one branch, as segment Seg (0: none yet) held Old and
% now holds New. A new sample (the first with mass) joins the candidate; a
% known one is replaced in the segment holding it, if one still does.
% Result: the branch's segments and the member's segment.
'regime-take!'(Hash, H, Id, Segs, Seg, ['BaseRateEvidence', OW, OM], ['BaseRateEvidence', NW, NM], [Segs1, Seg1]) :-
    (   Seg =:= 0
    ->  (   NM =< 0.0 -> Segs1 = Segs, Seg1 = 0
        ;   H =< 0.0
        ->  (   Segs = [['regime-segment', One, W, M]]
            ->  regime_shift(W, M, 0.0, 0.0, NW, NM, W1, M1),
                Segs1 = [['regime-segment', One, W1, M1]], Seg1 = One
            ;   Segs1 = [['regime-segment', Id, NW, NM]], Seg1 = Id
            )
        ;   Segs = [] -> Segs1 = [['regime-segment', Id, NW, NM], ['regime-segment', 0, 0.0, 0.0]], Seg1 = Id
        ;   regime_add(Hash, H, Id, Segs, NW, NM, Segs1, Seg1)
        )
    ;   regime_root(Hash, Seg, Seg1),
        (   select(['regime-segment', Seg1, W, M], Segs, ['regime-segment', Seg1, W1, M1], Segs1)
        ->  regime_shift(W, M, OW, OM, NW, NM, W1, M1)
        ;   Segs1 = Segs
        )
    ).

% The sample joins the candidate, which starts where a change is most probable
% (Page's CUSUM, over two start points): at its first sample, or at the new
% sample when that one alone departs further from the samples before it. A
% candidate whose samples favour the rate before them over one of their own
% (Bayes factor at most 1) was no change: it merges into the current segment
% and a new candidate starts. One the posterior more probably holds a change
% than not becomes the current segment; with an old one already kept, two of
% the three segments merge first (regime_make_room).
regime_add(Hash, H, Id, Segs, W, M, Segs1, Seg1) :-
    append(Front, [Cur0, ['regime-segment', NId0, NW0, NM0]], Segs),
    Empty = ['regime-segment', 0, 0.0, 0.0],
    New = ['regime-segment', Id, W, M],
    (   NM0 =< 0.0 -> Cur = Cur0, Cand = New
    ;   Old = ['regime-segment', NId0, NW0, NM0],
        regime_shift(NW0, NM0, 0.0, 0.0, W, M, NW, NM),
        Run = ['regime-segment', NId0, NW, NM],
        regime_change_lbf(Cur0, Run, LRun),
        Cur0 = ['regime-segment', _, CW, CM],
        BW is CW + NW0, BM is CM + NM0,
        regime_change_lbf(['regime-segment', 0, BW, BM], New, LNew),
        (   LNew > LRun, LNew > 0.0
        ->  regime_merge(Hash, Id, Cur0, Old, Cur, _, _), Cand = New
        ;   Cur = Cur0, Cand = Run
        )
    ),
    Cand = ['regime-segment', NId, _, _],
    (   regime_change_lbf(Cur, Cand, L), L =< 0.0
    ->  regime_merge(Hash, Id, Cur, Cand, Merged, Gone, Keep),
        append(Front, [Merged, Empty], Segs1),
        ( NId == Gone -> Seg1 = Keep ; Seg1 = NId )
    ;   append(Front, [Cur, Cand], Segs2),
        regime_hypotheses(H, Segs2, Hyps),
        regime_posteriors(Hyps, Posts),
        aggregate_all(sum(P), ( member(P-Labels-_-_, Posts), append(_, [LC, LN], Labels), LC =\= LN ), Change),
        Seg1 = NId,
        (   Change > 0.5
        ->  ( Front = [] -> Kept = Segs2 ; regime_make_room(Hash, Id, Segs2, Posts, Kept) ),
            append(Kept, [Empty], Segs1)
        ;   Segs1 = Segs2
        )
    ).

% The log Bayes factor for two segments' having rates of their own over one.
regime_change_lbf(['regime-segment', _, WA, MA], ['regime-segment', _, WB, MB], L) :-
    regime_log_ml(WA, MA, LA), regime_log_ml(WB, MB, LB),
    W is WA + WB, M is MA + MB, regime_log_ml(W, M, LU),
    L is LA + LB - LU.

% Two segments as one, under the larger one's id at the newer one's place; a
% member of the other finds it through &sk_instance_regime, unless the other
% holds only the sample being taken (id Id).
regime_merge(Hash, Id, ['regime-segment', IdA, WA, MA], ['regime-segment', IdB, WB, MB],
             ['regime-segment', Keep, W, M], Gone, Keep) :-
    ( MA >= MB -> Keep = IdA, Gone = IdB ; Keep = IdB, Gone = IdA ),
    W is WA + WB, M is MA + MB,
    ( Gone == Id -> true ; 'context-add!'('&sk_instance_regime',[Hash,Gone,Keep],true) ).

% A new current segment beside an old and the previous one: the pair the
% posterior most probably holds in one regime merges, if more probably than
% not (the old regime with the new one when it returned, so its evidence
% counts at once). Otherwise the older segment least probably in the newest
% one's regime is dropped, and its members' samples no longer count.
regime_make_room(Hash, Id, Segs, Posts, Kept) :-
    findall(Same-I-J,
            ( member(I-J, [1-2, 1-3, 2-3]),
              aggregate_all(sum(P), ( member(P-Labels-_-_, Posts), nth1(I, Labels, L), nth1(J, Labels, L) ), Same) ),
            Pairs),
    max_member(Best-BI-BJ, Pairs),
    (   Best > 0.5
    ->  nth1(BI, Segs, SI), nth1(BJ, Segs, SJ),
        regime_merge(Hash, Id, SI, SJ, Merged, _, _),
        findall(S, ( nth1(N, Segs, S0), N =\= BI, ( N =:= BJ -> S = Merged ; S = S0 ) ), Kept)
    ;   findall(Weight-N,
                ( member(N, [1, 2]),
                  aggregate_all(sum(P), ( member(P-Labels-_-_, Posts), nth1(N, Labels, L), last(Labels, L) ), Weight) ),
                Weights),
        min_member(_-Drop, Weights),
        findall(S, ( nth1(N, Segs, S), N =\= Drop ), Kept)
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
    ;   T = ['fact-source',_,Source] -> proof_ref_counts(Source,C0,C)
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
    ;   T = ['zero-likelihood',Source] -> proof_dag_term(Source,Counts,D0,D,Out)
    ;   T = ['unsettled-summary',_,Source] -> proof_dag_term(Source,Counts,D0,D,Out)
    ;   T = ['fact-source',_,Source] -> proof_dag_term(Source,Counts,D0,D,Out)
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

% Python's call of a chainer function (pettachainer.py): Fn applied to the
% arguments each MeTTa source in Sources reads as, every result collected in
% order, as a runnable `!(Fn Args)` returns them. Arguments that are data,
% which a runnable passes as they are, are passed without compiling one; any
% other argument, such as a nested call or a lambda a runnable evaluates
% first, is compiled as a runnable. As text, a result is printed as MeTTa
% prints it; as terms, an expression arrives through janus as a list and a
% symbol or string as a str, and since janus passes no unbound variable each
% is named as MeTTa prints it.
metta_call(Fn, Sources, Results) :-
    atom_string(Name, Fn),
    foldl(metta_call_source(Name), Sources, Results, []).
metta_call_source(Name, Source, Results, Rest) :-
    format(string(Expression), "(~s)", [Source]),
    sread(Expression, Args),
    (   maplist(metta_data, Args)
    ->  append(Args, [Result], CallArgs),
        Goal =.. [Name|CallArgs],
        findall(Result, Goal, Results, Rest)
    ;   format(string(Code), "!(~w ~s)", [Name, Source]),
        process_metta_string(Code, Own),
        append(Own, Rest, Results)
    ).
% What a runnable passes unevaluated: a variable, a number, symbol or string,
% or an expression of such terms whose head names no function, special form
% or translator rule.
metta_data(Term) :- var(Term), !.
metta_data(Term) :- atomic(Term), !.
metta_data([Head|Args]) :-
    (   atom(Head)
    ->  \+ fun(Head), \+ translator_rule(Head), \+ special_builtin_form(Head, Args, _)
    ;   metta_data(Head)
    ),
    maplist(metta_data, Args).
metta_call_text(Fn, Sources, Texts) :-
    metta_call(Fn, Sources, Results),
    maplist(swrite, Results, Texts).
metta_call_terms(Fn, Sources, Results) :-
    metta_call(Fn, Sources, Results),
    term_variables(Results, Variables),
    foldl([Variable, N0, N]>>(format(atom(Variable), '$_~d', [N0]), N is N0 + 1),
          Variables, 0, _).

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
    maplist(generalize_argument(Subst), Args, General).
generalize_argument(Subst, Arg, General) :-
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

% Functional input relations are immutable value tables. Ground certain-true
% facts assign a key; no other fact or rule may define that relation.
% This is stronger than merely knowing an uncertain most likely value.
:- dynamic functional_predicate/4, functional_value/3, '&kb'/4, '&sk_answer'/3, rules/4.
'set-functional-predicate'(Kb, Head, Arity, Positions, true) :-
    'declared-head!'(Head, true),
    ( atom(Head), integer(Arity), Arity > 1, is_list(Positions),
      Positions \== [], sort(Positions, Positions), length(Positions, N), N < Arity,
      forall(member(P, Positions), (integer(P), between(1, Arity, P)))
    -> true ; throw(error(domain_error(functional_predicate, [Head,Arity,Positions]), _)) ),
    ( functional_predicate(Head, Kb, Arity, Positions) -> true
    ; ( functional_predicate(Head, Kb, _, _)
      ; '&kb'([Head|_], [Kb|_], _, _)
      ; rules('runtime-rule-row', _, [[Head|_],[Kb|_]|_], _) )
    -> throw(error(permission_error(declare, functional_predicate, Head), _))
    ; assertz(functional_predicate(Head, Kb, Arity, Positions)),
      'set-positive-only-predicate'(Kb, Head, true) ).

functional_key(Type, Context, Key) :-
    nonvar(Type), Type = [Head|Args], nonvar(Head),
    ground(Context), Context = [Kb,'MAIN','Nil'], functional_predicate(Head, Kb, Arity, Positions),
    length(Args, Arity), maplist(functional_arg(Args), Positions, Values),
    ground(Values), Key = functional(Kb, Head, Values).
functional_arg(Args, Position, Value) :- nth1(Position, Args, Value).

% Validate before publication, including no-check/bulk ingestion. Declarations
% are KB-local and apply to main-world inputs; private hypothetical facts do
% not assign or conflict with the world's immutable value.
functional_check_fact([Type, Context, _, TV], Assignment) :-
    ( nonvar(Type), Type = [Head|_], Context = [Kb,'MAIN','Nil'],
      functional_predicate(Head, Kb, _, _)
    -> ( ground(Type-TV), TV = ['STV',S,C], S =:= 1, C >= 1 -> true
       ; throw(error(domain_error(functional_input, Type-TV), _)) ),
       ( functional_key(Type, Context, Key) -> true
       ; throw(error(domain_error(functional_arity, Type), _)) ),
       term_hash(Key, Hash),
       ( functional_value(Hash, Key, Stored), Stored \== Type
       -> throw(error(permission_error(assign, functional_key, Key-Type), _)) ; true ),
       Assignment = [Hash,Key,Type]
    ; Assignment = [] ).

% Validate a source's complete lowering before publishing any of it. The
% local map also catches two conflicting conjuncts within that one source.
'functional-check-additions!'(Kb, Adds, true) :-
    ( functional_predicate(_, Kb, _, _)
    -> empty_assoc(Empty), foldl(functional_check_addition, Adds, Empty, _)
    ; true ).
functional_check_addition(Add, Before, After) :-
    ( Add = [rules,[_, '|-', Conclusion]]
    -> 'functional-rule!'(Conclusion, true), After = Before
    ; functional_check_fact(Add, Assignment),
      ( Assignment = [_,Key,Type]
      -> ( get_assoc(Key, Before, Stored), Stored \== Type
         -> throw(error(permission_error(assign, functional_key, Key-Type), _)) ; true ),
         put_assoc(Key, Before, Type, After)
      ; After = Before ) ).

'functional-fact!'(Fact, true) :-
    functional_check_fact(Fact, Assignment),
    ( Assignment = [Hash,Key,Type], \+ functional_value(Hash, Key, _)
    -> assertz(functional_value(Hash, Key, Type)),
       ( sk_search_owned(Hash, Key, _, _) -> sk_queue_retirement(Hash, Key) ; true )
    ; true ).

'functional-rule!'([Type, Context|_], true) :-
    ( nonvar(Context), Context = [Kb|_], nonvar(Kb),
      functional_predicate(Head, Kb, _, _),
      ( var(Type) ; Type = [Candidate|_], (var(Candidate) ; Candidate == Head) )
    -> throw(error(permission_error(derive, functional_predicate, Head), _))
    ; true ).

'sk-functional-conflict?'([Type,Context|_], Conflict) :-
    ( functional_key(Type, Context, Key), term_hash(Key, Hash),
      functional_value(Hash, Key, Stored), \+ unifiable(Type, Stored, _)
    -> Conflict = true ; Conflict = false ).

% An extensional functional node with its unique answer has no remaining
% producer work. Consume that key directly instead of allocating a lease and
% immediately retiring it again.
'sk-functional-exhausted?'(N, Exhausted) :-
    ( N = [Type,Context|_], functional_key(Type, Context, Key),
      term_hash(Key, Hash), functional_value(Hash, Key, _),
      'sk-node-hash'(N, H), '&sk_answer'(H, Stored, _), attribute_free_variant(Stored, N)
    -> Exhausted = true ; Exhausted = false ).

% A delivered value exhausts this subscription. Existing rows and key reads
% remain live for evidence updates; unassigned functional keys remain open.
% Snapshot only functional subscriptions, before extension binds their node.
'sk-functional-subscription'(W, Subscription) :-
    ( W = ['sk-partial',_,_,_,_,[N|_],_], N = [Type,Context|_],
      functional_key(Type, Context, Key), term_hash(Key, Hash), functional_value(Hash, Key, _)
    -> 'sk-node-hash'(N, H),
       ( sk_wait_ref(H, N, W, Ref) -> copy_term_nat([H,N,Ref], Subscription) ; Subscription = [] )
    ; Subscription = [] ).

'sk-functional-delivered!'([], true).
'sk-functional-delivered!'([H,N,Ref], true) :-
    ( '&sk_answer'(H, Stored, _), attribute_free_variant(Stored, N),
      clause(sk_wait_payload(_,_,_,_), true, Ref)
    -> sk_retire_wait_ref(Ref) ; true ).

sk_queue_retirement(H, Key) :-
    ( sk_retire_queue(H, Key) -> true ; assertz(sk_retire_queue(H, Key)) ).

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
sk_search_init :-
    (   nb_current(sk_search_listening, true) -> true
    ;   forall(member(Space/Arity, [sk_wait_payload/4, '&sk_join_link'/2, '&sk_child'/4,
                                   '&sk_deferred_joins'/3, '&sk_deferred'/3,
                                   '&sk_expanded'/2]),
               prolog_listen(user:Space/Arity, sk_search_changed(Space))),
        nb_setval(sk_search_listening, true)
    ).

sk_search_key([Type, Context|Rest], Hash, [Type, Context]) :-
    % Query adapters read a statement and reconstruct its proof; they are
    % exempt from the known-row rule in sk-complete-row! too.
    ( Rest = [Proof|_], nonvar(Proof), Proof = [Head|_], var(Head) -> fail ; true ),
    nonvar(Context), Context = [_, _, _], ground(Type-Context),
    term_hash([Type, Context], Hash).

% Use the same fact selection as sk-complete-row!: forward copies, filtered
% contexts and materialized facts cannot accidentally turn a cache into a
% reason to retire a search. Only known true/false facts are absorbing under
% conditioning; a fractional confidence-1 fact keeps its derivations.
'sk-known-conclusion?'(Conclusion, Known) :-
    sk_search_init,
    (   sk_search_key(Conclusion, _, [Type, Context]),
        'sk-leaf-facts'(Type, Context, 'sk-any-filter', Facts),
        member([_, [_, FactContext, _], Proof, ['STV', S, C]], Facts),
        C >= 1, (S =:= 0; S =:= 1),
        % A borrowed world fact cannot absorb an assumption-dependent path
        % that a private judgment still needs to discover.
        ( FactContext == 'MAIN' -> true ; 'assumption-proof?'(Proof, true) )
    ->  Known = true
    ;   Known = false
    ).

sk_search_index(Conclusion, Space, Ref) :-
    (   sk_search_key(Conclusion, H, _)
    ->  assertz(sk_search_clause(H, Space, Ref))
    ;   true ).

% Ownership rows copy only the hash, store kind and exact clause reference.
% Validate collisions against the owned clause, where the key already lives.
% Join digests retain the existing 60-bit identity contract used by thawing.
sk_search_owned(H, Key, Space, Ref) :-
    term_hash(Key, H), sk_search_clause(H, Space, Ref),
    ( Space == sk_functional_wait
    -> clause(sk_wait_payload(_, [Type,Context|_], _, _), true, Ref),
       functional_key(Type, Context, Stored), Key = Stored
    ; Space == '&sk_join_link'
    -> Key = [Type,Context], ground(Key),
       'link-digest'(['sk-key',Type,Context], D),
       clause('&sk_join_link'(D,_), true, Ref)
    ; ( Space == sk_wait_payload
      -> clause(sk_wait_payload(_, _, TemplateId, B), true, Ref),
         sk_wait_template(_, _, TemplateId, ['sk-partial',_,_,C|_], B)
      ; Space == sk_child_claim -> clause(sk_child_claim(_, _, C), true, Ref)
      ; sk_search_conclusion(Space, Row, C), clause(Row, true, Ref) ),
      sk_search_key(C, _, Key) ).

% Keep the conclusion index for thaw replay, and the waiter reference for
% lifetime. Capture the original partial before its answer binds open slots.
'sk-store-join!'(Digest, Waiter, Conclusion, New) :-
    sk_search_init,
    ( Conclusion = [Head|_], Head == 'CPU'
    -> Conclusion = [_,Fun,Args,_],
       ( Fun == 'GroupedFoldAllCompiled' -> Key = ['sk-group',Args] ; Key = ['sk-fold',Args] )
    ; Conclusion = [Type,Context|_], Key = ['sk-key',Type,Context] ),
    'link-digest'(Key, KeyDigest),
    ( '&sk_join_link'(KeyDigest, Digest) -> New = false
    ; assertz('&sk_join_link'(KeyDigest, Digest), Ref),
      sk_search_index(Conclusion, '&sk_join_link', Ref),
      Waiter = ['sk-partial',_,_,_,_,[N|_],_], 'sk-node-hash'(N,H),
      ( sk_wait_ref(H, N, Waiter, WaitRef) -> assertz(sk_join_wait(WaitRef, Ref)) ; true ),
      ( sk_search_key(Conclusion, _, [T,C]) -> 'sk-retire-known!'(T,C,true) ; true ),
      New = true ).

% A waiter batch already needs this digest for its child link. Retain a
% lease by clause reference, so retraction never hashes the partial again.
% Reopening an evicted cache reuses the subscription and its child lease.

'sk-store-wait!'(D, H, N, Waiter, true) :-
    sk_search_init,
    ( sk_wait_ref(H, N, Waiter, _) -> true
    ; Waiter = ['sk-partial', _, Id, C, Done, _, _], length(Done, Pos),
    ( sk_wait_template(Id, Pos, TemplateId, Template, Bindings), subsumes_term(Template, Waiter)
    -> Template = Waiter
    ; rules('runtime-rule-row', Id, Conclusion, Premises),
      copy_term_nat(Conclusion, Owner),
      length(Prefix, Pos), append(Prefix, Remaining, Premises), reverse(Prefix, Consumed),
      term_subsumer(['sk-partial', Owner, Id, Conclusion, Consumed, Remaining, _], Waiter, Template),
      term_variables(Template, Bindings),
      flag(sk_wait_template_id, TemplateId, TemplateId + 1),
      assertz(sk_wait_template(Id, Pos, TemplateId, Template, Bindings)),
      Template = Waiter ),
    assertz(sk_wait_payload(H, N, TemplateId, Bindings), Ref),
    variant_hash([N, TemplateId|Bindings], WaitHash), assertz(sk_wait_key(WaitHash, Ref)),
    assertz(sk_child_users(D, Ref)), sk_search_index(C, sk_wait_payload, Ref),
    ( N = [Type,Context|_], functional_key(Type, Context, Key), term_hash(Key, Hash),
      \+ functional_value(Hash, Key, _)
    -> assertz(sk_search_clause(Hash, sk_functional_wait, Ref)) ; true ) ).

% A continuation template is the compiled rule split at a premise position.
% Context routing and query proof patterns widen only the affected slots.
% Generalization preserves sharing only where both the compiled rule and
% the contextualized join share it; it never binds the join being encoded.
% Templates are shared, immutable, and leave with their last subscription.
:- use_module(library(terms), [term_subsumer/3]).
:- dynamic sk_wait_payload/4, sk_wait_template/5, sk_wait_key/2.
% The read-only relation exposes the existing transient delivery shape. The
% only owned clauses are compact payloads, indexed by the awaited node hash.
% sk_wait_key(Hash, Ref) finds one payload by the variant hash of its node,
% template and bindings: a node can hold many payloads of one template.
'&sk_wait'(H, N, Waiter) :-
    sk_wait_payload(H, N, TemplateId, Bindings),
    sk_wait_template(_, _, TemplateId, Waiter, Bindings).

% Select by continuation, then by the variant hash of node and bindings
% (variant_hash ignores attributes, as attribute_free_variant does); the alpha
% comparison rejects hash collisions.
sk_wait_ref(H, N, Waiter, Ref) :-
    Waiter = ['sk-partial',_,Id,_,Done,_,_], length(Done, Pos),
    sk_wait_template(Id, Pos, TemplateId, Template, Bindings),
    subsumes_term(Template, Waiter), Template = Waiter,
    variant_hash([N, TemplateId|Bindings], WaitHash), sk_wait_key(WaitHash, Ref),
    clause(sk_wait_payload(H, Stored, TemplateId, B), true, Ref),
    attribute_free_variant(Stored-B, N-Bindings), !.

sk_retire_wait_ref(Ref) :-
    setup_call_cleanup(nb_setval(sk_retiring, true), erase(Ref), nb_delete(sk_retiring)).

'sk-store-child!'(D, H, Owner, Child, CH, true) :-
    sk_search_init, assertz('&sk_child'(H, Owner, Child, CH), Ref),
    assertz(sk_child_edge(D, Ref)).

% Fixed leases carry the actual join conclusion, not just its open owner.
'sk-keep-child!'(D, Conclusion, true) :-
    sk_search_init, 'link-digest'(['sk-child-claim', D, Conclusion], Claim),
    ( sk_child_claim(Claim, _, _) -> true
    ; assertz(sk_child_claim(Claim, D, Conclusion), Ref),
      sk_search_index(Conclusion, sk_child_claim, Ref),
      ( sk_search_key(Conclusion, _, [Type, Context]) -> 'sk-retire-known!'(Type, Context, true) ; true ) ).

sk_search_conclusion('&sk_deferred_joins', '&sk_deferred_joins'(_, _, ['sk-join', ['sk-partial', _, _, C|_], _]), C).
sk_search_conclusion('&sk_deferred', '&sk_deferred'(_, _, ['sk-deferred', _, _, C|_]), C).

sk_search_changed(Space, assertz, Ref) :- !,
    ( sk_search_conclusion(Space, Row, C), clause(Row, true, Ref)
    -> sk_search_index(C, Space, Ref)
    ; Space == '&sk_expanded', clause('&sk_expanded'(H, N), true, Ref)
    -> sk_unwatch_fact(H, N)
    ; true ).
sk_search_changed(Space, retract, Ref) :- !,
    retractall(sk_search_clause(_, _, Ref)),
    (   Space == sk_wait_payload
    ->  clause(sk_wait_payload(_, N, TemplateId, Bindings), true, Ref),
        variant_hash([N, TemplateId|Bindings], WaitHash), retract(sk_wait_key(WaitHash, Ref)),
        ( once((clause(sk_wait_payload(_, _, TemplateId, _), true, Other), Other \== Ref)) -> true
        ; retractall(sk_wait_template(_, _, TemplateId, _, _)) ),
        ( sk_join_wait(Ref, _) -> assertz(sk_retire_wait(Ref)) ; true ),
        forall(retract(sk_child_users(D, Ref)), sk_release_child(D))
    ;   Space == '&sk_join_link'
    ->  retractall(sk_join_wait(_, Ref))
    ;   Space == '&sk_child', clause('&sk_child'(OH, O, N, NH), true, Ref),
        retract(sk_child_edge(D, Ref))
    ->  forall(clause(sk_child_claim(_, D, _), true, Claim), sk_erase_claim(Claim)),
        retractall(sk_child_debt(_, D)),
        (   nb_current(sk_retiring, true)
        ->  retractall('&sk_link'(D)), pw_unlink(OH, O, NH, N),
            pw_drop_unused(OH, O), pw_drop_unused(NH, N)
        ;   true )
    ;   true ).
sk_search_changed(_, _, _).

sk_erase_claim(Ref) :-
    retractall(sk_search_clause(_, _, Ref)), erase(Ref).

% Withdrawal uses the same lease release as known-conclusion retirement.
% Context cleanup keeps its own pending-graph transitions instead.

'sk-retire-wait!'(Hash, Premise, Waiter, true) :-
    ( sk_wait_ref(Hash, Premise, Waiter, Ref) -> sk_retire_wait_ref(Ref) ; true ).

% The node hash is already available at expansion/context cleanup. Only its
% few compact subscriptions need alpha comparison; no digest is computed.
sk_unwatch_fact(H, N) :-
    forall(clause('&sk_fact_watch'(H, _, Stored), true, Ref),
           ( attribute_free_variant(Stored, N) -> erase(Ref) ; true )).

% The typed native boundary exposes records whose schema is supplied here,
% rather than by a MeTTa add-atom specialization.
'sk-fact-watches'(H, Nodes) :- findall(N, '&sk_fact_watch'(H, _, N), Nodes).

% Ordinary context cleanup retains its existing pending-graph transitions.
% A released join can still lead to pending premise work shared with later
% queries. Keep that traversal until its component settles, then retire it
% by component index; removing it sooner changes finite-budget answers.
sk_release_child(D) :-
    (   nb_current(sk_retiring, true),
        \+ sk_child_users(D, _), \+ sk_child_claim(_, D, _), sk_child_edge(D, Ref)
    ->  clause('&sk_child'(_, _, N, NH), true, Ref),
        (   pw_known(NH, N, Id), pw_find(Id, R), pw_pending_rep(R)
        ->  ( sk_child_debt(R, D) -> true ; assertz(sk_child_debt(R, D)) )
        ;   erase(Ref) )
    ;   true ).

% Ingestion only records an indexed retirement. A bounded slice runs at query
% activation and after its answers: even closing a long-deferred outcome does
% not scan the history or erase all its owned records during the fact add.
'sk-retire-known!'(Type, Context, true) :-
    sk_search_init,
    (   sk_search_key([Type, Context], H, Key),
        once((sk_search_owned(H, Key, _, _) ; sk_search_node(H, Key, _, _))),
        'sk-known-conclusion?'([Type, Context], true)
    ->  sk_queue_retirement(H, Key)
    ;   true ).

'sk-retire-searches!'(true) :-
    setup_call_cleanup(nb_setval(sk_retiring, true), sk_retire_slice(512), nb_delete(sk_retiring)).

sk_retire_slice(0) :- !.
sk_retire_slice(Units) :-
    (   sk_retire_wait(WaitRef)
    ->  ( sk_join_wait(WaitRef, JoinRef) -> erase(JoinRef)
        ; retract(sk_retire_wait(WaitRef)) ),
        Left is Units - 1, sk_retire_slice(Left)
    ;   sk_retire_queue(H, Key)
    ->  (   sk_search_owned(H, Key, Space, Ref)
        ->  ( Key = functional(_,_,_)
            -> ( clause(sk_wait_payload(_, N, _, _), true, Ref), 'sk-functional-conflict?'(N, true)
               -> sk_retire_clause(Space, Ref)
               ; retractall(sk_search_clause(H, Space, Ref)) )
            ; sk_retire_clause(Space, Ref) )
        ;   clause(sk_search_node(H, Key, NH, N), true, NodeRef)
        ->  erase(NodeRef), pw_drop_unused(NH, N)
        ;   retract(sk_retire_queue(H, Key)) ),
        Left is Units - 1, sk_retire_slice(Left)
    ;   sk_retire_component(R)
    ->  (   pw_pending_rep(R) -> retract(sk_retire_component(R))
        ;   clause(sk_child_debt(R, D), true, Ref)
        ->  erase(Ref), sk_release_child(D)
        ;   retract(sk_retire_component(R)) ),
        Left is Units - 1, sk_retire_slice(Left)
    ;   true ).

sk_retire_clause(Space, Ref) :-
    % A ground unexpanded premise used its waiter as a fact subscription.
    % Preserve that read once per node, without the obsolete join payload.
    (   memberchk(Space, [sk_wait_payload,sk_functional_wait]), clause(sk_wait_payload(H, N, _, _), true, Ref), N = [T, C, _, _],
        sk_search_key([T, C], _, _), 'sk-functional-conflict?'(N, false),
        \+ ( '&sk_expanded'(H, S), attribute_free_variant(S, N) ),
        'link-digest'(['sk-fact-watch', N], D), \+ '&sk_fact_watch'(_, D, _)
    ->  assertz('&sk_fact_watch'(H, D, N))
    ;   true ),
    (   memberchk(Space, ['&sk_deferred_joins', '&sk_deferred']), clause(Row, true, Ref)
    ->  (   Row = '&sk_deferred_joins'(H, _, ['sk-join', ['sk-partial', O|_], _])
        ;   Row = '&sk_deferred'(H, _, ['sk-deferred', O|_]) ),
        'sk-work!'(H, O, -1, [])
    ;   true ),
    ( Space == sk_child_claim
    -> clause(sk_child_claim(_, D, _), true, Ref), sk_erase_claim(Ref), sk_release_child(D)
    ; erase(Ref) ).

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

pw_drop_unused(H, N) :-
    (   pw_known(H, N, Id), pw_find(Id, R), pw_size(R, 1), pw_deg(R, 0, 0),
        \+ holds_work(H)
    ->  (   'sk-known-conclusion?'(N, true)
        ->  forall(clause('&sk_score'(H, S, _), true, Ref), (attribute_free_variant(S, N) -> erase(Ref);true))
        ;   true ),
        'sk-drop-pending!'(H, N, [])
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

% A producer must cover the entire query, without specializing either term.
'term-covers?'(General, Specific, Result) :-
    ( subsumes_term(General, Specific) -> Result = true ; Result = false ).

% Unlike a sampling declaration, immutable inputs forbid every derived value.
'functional-pattern?'(Kb, Pattern, Result) :-
    'implication-side-conjuncts'(Pattern, Parts),
    ( member(Part, Parts), 'canon'(Part, [Type, _]),
      nonvar(Type), Type = [Head|_], functional_predicate(Declared, Kb, _, _),
      ( var(Head) ; Head == Declared )
    -> Result = true ; Result = false ).

% Disconnected parts range over a Cartesian product. A separate joint rate
% would contradict that model; reject it rather than silently ignoring it.
'validate-base-rate!'(Pattern, Parts, TV, true) :-
    ( 'member-canon'(Pattern, Canonical), rate_class_link(Canonical)
    -> throw(error(domain_error(base_rate_class_link, Pattern),
                   context('set-base-rate'/3, 'a class link is a rule, no population: rate a class membership as (Member $x Class)')))
    ; true ),
    ( 'canon'(Pattern, [_, true]), \+ (nonvar(TV), TV = ['STV'|_])
    -> throw(error(domain_error(negated_base_rate_value, TV),
                   context('set-base-rate'/3, 'a negated statement takes an STV')))
    ; true ),
    ( Parts = [_,_|_]
    -> throw(error(domain_error(disconnected_base_rate, Pattern),
                   context('set-base-rate'/3, 'set a rate for each connected part')))
    ; true ).

% A canonical rate pattern stating a class link, (Inheritance A B) in any of
% its spellings, with either class a name or a variable, at its top or under a
% connective.
rate_class_link(Pattern) :-
    nonvar(Pattern), Pattern = [Head|Args],
    (   Head == 'Implication'
    ->  Args = [[Sub, X], [Super, Y]], var(X), X == Y,
        forall(member(Class, [Sub, Super]), ( var(Class) ; atom(Class) ))
    ;   memberchk(Head, ['And', 'Or', 'Not']), member(Arg, Args), rate_class_link(Arg) ), !.

% A view's evidence as its readers inherit it: the role in which the view read
% a certain fact (given-ev, a condition) is that view's own; a reader holds the
% fact itself. A set with no given entry is itself. Sets never change, so each
% is computed once; the memo goes with its set, and a collected result is
% computed again.
:- dynamic ev_inherited_memo/2.
'evidence-inherited'(['ev-set', A], ['ev-set', C]) :-
    (   ev_inherited_memo(A, C0), ( C0 == A ; ev_set(C0, _, _, _, _) ) -> refs_gc_touch_set(C0), C = C0
    ;   retractall(ev_inherited_memo(A, _)), ev_order(A, Ids),
        (   member(Id, Ids), ev_given_fact(Id, _)
        ->  maplist(ev_inherited_id, Ids, Out), list_to_set(Out, Set), ev_of_ids(Set, C)
        ;   C = A ),
        assertz(ev_inherited_memo(A, C)) ).
ev_inherited_id(Id, Out) :- ( ev_given_fact(Id, Fact) -> Out = Fact ; Out = Id ).

% The fact entries stored with Proof of Evidence's inherited set, in its
% order. They are found by the proof's hash, without reading the set: a fact
% is inherited when it or a condition given it is in the set.
'evidence-proof-fact'(['ev-set', A], Proof, Entry) :-
    'index-hash'(Proof, Hash), ev_sorted(A, Sorted),
    findall(Id, ( ev_proof_entry(Hash, Id), ev_entry(Id, _, ['fact-ev', _, Proof, _]),
                  ( ord_memberchk(Id, Sorted) -> true ; ev_given_fact(Given, Id), ord_memberchk(Given, Sorted) ) ),
            Ids),
    (   Ids = [_, _|_]
    ->  ev_order(A, Order), maplist(ev_inherited_id, Order, Out), list_to_set(Out, Set),
        include([Id]>>memberchk(Id, Ids), Set, Ordered)
    ;   Ordered = Ids ),
    member(Id, Ordered), ev_entry(Id, _, Entry).

% Stored binary-certain facts and conditions are certain entries. A fact's
% certainty is read from the live KB, not cached with its entry.
ev_entry_certain(Id) :- ev_entry(Id, _, E), ev_entry_is_certain(E).
ev_entry_is_certain(['given-ev'|_]) :- !.
ev_entry_is_certain(['rule-ev', Kb, Name]) :- !,
    catch('&given_rules'(Name, Kb), error(existence_error(procedure, _), _), fail).
ev_entry_is_certain(['not-ev', Inner]) :- !, ev_entry_is_certain(Inner).
ev_entry_is_certain(['not-fact-ev', Ctx, P, Type]) :- !, ev_entry_is_certain(['fact-ev', Ctx, P, Type]).
ev_entry_is_certain(['fact-ev', Ctx, P, Type]) :- !,
    once(catch('&kb'(Type, Ctx, P, ['STV', S, C]), error(existence_error(procedure, _), _), fail)),
    ev_binary_certain(S, C).
ev_binary_certain(S, C) :- number(S), number(C), C >= 1.0, ( S >= 1.0 ; S =< 0.0 ).

% The evidence B's raw sources add to A, as a count: none (0) when B lies
% within A; unbounded (-1) when a source new to A is certain (a binary fact,
% a given, or a value at confidence 1); otherwise the sum of the counts
% k c/(1 - c) of B's new sources, a source whose truth value cannot be read
% counting nothing (what A already holds is never counted again).
'evidence-unique-count'(K, ['ev-set', A], ['ev-set', B], Count) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ord_subtract(SortedB, SortedA, New),
    (   New == []
    ->  Count = 0.0
    ;   member(Id, New), ( ev_entry_certain(Id) ; entry_confidence(Id, C), C >= 1.0 )
    ->  Count = -1.0
    ;   foldl(entry_count(K), New, 0.0, Count) ).

entry_count(K, Id, N0, N) :- ( entry_confidence(Id, C) -> N is N0 + K * C / (1 - C) ; N = N0 ).

entry_confidence(Id, C) :- ev_entry(Id, _, Entry), entry_tv_confidence(Entry, C).
entry_tv_confidence(['not-ev', Inner], C) :- !, entry_tv_confidence(Inner, C).
entry_tv_confidence(['not-fact-ev', Ctx, P, Type], C) :- !, entry_tv_confidence(['fact-ev', Ctx, P, Type], C).
entry_tv_confidence(['fact-ev', Ctx, P, Type], C) :- !,
    once(catch('&kb'(Type, Ctx, P, TV), error(existence_error(procedure, _), _), fail)), tv_confidence(TV, C).
entry_tv_confidence(['rule-ev', Kb, Name], C) :-
    once(catch('&kb'(_, [Kb|_], Name, TV),
               error(existence_error(procedure, _), _), fail)),
    tv_confidence(TV, C).
tv_confidence(['STV', _, C], C).
tv_confidence(['CTV', ['STV', _, C1], ['STV', _, C2]], C) :- C is min(C1, C2).

% Whether two views share an uncertain entry. Only the shared entries are
% classified.
'evidence-uncertain-overlap?'(['ev-set', A], ['ev-set', B], Result) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    ( ev_shared_where(ev_uncertain_id, SortedA, SortedB) -> Result = true ; Result = false ).
ev_uncertain_id(Id) :- \+ ev_entry_certain(Id).
% Whether two sorted id lists share an id meeting Goal; stops at the first.
ev_shared_where(Goal, [X|Xs], [Y|Ys]) :-
    compare(Order, X, Y),
    (   Order == (=) -> ( call(Goal, X) -> true ; ev_shared_where(Goal, Xs, Ys) )
    ;   Order == (<) -> ev_shared_where(Goal, Xs, [Y|Ys])
    ;   ev_shared_where(Goal, [X|Xs], Ys) ).

% A's entries without the certain entries of B.
'evidence-subtraction-certain'(['ev-set', A], ['ev-set', B], ['ev-set', C]) :-
    ev_sorted(B, SortedB), include(ev_entry_certain, SortedB, Certain),
    ev_sorted(A, SortedA), ord_subtract(SortedA, Certain, Kept),
    (   Kept == SortedA -> C = A
    ;   ev_order(A, IdsA), ev_keep(IdsA, Kept, Ids), ev_of_ids(Ids, C) ).

% A certain fact a row read as a condition (its stored proof among the row's
% condition leaves, by hash) becomes given-ev in the row's evidence, or
% (not-ev given-ev) when read under a Not. Only the leaves' entries are looked at.
'evidence-condition'(['ev-set', A], Names, ['ev-set', C]) :-
    findall(Id, ( member(Name, Names), ev_proof_entry(Name, Id), ev_entry_certain(Id) ), Leaves0),
    (   Leaves0 == [] -> C = A
    ;   sort(Leaves0, Leaves), ev_sorted(A, SortedA), ord_intersection(SortedA, Leaves, Given),
        (   Given == [] -> C = A
        ;   ev_order(A, Ids), maplist(ev_condition_id(Given), Ids, Out), list_to_set(Out, Set), ev_of_ids(Set, C) ) ).
ev_condition_id(Given, Id, Out) :-
    (   ord_memberchk(Id, Given), ev_entry(Id, _, [Tag, K, P, T])
    ->  ( Tag == 'fact-ev' -> ev_entry_id(['given-ev', K, P, T], Out) ; ev_entry_id(['not-ev', ['given-ev', K, P, T]], Out) )
    ;   Out = Id ).

% How two views share a certain fact: `observed` when both observed it,
% `a-condition` / `b-condition` when one read it as a condition the other
% observed, outside complete predicates (whether that is a loop depends on the
% reader being a forward view), `no-shared` otherwise. Roles are given-ev / fact-ev.
'evidence-observed-roles'(['ev-set', A], ['ev-set', B], Result) :-
    ev_sorted(A, SortedA), ev_sorted(B, SortedB),
    (   ev_shared_where(ev_certain_observation, SortedA, SortedB) -> Result = observed
    ;   ev_given_facts(A, SortedA, GivenA), ord_intersection(GivenA, SortedB, AB), \+ maplist(ev_complete_entry, AB)
    ->  Result = 'a-condition'
    ;   ev_given_facts(B, SortedB, GivenB), ord_intersection(GivenB, SortedA, BA), \+ maplist(ev_complete_entry, BA)
    ->  Result = 'b-condition'
    ;   Result = 'no-shared' ).
% The certain facts a set read as conditions, as sorted fact-ev ids. Sets never
% change, so they are computed once (a collected set's id is never reused).
:- dynamic ev_given_memo/2.
ev_given_facts(Set, Sorted, Facts) :-
    (   ev_given_memo(Set, Facts0) -> Facts = Facts0
    ;   findall(Fact, ( member(Id, Sorted), ev_given_fact(Id, Fact) ), Facts1), sort(Facts1, Facts),
        assertz(ev_given_memo(Set, Facts)) ).
ev_certain_observation(Id) :- ev_entry(Id, _, [Tag|_]), memberchk(Tag, ['fact-ev', 'not-fact-ev']), ev_entry_certain(Id).
ev_complete_entry(Id) :-
    ev_entry(Id, _, ['fact-ev', [Kb, 'MAIN', _], _, Type]), ground(Type),
    ( Type = [Head|_] -> true ; Head = Type ),
    catch('&complete_predicates'(Kb, Head), error(existence_error(procedure, _), _), fail).
