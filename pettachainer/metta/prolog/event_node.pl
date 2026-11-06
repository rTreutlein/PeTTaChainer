% Event-node semantics and numerical contracts: docs/metta/event_node_contract.md.
:- module(event_node, [event_node_dist/5, event_node_moments/4, event_node_expectations/5, event_node_answer/2, event_node_coupling/5, event_node_widen/6, dist_mean/2]).
:- autoload(library(simplex)).
:- use_module(library(yall)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(pairs)).
:- use_module(library(assoc)).

event_node_dist(_, S, C, _, point(S)) :- C >= 1.0, !.
event_node_dist(stored, _, C, _, beta(1.0, 1.0)) :- C =< 0.0, !.
event_node_dist(stored, S, C, K, beta(A, B)) :- N is K * C / (1 - C), A is N * S + 1, B is N * (1 - S) + 1.
event_node_dist(view, S, C, _, bernoulli(S)) :- C =< 0.0, !.
event_node_dist(view, S, C, K, beta(A, B)) :-
    N is K * C / (1 - C), A is max(1.0e-12, N * S), B is max(1.0e-12, N * (1 - S)).

% One polynomial gives strength and confidence. A literal Id-Bit reads theta
% or 1-theta of parameter Id, and w(Literals)-Bit their product or its
% complement. A parameter used repeatedly keeps its powers: a monomial maps
% each parameter to c(T, F), its powers of theta and of 1-theta.
event_node_moments(Vars, Terms, Goals, Answers) :-
    event_node_expectations(Vars, Terms, Goals, [_]>>true, Moments),
    ( is_list(Moments) -> maplist(event_node_answer, Moments, Answers) ; Answers = Moments ).

% Each goal's m(E[N], E[Z], E[N^2], E[NZ], E[Z^2]), exact rationals: the
% moments of independent components multiply. Pay is called with the scalar
% operations of each step before the step: the expanded monomials times the
% parameters they can carry for Z and every N, then the monomial pairs of the
% paired moments times their length. A refused payment is unaffordable.
event_node_expectations(Vars, Terms0, Goals, Pay, Moments) :-
    foldl([t(C, _, _), M0, M]>>(M is max(M0, abs(C))), Terms0, 0.0, Scale),
    foldl([t(_, Lits, _), W0, W]>>( aggregate_all(count, member(w(_)-0, Lits), N),
                                   W is W0 + 1 << N ), Terms0, 0, Expanded),
    findall(Id, ( member(t(_, Lits, _), Terms0), member(L-_, Lits),
                  ( L = w(Ls) -> member(Id-_, Ls) ; Id = L ), \+ memberchk(Id-point(_), Vars) ), Ids0),
    sort(Ids0, Ids), length(Ids, Owners), length(Goals, NG),
    (   Scale =:= 0.0
    ->  Moments = inconsistent
    ;   Build is Expanded * (Owners + 1) * (NG + 1), \+ call(Pay, Build)
    ->  Moments = unaffordable
    ;   maplist(scaled_term(Scale), Terms0, Terms), list_to_assoc(Vars, Dists),
        polynomial(Dists, Terms, Z),
        maplist({Dists, Terms}/[Goal, N]>>( include({Goal}/[t(_, _, Hits)]>>memberchk(Goal, Hits), Terms, GoalTerms),
                                           polynomial(Dists, GoalTerms, N) ), Goals, Ns),
        append([Z|Ns], Monomials), pairs_keys(Monomials, Keys),
        foldl([K, L0, L]>>(length(K, LK), L is max(L0, LK)), Keys, 1, Width),
        length(Z, LZ),
        foldl({LZ}/[N, P0, P]>>(length(N, LN), P is P0 + LN * LN + LN * LZ), Ns, LZ * LZ, Pairs),
        (   Pair is Pairs * Width, \+ call(Pay, Pair)
        ->  Moments = unaffordable
        ;   append(Keys, Uses),
            findall(Id-Stat, ( member(Id-Dist, Vars), Dist \= point(_), parameter_stat(Uses, Id, Dist, Stat) ), Stats0),
            list_to_assoc(Stats0, Stats),
            expectation(Stats, Z, [[]-1], EZ),
            (   EZ =< 0
            ->  Moments = inconsistent
            ;   expectation(Stats, Z, Z, EZ2),
                maplist({Stats, Z, EZ, EZ2}/[N, m(EN, EZ, EN2, ENZ, EZ2)]>>(
                            expectation(Stats, N, [[]-1], EN), expectation(Stats, N, N, EN2),
                            expectation(Stats, N, Z, ENZ) ), Ns, Moments) ) ) ).

scaled_term(Scale, t(C0, Lits, Gs), t(C, Lits, Gs)) :- C is C0 / Scale.
dist_mean(point(X), X).
dist_mean(bernoulli(M), M).
dist_mean(beta(A, B), M) :- M is A / (A + B).

% E[theta^T (1-theta)^F] up to twice the powers used, so products of two
% polynomials stay exact: for a Beta, rising factorials of a, b and a+b.
parameter_stat(Uses, Id, Dist, Stat) :-
    foldl({Id}/[I-c(U, G), T0-F0, T1-F1]>>( I == Id -> T1 is max(T0, U), F1 is max(F0, G) ; T1-F1 = T0-F0 ),
          Uses, 0-0, T-F),
    Tm is 2 * T, Fm is 2 * F, TFm is Tm + Fm,
    (   Dist = beta(A0, B0)
    ->  A is rational(A0), B is rational(B0), AB is A + B,
        rising(A, Tm, RA), rising(B, Fm, RB), rising(AB, TFm, RAB), Stat = beta(RA, RB, RAB)
    ;   Dist = bernoulli(P0), P is rational(P0), Stat = bernoulli(P) ).

rising(X, N, V) :-
    findall(I, between(1, N, I), Is), foldl({X}/[I, [R|Rs], [R1, R|Rs]]>>(R1 is R * (X + I - 1)), Is, [1], Rev),
    reverse(Rev, L), V =.. [r|L].

power(beta(RA, RB, RAB), T, F, X) :-
    T1 is T + 1, F1 is F + 1, TF is T + F + 1,
    arg(T1, RA, A), arg(F1, RB, B), arg(TF, RAB, C), X is A * B rdiv C.
power(bernoulli(P), T, F, X) :- ( T > 0, F > 0 -> X = 0 ; T > 0 -> X = P ; F > 0 -> X is 1 - P ; X = 1 ).

% Terms as signed monomials; equal monomials are collected. Points fold into
% coefficients, so only an expression's complement adds a monomial.
polynomial(Dists, Terms, Poly) :-
    findall(Key-C,
            ( member(t(C0, Lits, _), Terms), R is rational(C0),
              foldl(expand_literal(Dists), Lits, [[]-R], Expanded), member(Key-C, Expanded) ), Pairs),
    collected(Pairs, P0),
    findall(Id, ( gen_assoc(Id, Dists, Dist), Dist \= point(_) ), Ids),
    foldl(complements, Ids, P0, Poly).

collected(Pairs, Poly) :-
    keysort(Pairs, Sorted), group_pairs_by_key(Sorted, Groups),
    findall(Key-C, (member(Key-Cs, Groups), sum_list(Cs, C), C =\= 0), Poly).

% theta + (1-theta) = 1: monomials alike but for one more theta against one
% more 1-theta of parameter Id, at one coefficient, are one monomial. So
% independent parameters stay factored: a full partition of them is one term.
complements(Id, P0, P) :-
    maplist({Id}/[K-C, (R-C)-E]>>( selectchk(Id-E, K, R) -> true ; E = c(0, 0), R = K ), P0, Split),
    keysort(Split, Sorted), group_pairs_by_key(Sorted, Groups),
    findall(K-C, ( member((R-C)-Es, Groups), complement_powers(Es, Ms), member(E, Ms),
                   ( E == c(0, 0) -> K = R ; monomial_product(R, [Id-E], K) ) ), P1),
    collected(P1, P).

complement_powers(Es, Ms) :-
    (   select(c(T1, F), Es, Rest), T1 > 0, T is T1 - 1, F1 is F + 1, selectchk(c(T, F1), Rest, Rest1)
    ->  complement_powers([c(T, F)|Rest1], Ms)
    ;   Ms = Es ).

expand_literal(Dists, w(Lits)-0, P0, P) :- !,
    literal_factor(Dists, w(Lits)-1, C, M),
    NC is -C, Complement is 1 - C,
    ( M == [] -> Factor = [[]-Complement] ; Factor = [[]-1, M-NC] ),
    findall(K-X, ( member(K0-X0, P0), member(K1-X1, Factor), monomial_product(K0, K1, K), X is X0 * X1 ), P).
expand_literal(Dists, Lit, P0, P) :-
    literal_factor(Dists, Lit, C, M),
    maplist({C, M}/[K0-X0, K-X]>>( monomial_product(K0, M, K), X is X0 * C ), P0, P).

% A literal that is one product: coefficient C times monomial M.
literal_factor(Dists, w(Lits)-1, C, M) :- !,
    foldl({Dists}/[L, C0-M0, C1-M1]>>( literal_factor(Dists, L, X, K), C1 is C0 * X, monomial_product(M0, K, M1) ),
          Lits, 1-[], C-M).
literal_factor(Dists, Id-Bit, C, M) :-
    get_assoc(Id, Dists, Dist),
    (   Dist = point(P0)
    ->  P is rational(P0), M = [], ( Bit =:= 1 -> C = P ; C is 1 - P )
    ;   C = 1, ( Bit =:= 1 -> M = [Id-c(1, 0)] ; M = [Id-c(0, 1)] ) ).

monomial_product([], B, B) :- !.
monomial_product(A, [], A) :- !.
monomial_product([I-c(T1, F1)|As], [J-c(T2, F2)|Bs], M) :-
    compare(Order, I, J),
    (   Order == (=) -> T is T1 + T2, F is F1 + F2, M = [I-c(T, F)|Ms], monomial_product(As, Bs, Ms)
    ;   Order == (<) -> M = [I-c(T1, F1)|Ms], monomial_product(As, [J-c(T2, F2)|Bs], Ms)
    ;   M = [J-c(T2, F2)|Ms], monomial_product([I-c(T1, F1)|As], Bs, Ms) ).

% E[AB] under the independent parameter laws: each product monomial is a
% product over its parameters of their power moments.
expectation(Stats, A, B, E) :-
    foldl({Stats, B}/[Ka-Ca, E0, E1]>>
          foldl({Stats, Ka, Ca}/[Kb-Cb, V0, V]>>
                ( monomial_product(Ka, Kb, K),
                  foldl({Stats}/[Id-c(T, F), W0, W]>>( get_assoc(Id, Stats, S), power(S, T, F, X), W is W0 * X ),
                        K, Ca * Cb, Weight),
                  V is V0 + Weight ), B, E0, E1), A, 0, E).

% Forced goals have Q = 0 exactly, so variance 0.
event_node_answer(m(EN, EZ, EN2, ENZ, EZ2), a(S, V, Kind)) :-
    Center is EN rdiv EZ, S is float(Center), ZVar is EZ2 - EZ * EZ,
    Q is EN2 - 2 * Center * ENZ + Center * Center * EZ2,
    Bound is (Q + max(Center, 1 - Center) * sqrt(ZVar * Q)) / (EZ * EZ),
    V is float(min(Center * (1 - Center), Bound)),
    ( (ZVar =:= 0 ; Q =:= 0) -> Kind = exact ; Kind = conservative ).

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
