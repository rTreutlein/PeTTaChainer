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
