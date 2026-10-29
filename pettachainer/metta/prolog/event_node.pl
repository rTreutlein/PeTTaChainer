% Event-node semantics and numerical contracts: docs/metta/event_node_contract.md.
:- module(event_node, [event_node_dist/5, event_node_moments/4, event_node_coupling/5, event_node_widen/6, dist_rule/3, dist_mean/2]).
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

event_node_moments(Vars, Terms0, Goals, Answers) :-
    foldl([t(C, _, _), M0, M]>>(M is max(M0, abs(C))), Terms0, 0.0, Scale),
    (   Scale =:= 0.0
    ->  Answers = inconsistent
    ;   maplist(scaled_term(Scale), Terms0, Terms),
        pairs_keys_values(Vars, Ids, Dists),
        maplist(dist_mean, Dists, Means),
        pairs_keys_values(MuPairs, Ids, Means), list_to_assoc(MuPairs, Mu),
        forms(Terms, Goals, Mu, Z0, N0),
        (   Z0 =< 0.0
        ->  Answers = inconsistent
        ;   maplist(ratio(Z0), N0, Ss),
            maplist(square_ratio(Z0), N0, H0),
            exclude([_-D]>>(D = point(_)), Vars, Free),
            (   exact_second_moments(Free, Terms, Goals, Mu, H0, Exact)
            ->  (   Exact == bound
                ->  maplist(bound_answer, Ss, Answers)
                ;   maplist(exact_answer(Z0), Ss, Exact, Answers) )
            ;   maplist(one_dimension(Terms, Goals, Mu, Z0, N0, H0), Free, Dims),
                first_order(Dims, Terms, Goals, Mu, H0, Hdmr),
                polynomial_moments(Free, Terms, Goals, Mu, Poly),
                length(Goals, G), numlist(1, G, Is),
                maplist(goal_answer(Z0, Ss, Hdmr, Poly), Is, Answers) ) ) ).

exact_answer(Z0, S, E, a(S, V, exact)) :- V is max(0.0, E / Z0 - S * S).

exact_second_moments(Free, Terms, Goals, Mu, H0, Exact) :-
    tensor_moments(17, Free, Terms, Goals, Mu, Size17, E17),
    ( Size17 =< 5000
    -> tensor_moments(9, Free, Terms, Goals, Mu, _, E9),
       refined_moments(17, E9, E17, Free, Terms, Goals, Mu, H0, Exact)
    ; tensor_moments(9, Free, Terms, Goals, Mu, Size9, E9), Size9 =< 70000,
      tensor_moments(5, Free, Terms, Goals, Mu, _, E5),
      ( agree_moments(H0, E5, E9) -> Exact = E9
      ; tensor_moments(15, Free, Terms, Goals, Mu, Size15, E15), Size15 =< 70000,
        refined_moments(15, E9, E15, Free, Terms, Goals, Mu, H0, Exact) ) ).

refined_moments(N, Ecoarse, Efine, Free, Terms, Goals, Mu, H0, Exact) :-
    (   agree_moments(H0, Ecoarse, Efine) -> Exact = Efine
    ;   N1 is 2 * N - 1, N1 =< 257,
        catch(tensor_moments(N1, Free, Terms, Goals, Mu, Size, E1), error(evaluation_error(_), _), fail),
        Size =< 70000
    ->  refined_moments(N1, Efine, E1, Free, Terms, Goals, Mu, H0, Exact)
    ;   Exact = bound ).

tensor_moments(N, Free, Terms, Goals, Mu, Size, E) :-
    length(Free, Count), maplist(axis_rule(N, Count), Free, Axes),
    foldl([_-rule(Xs, _), P0, P]>>(length(Xs, L), P is P0 * L), Axes, 1, Size),
    (   Size =< 70000
    ->  zeros(Goals, Zero), tensor(Axes, Mu, 1.0, Terms, Goals, h, Zero, E)
    ;   E = none ).

axis_rule(N, Count, Id-D, Id-Rule) :-
    ( Count > 3, D = beta(A, B), min(A, B) > 10, A + B > 1000 -> Nodes is max(2, (N + 7) // 8) ; Nodes = N ),
    dist_rule(D, Nodes, Rule).

agree_moments(H0, Ea, Eb) :-
    maplist([E, H, C]>>(C is E - H), Ea, H0, Ca),
    maplist([E, H, C]>>(C is E - H), Eb, H0, Cb),
    agree(H0, Ca, Cb).

scaled_term(Scale, t(C0, Lits, Gs), t(C, Lits, Gs)) :- C is C0 / Scale.
ratio(Z, N, S) :- S is N / Z.
square_ratio(Z, N, H) :- H is N * N / Z.

dist_mean(point(X), X).
dist_mean(bernoulli(M), M).
dist_mean(beta(A, B), M) :- M is A / (A + B).

% A distribution's n-point rule (Bernoulli's two points are exact for any n).
dist_rule(beta(A, B), N, rule(Xs, Ws)) :- gauss_jacobi(A, B, N, Xs, Ws).
dist_rule(bernoulli(M), _, rule([0.0, 1.0], [W0, M])) :- W0 is 1 - M.

% Z and each goal's N at the parameters Theta (an assoc).
forms(Terms, Goals, Theta, Z, Ns) :-
    zeros(Goals, Zero),
    foldl(add_term(Goals, Theta), Terms, 0.0-Zero, Z-Ns).

zeros(List, Zeros) :- maplist([_, 0.0]>>true, List, Zeros).

add_term(Goals, Theta, t(Coef, Lits, Gs), Z0-N0, Z-N) :-
    foldl(lit_value(Theta), Lits, Coef, W),
    Z is Z0 + W,
    maplist(add_goal(Gs, W), Goals, N0, N).

add_goal(Gs, W, Goal, N0, N) :- ( memberchk(Goal, Gs) -> N is N0 + W ; N = N0 ).

lit_value(Theta, Id-Bit, P0, P) :-
    get_assoc(Id, Theta, X),
    ( Bit =:= 1 -> P is P0 * X ; P is P0 * (1 - X) ).

goal_answer(Z0, Ss, Hdmr, Poly, I, Answer) :-
    nth1(I, Ss, S),
    (   Poly = m(EZ2, EN2s, EN2Zs), ZVar is EZ2 - Z0 * Z0, nth1(I, EN2s, EN2), nth1(I, EN2Zs, EN2Z)
    ->  (   ZVar =< 1.0e-12 * Z0 * Z0
        ->  V is max(0.0, EN2 / (Z0 * Z0) - S * S), Answer = a(S, V, exact)
        ;   Hdmr \== bound,
            nth1(I, Hdmr, EH),
            ER is EN2 / Z0 - (EN2Z - EN2 * Z0) / Z0 ** 2 + EN2 * ZVar / Z0 ** 3,
            VH is max(0.0, EH / Z0 - S * S), VR is max(0.0, ER / Z0 - S * S),
            Hi is max(VH, VR), Lo is min(VH, VR),
            Hi =< 2 * Lo + 1.0e-15,
            Hi > (abs(EN2Z - EN2 * Z0) / Z0 ** 2 + EN2 * ZVar / Z0 ** 3) / Z0 * sqrt(ZVar) / Z0
        ->  Answer = a(S, Hi, exact)
        ;   bound_answer(S, Answer) )
    ;   bound_answer(S, Answer) ).

bound_answer(S, a(S, V, bound)) :- V is S * (1 - S).

one_dimension(Terms, Goals, Mu, Z0, N0, H0, Id-Dist, dim(Id, Rule, Contrib, R, Resolved)) :-
    rule_contributions(9, Dist, Id, Terms, Goals, Mu, Z0, N0, H0, d(_, C9, _)),
    rule_contributions(17, Dist, Id, Terms, Goals, Mu, Z0, N0, H0, d(R17, C17, Rel17)),
    (   agree(H0, C9, C17) -> Rule = R17, Contrib = C17, R = Rel17, Resolved = true
    ;   rule_contributions(33, Dist, Id, Terms, Goals, Mu, Z0, N0, H0, d(Rule, Contrib, R)),
        ( agree(H0, C17, Contrib) -> Resolved = true ; Resolved = false ) ).

rule_contributions(N, Dist, Id, Terms, Goals, Mu, Z0, N0, H0, d(Rule, Contrib, R)) :-
    dist_rule(Dist, N, Rule), Rule = rule(Xs, Ws),
    zeros(Goals, Zero),
    foldl(rule_point(Id, Mu, Terms, Goals), Xs, Ws, Zero-[0.0|Zero], EH-Squares),
    maplist([E, H, Cg]>>(Cg is E - H), EH, H0, Contrib),
    foldl([F0, Sq, R0, R1]>>( F0 =:= 0.0 -> R1 = R0 ; R1 is max(R0, Sq / F0 ** 2 - 1) ), [Z0|N0], Squares, 0.0, R).

rule_point(Id, Mu, Terms, Goals, X, W, E0-Q0, E-Q) :-
    put_assoc(Id, Mu, X, Theta), forms(Terms, Goals, Theta, Z, Ns),
    maplist(add_weighted_square_ratio(W, Z), Ns, E0, E),
    maplist(add_weighted_square(W), [Z|Ns], Q0, Q).

% A point with Z = 0 (Bernoulli parameters at an endpoint) adds nothing: N =< Z there.
add_weighted_square_ratio(W, Z, N, E0, E) :- ( Z > 0.0 -> E is E0 + W * N * N / Z ; E = E0 ).
add_weighted_square(W, F, Q0, Q) :- Q is Q0 + W * F * F.
add_weighted_square_times(W, Z, N, Q0, Q) :- Q is Q0 + W * N * N * Z.

% Two rules agree on a contribution within 1 %, or within 1e-12 of h_g(mu) itself
% (a parameter that barely moves the goal leaves only rounding).
agree(H0, C1, C2) :- maplist([H, A, B]>>(abs(A - B) =< 0.01 * abs(B) + 1.0e-12 * abs(H)), H0, C1, C2).

first_order(Dims, Terms, Goals, Mu, H0, Hdmr) :-
    partition([dim(_, _, _, R, _)]>>(R > 0.05), Dims, Wide, Narrow),
    foldl([dim(_, rule(Xs, _), _, _, _), P0, P]>>(length(Xs, L), P is P0 * L), Wide, 1, Evaluations),
    foldl([dim(_, _, _, R, _), P0, P]>>(P is P0 * (1 + R)), Dims, 1.0, All),
    foldl([dim(_, _, _, R, _), P0, P]>>(P is P0 * (1 + R)), Wide, 1.0, WideAll),
    foldl([dim(_, _, _, R, _), S0, S]>>(S is S0 + R), Narrow, 0.0, NarrowSum),
    Captured is NarrowSum + WideAll - 1,
    (   memberchk(dim(_, _, _, _, false), Dims) -> Hdmr = bound
    ;   length(Wide, NW), NW > 3 -> Hdmr = bound
    ;   Evaluations > 5000 -> Hdmr = bound
    ;   Captured > 0.0, (All - 1) / Captured > 1.1 -> Hdmr = bound
    ;   (   Wide == [] -> Block = H0
        ;   maplist([dim(Id, Rule, _, _, _), Id-Rule]>>true, Wide, Axes),
            zeros(Goals, Zero), tensor(Axes, Mu, 1.0, Terms, Goals, h, Zero, Block) ),
        foldl([dim(_, _, C, _, _), E0, E]>>maplist([Ei0, Ci, Ei]>>(Ei is Ei0 + Ci), E0, C, E), Narrow, Block, Hdmr) ).

polynomial_moments(Free, Terms, Goals, Mu, Poly) :-
    (   length(Free, K), K > 12
    ->  Poly = none
    ;   maplist([Id-D, Id-Rule]>>dist_rule(D, 2, Rule), Free, Axes),
        zeros(Goals, Zero),
        tensor(Axes, Mu, 1.0, Terms, Goals, poly, m(0.0, Zero, Zero), Poly) ).

% A tensor rule over Axes (Id-rule pairs), the other parameters at Theta,
% accumulating h (E[N_g^2/Z]) or poly (the moments above) at each point.
tensor([], Theta, W, Terms, Goals, Kind, A0, A) :-
    forms(Terms, Goals, Theta, Z, Ns),
    accumulate(Kind, W, Z, Ns, A0, A).
tensor([Id-rule(Xs, Ws)|Axes], Theta, W0, Terms, Goals, Kind, A0, A) :-
    foldl(tensor_node(Id, Theta, W0, Axes, Terms, Goals, Kind), Xs, Ws, A0, A).

tensor_node(Id, Theta, W0, Axes, Terms, Goals, Kind, X, Wx, A0, A) :-
    put_assoc(Id, Theta, X, Th), W is W0 * Wx,
    tensor(Axes, Th, W, Terms, Goals, Kind, A0, A).

accumulate(h, W, Z, Ns, E0, E) :- maplist(add_weighted_square_ratio(W, Z), Ns, E0, E).
accumulate(poly, W, Z, Ns, m(Z2a, N2a, N2Za), m(Z2, N2, N2Z)) :-
    Z2 is Z2a + W * Z * Z,
    maplist(add_weighted_square(W), Ns, N2a, N2),
    maplist(add_weighted_square_times(W, Z), Ns, N2Za, N2Z).

gauss_jacobi(A, B, N, Xs, Ws) :-
    AB is A + B,
    D0 is (A - B) / AB,
    Last is N - 1,
    ( Last >= 1 -> numlist(1, Last, Ks) ; Ks = [] ),
    maplist(jacobi_diagonal(A, B), Ks, Ds),
    O0 is 4 * A * B / (AB ** 2 * (AB + 1)),
    ( Ks = [_|Ks2] -> true ; Ks2 = [] ),
    maplist(jacobi_off_diagonal(A, B), Ks2, Os),
    Diag = [D0|Ds],
    ( N > 1 -> maplist([O, E]>>(E is sqrt(O)), [O0|Os], Off) ; Off = [] ),
    gershgorin(Diag, Off, Lo, Hi),
    numlist(1, N, Js),
    maplist(eigenvalue(Diag, Off, Lo, Hi), Js, Ys),
    maplist(christoffel(Diag, Off), Ys, Ws0),
    sum_list(Ws0, WSum),
    maplist(ratio(WSum), Ws0, Ws),
    maplist([Y, X]>>(X is (1 + Y) / 2), Ys, Xs).

% The recurrence coefficients of Beta(a, b) in a and b (alpha = b - 1, beta = a - 1).
jacobi_diagonal(A, B, K, D) :- AB is A + B, S2 is 2 * K - 2 + AB, D is (A - B) * (AB - 2) / (S2 * (S2 + 2)).
jacobi_off_diagonal(A, B, K, O) :-
    AB is A + B, T is 2 * K - 2 + AB,
    O is 4 * K * (K - 1 + B) * (K - 1 + A) * (K - 2 + AB) / (T ** 2 * (T + 1) * (T - 1)).

gershgorin(Diag, Off, Lo, Hi) :-
    append([0.0], Off, Left), append(Off, [0.0], Right),
    foldl([D, L, R, Lo0-Hi0, Lo1-Hi1]>>(Lo1 is min(Lo0, D - abs(L) - abs(R)), Hi1 is max(Hi0, D + abs(L) + abs(R))),
          Diag, Left, Right, 1.0e300-(-1.0e300), Lo-Hi).

% The J-th smallest eigenvalue: the least x with at least J eigenvalues below it.
eigenvalue(Diag, Off, Lo, Hi, J, X) :-
    Mid is (Lo + Hi) / 2,
    (   ( Mid =< Lo ; Mid >= Hi ) -> X = Mid
    ;   below(Diag, Off, Mid, Count),
        ( Count >= J -> eigenvalue(Diag, Off, Lo, Mid, J, X) ; eigenvalue(Diag, Off, Mid, Hi, J, X) ) ).

% The number of eigenvalues below X: the negative pivots of the LDL' of J - X.
below([D0|Ds], Off, X, Count) :-
    P0 is D0 - X,
    foldl(pivot(X), Ds, Off, P0-0, PN-C0),
    ( PN < 0 -> Count is C0 + 1 ; Count = C0 ).

% A pivot too close to 0 is moved to +-1e-280, so that e^2 / pivot stays finite.
pivot(X, D, E, P1-C1, P2-C2) :-
    ( abs(P1) >= 1.0e-280 -> Q = P1 ; P1 < 0 -> Q = -1.0e-280 ; Q = 1.0e-280 ),
    P2 is D - X - E * E / Q,
    ( P1 < 0 -> C2 is C1 + 1 ; C2 = C1 ).

christoffel([D0|Ds], Off, X, W) :-
    (   Off == []
    ->  W = 1.0
    ;   Off = [E0|_],
        Q1 is (X - D0) / E0,
        christoffel_sum(Ds, Off, X, 1.0, Q1, 1.0, S),
        W is 1 / S ).

% sum of q_0^2..q_{n-1}^2 with q_{k+1} = ((x - d_k) q_k - e_{k-1} q_{k-1}) / e_k.
christoffel_sum([D|Ds], [Eprev, E|Es], X, Qprev, Q, S0, S) :- !,
    Qnext is ((X - D) * Q - Eprev * Qprev) / E,
    S1 is S0 + Q * Q,
    christoffel_sum(Ds, [E|Es], X, Q, Qnext, S1, S).
christoffel_sum([_], _, _, _, Q, S0, S) :- S is S0 + Q * Q.

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
