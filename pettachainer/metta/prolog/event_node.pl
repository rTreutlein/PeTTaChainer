% Event-node semantics and numerical contracts: docs/metta/event_node_contract.md.
:- module(event_node, [event_node_dist/5, event_node_moments/4, event_node_coupling/5, event_node_widen/6, dist_mean/2, event_node_product/3]).
:- autoload(library(simplex)).
:- use_module(library(yall)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(assoc)).
:- use_module(library(ordsets)).

event_node_dist(_, S, C, _, point(S)) :- C >= 1.0, !.
event_node_dist(stored, _, C, _, beta(1.0, 1.0)) :- C =< 0.0, !.
event_node_dist(stored, S, C, K, beta(A, B)) :- N is K * C / (1 - C), A is N * S + 1, B is N * (1 - S) + 1.
event_node_dist(view, S, C, _, bernoulli(S)) :- C =< 0.0, !.
event_node_dist(view, S, C, K, beta(A, B)) :-
    N is K * C / (1 - C), A is max(1.0e-12, N * S), B is max(1.0e-12, N * (1 - S)).

% Strength uses the existing multilinear evaluation. Confidence uses only
% closed polynomial moments; the ratio bound is derived in the contract.
event_node_moments(Vars, Terms0, Goals, Answers) :-
    foldl([t(C, _, _), M0, M]>>(M is max(M0, abs(C))), Terms0, 0.0, Scale),
    (   Scale =:= 0.0
    ->  Answers = inconsistent
    ;   maplist(scaled_term(Scale), Terms0, Terms),
        pairs_keys_values(Vars, Ids, Dists), maplist(dist_mean, Dists, Means),
        pairs_keys_values(MuPairs, Ids, Means), list_to_assoc(MuPairs, Mu),
        forms(Terms, Goals, Mu, Z0, Ns),
        (   Z0 =< 0.0
        ->  Answers = inconsistent
        ;   maplist(constant_goal(Terms), Goals, Answers) -> true
        ;   maplist(parameter_moments, Vars, Moments), list_to_assoc(Moments, Stats),
            polynomial(Stats, Terms, Z),
            polynomial_product(Stats, Z, [[]-1], EZ),
            polynomial_product(Stats, Z, Z, EZ2),
            ZVar is EZ2 - EZ * EZ,
            maplist(polynomial_answer(Stats, Terms, Z, EZ, EZ2, ZVar, Z0), Goals, Ns, Answers) ) ).

scaled_term(Scale, t(C0, Lits, Gs), t(C, Lits, Gs)) :- C is C0 / Scale.
dist_mean(point(X), X).
dist_mean(bernoulli(M), M).
dist_mean(beta(A, B), M) :- M is A / (A + B).
dist_mean(moments(M, _), M).

event_node_product(Dists, Complement, moments(M, M2)) :-
    foldl({Complement}/[D, A-B, X-Y]>>(
        parameter_moments(_-D, _-m(U, V)),
        ( Complement == true -> X is A*(1-U), Y is B*(1-2*U+V)
        ; X is A*U, Y is B*V )), Dists, 1-1, M-M2).

% Rational arithmetic keeps polynomial cancellation exact, including small
% endpoint complements and concentrated stationary interactions.
parameter_moments(Id-D, Id-m(M, M2)) :-
    ( D = moments(M, M2) -> true
    ; D = beta(A0, B0)
    -> A is rational(A0), B is rational(B0), T is A + B,
       M is A rdiv T, M2 is (A * (A + 1)) rdiv (T * (T + 1))
    ; D = bernoulli(P) -> M is rational(P), M2 = M
    ; D = point(P), M is rational(P), M2 is M * M ).

% Expand negative literals, fold points, and collect equal positive monomials.
polynomial(Stats, Terms, Poly) :-
    findall(Key-C,
            ( member(t(C0, Lits, _), Terms), R is rational(C0),
              foldl(expand_literal(Stats), Lits, [[]-R], Expanded),
              member(Ids-C, Expanded), msort(Ids, Key) ), Pairs),
    keysort(Pairs, Sorted), group_pairs_by_key(Sorted, Groups),
    findall(Key-C, (member(Key-Cs, Groups), sum_list(Cs, C), C =\= 0), Poly).

expand_literal(Stats, Id-Bit, P0, P) :-
    get_assoc(Id, Stats, m(M, M2)),
    (   M2 =:= M * M
    ->  ( Bit =:= 1 -> X = M ; X is 1 - M ),
        maplist({X}/[K-C0, K-C]>>(C is C0 * X), P0, P)
    ;   Bit =:= 1
    ->  maplist({Id}/[K-C, [Id|K]-C]>>true, P0, P)
    ;   maplist({Id}/[K-C0, [Id|K]-C]>>(C is -C0), P0, Negative), append(P0, Negative, P) ).

% E[fg]: a shared parameter contributes its second moment; all other
% parameters contribute their means. This is exact for multilinear f and g.
polynomial_product(Stats, A, B, E) :-
    foldl({Stats, B}/[Ka-Ca, E0, E1]>>
          foldl({Stats, Ka, Ca}/[Kb-Cb, V0, V]>>
                ( Product is Ca * Cb, ord_union(Ka, Kb, Union), ord_intersection(Ka, Kb, Shared),
                  foldl({Stats, Shared}/[Id, W0, W]>>
                        ( get_assoc(Id, Stats, m(M, M2)),
                          ( memberchk(Id, Shared) -> W is W0 * M2 ; W is W0 * M ) ),
                        Union, Product, Weight),
                  V is V0 + Weight ), B, E0, E1), A, 0, E).

polynomial_answer(Stats, Terms, Z, EZ, EZ2, ZVar, Z0, Goal, N0, a(S, V, Kind)) :-
    S is N0 / Z0,
    include({Goal}/[t(_, _, Hits)]>>memberchk(Goal, Hits), Terms, GoalTerms),
    polynomial(Stats, GoalTerms, N),
    polynomial_product(Stats, N, [[]-1], EN),
    polynomial_product(Stats, N, N, EN2), polynomial_product(Stats, N, Z, ENZ),
    Center is EN rdiv EZ,
    Q is EN2 - 2 * Center * ENZ + Center * Center * EZ2,
    Bound is (Q + max(Center, 1 - Center) * sqrt(ZVar * Q)) / (EZ * EZ),
    V is float(min(Center * (1 - Center), Bound)),
    ( (ZVar =:= 0 ; Q =:= 0) -> Kind = exact ; Kind = conservative ).

% A goal forced by every surviving term is independent of all parameters.
constant_goal(Terms, Goal, a(S, 0.0, exact)) :-
    ( forall(member(t(C, _, Hits), Terms), (C =:= 0 ; memberchk(Goal, Hits))) -> S = 1.0
    ; forall(member(t(C, _, Hits), Terms), (C =:= 0 ; \+ memberchk(Goal, Hits))), S = 0.0 ).

% Z and each goal's N at the parameters Theta (an assoc).
forms(Terms, Goals, Theta, Z, Ns) :-
    maplist([_, 0.0]>>true, Goals, Zero),
    foldl(add_term(Goals, Theta), Terms, 0.0-Zero, Z-Ns).

add_term(Goals, Theta, t(Coef, Lits, Gs), Z0-N0, Z-N) :-
    foldl(lit_value(Theta), Lits, Coef, W),
    Z is Z0 + W,
    maplist({Gs, W}/[Goal, A, B]>>( memberchk(Goal, Gs) -> B is A + W ; B = A ), Goals, N0, N).

lit_value(Theta, Id-Bit, P0, P) :-
    get_assoc(Id, Theta, X),
    ( Bit =:= 1 -> P is P0 * X ; P is P0 * (1 - X) ).

event_node_coupling(Ps, _, _, _, interval(0.0, 1.0)) :- length(Ps, J), J > 4, !.
event_node_coupling(Ps, Pairs, Lambdas0, Goal, Result) :-
    max_list(Lambdas0, Scale),
    length(Ps, J), Last is (1 << J) - 1, numlist(0, Last, Cs),
    numlist(1, J, Is),
    maplist([I, P, [I]-P]>>true, Is, Ps, Marginals),
    maplist([pj(I1, I2, P), [I1, I2]-P]>>true, Pairs, Joints),
    append(Marginals, Joints, Fixed),
    (   Scale =< 0.0
    ->  Result = inconsistent
    ;   maplist(scaled_rational(Scale), Lambdas0, Lambdas),
        maplist([C, L, L*y(C)]>>true, Cs, Lambdas, Evidence),
        maplist([C, 1*y(C)]>>true, Cs, Mass),
        gen_state(P0),
        constraint(Mass = 1, P0, P1),
        foldl(fixed_mass(Cs, 1), Fixed, P1, P2),
        (   catch(maximize(Evidence, P2, Primal), _, fail), objective(Primal, Most), Most > 0
        ->  gen_state(S0),
            constraint(Evidence = 1, S0, S1),
            constraint([-1*t|Mass] = 0, S1, S2),
            foldl(fixed_mass(Cs, t), Fixed, S2, S3),
            foldl([C, L, G, O0, O]>>( G =:= 1 -> O = [L*y(C)|O0] ; O = O0 ), Cs, Lambdas, Goal, [], Objective),
            (   Objective == [] -> Result = interval(0.0, 0.0)
            ;   minimize(Objective, S3, Min), objective(Min, MinV),
                maximize(Objective, S3, Max), objective(Max, MaxV),
                Lo is float(MinV), Hi is float(MaxV), Result = interval(Lo, Hi) )
        ;   Result = inconsistent ) ).

scaled_rational(Scale, L0, L) :- L is rationalize(L0 / Scale).

% The cells where every one of Events holds carry P of the mass: of 1 (the
% joint itself) or of t (Charnes-Cooper's scaled joint).
fixed_mass(Cs, Mass, Events-P, S0, S) :-
    include(holds_all(Events), Cs, In),
    maplist([C, 1*y(C)]>>true, In, Ys), R is rationalize(P),
    (   Mass == t -> Q is -R, constraint([Q*t|Ys] = 0, S0, S)
    ;   constraint(Ys = R, S0, S) ).

holds_all(Events, C) :- forall(member(I, Events), C >> (I - 1) /\ 1 =:= 1).

event_node_widen(S, V, Lo, Hi, S1, V1) :-
    S1 is min(Hi, max(Lo, S)),
    D is max(S1 - Lo, Hi - S1),
    V1 is V + (D / 2) ** 2.
