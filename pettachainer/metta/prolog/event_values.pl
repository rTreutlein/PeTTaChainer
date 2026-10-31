% Numerical event-value kernels; no search or evaluator control.

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
    length(Dists, Count), Count =< 12,
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
    length(Dists, Count), Count =< 12, Last is Count - 1, numlist(0, Last, Is),
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
    (   separable(Likelihoods, Count)
    ->  maplist(literal_factor, Likelihoods, Factors),
        separable_moments(PDist, Factors, Count, S, V, Max)
    ;   union_node(PDist, Likelihoods, S, V), Max is S * (1 - S) ),
    node_stv(K, S, V, Max, TV).

prior_dist(_, _, uniform, beta(1.0, 1.0)) :- !.
prior_dist(K, BaseProof, ['STV', S, C], Dist) :-
    (   ( stored_proof(BaseProof) ; 'sk-step-proof'(BaseProof, ['population-prior'|_]) )
    ->  Kind = stored ; Kind = view ),
    event_node_dist(Kind, S, C, K, Dist).

% Every compound a connective over distinct literals, no other atom shared.
separable(Likelihoods, Count) :-
    maplist([[likelihood, F|_]]>>literal_formula(F), Likelihoods),
    foldl(sibling_keys, Likelihoods, [], All),
    sort(All, Distinct), same_length(All, Distinct), length(All, N), Count is N + 1.
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

% Fold point parameters into the coefficient before polynomial moments. Worlds
% with the same remaining monomial and goal can then be summed exactly.
node_fixed_literal(Vars, Id-B, W0-L0, W-L) :-
    memberchk(Id-Dist, Vars),
    ( Dist = point(P)
    -> ( B =:= 1 -> F = P ; F is 1 - P ), safe_log(F, LF), log_add(W0, LF, W), L = L0
    ; W = W0, L = [Id-B|L0] ).

separable_moments(PDist, Factors, Count, S, V, Max) :-
    dist_mean(PDist, Mu),
    maplist([f(W, _, _), Mw]>>moments(W, Mw, _), Factors, Ws),
    log_lambdas(Factors, Ws, LL1, LL0),
    log_weighted(Mu, LL1, A), log_weighted_complement(Mu, LL0, B),
    log_sum(A, B, LZ), LZ \== ninf, exp_diff(A, LZ, S),
    ( ( A == ninf ; B == ninf ) -> Max = 0.0 ; Max is exp(A + B - 2 * LZ) ),
    maplist(narrowed, Factors, Narrowed),
    findall(I-W, ( nth1(I, Narrowed, f(W, _, _)), W \= point(_) ), Nuisance),
    Vars = [0-PDist|Nuisance], exclude([_-D]>>(D = point(_)), Vars, Free), length(Free, D),
    ( ( D =:= 0 ; Max =:= 0 ) -> V = 0.0
    ; ( D > 4 ; Count > 12, Nuisance \== [] ) -> V = bound
    ; findall(LW-Lits-Hits,
              ( maplist([I-_, I-Bit]>>member(Bit, [0, 1]), Nuisance, Bits), member(P, [0, 1]),
                findall(Wv, ( nth1(I, Narrowed, f(W, _, _)),
                              ( W = point(Wv) -> true ; memberchk(I-Wv, Bits) ) ), World),
                log_lambdas(Narrowed, World, L1, L0),
                ( P = 1 -> L = L1, Hits = [1] ; L = L0, Hits = [] ),
                foldl(node_fixed_literal(Vars), [0-P|Bits], L-[], LW-Lits), LW \== ninf ), Weighted),
      foldl([LW-_-_, M0, M]>>(M is max(M0, LW)), Weighted, -1.0e300, Top),
      maplist({Top}/[LW-Lits-Hits, t(C, Lits, Hits)]>>(C is exp(LW - Top)), Weighted, Terms),
      event_node_moments(Vars, Terms, [1], [a(_, V0, Kind)]),
      ( Kind == bound -> V = bound ; V = V0 ) ).

% A factor whose lambdas change by less than 1e-9 of themselves over its W's
% whole range is constant to that precision: its W is a point at its mean.
narrowed(f(W, L1, L0), f(Point, L1, L0)) :-
    W \= point(_), moments(W, Mw, _),
    forall(member(L, [L1, L0]), lambda_flat(L, Mw)), !, Point = point(Mw).
narrowed(F, F).

lambda_flat(L, Mw) :-
    lambda_at(L, Mw, X), lambda_at(L, 0.0, X0), lambda_at(L, 1.0, X1),
    ( X =:= 0.0 -> X0 =:= 0.0, X1 =:= 0.0 ; abs(X0 - X) =< 1.0e-9 * X, abs(X1 - X) =< 1.0e-9 * X ).

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
    'proof-semantic'(Proof, ['kinematic-update', _KProof, Prediction, Conditionals, Index, _]),
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
    ( V >= Max -> C = 0.0
    ; Sc is min(1 - 1.0e-6, max(1.0e-6, S)),
      N is Sc * (1 - Sc) / V - 1, C is N / (N + K) ).

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
