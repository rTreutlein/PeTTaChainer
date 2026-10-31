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
