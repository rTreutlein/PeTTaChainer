% Sorts (docs/metta/API.md, "Sorts"). A head's argument positions may be
% declared Stage, Time, Object, Concept or Value, and a constant gets the
% sort of each declared position an ingested source states it at, or a
% declared one. A statement with a Stage or Time argument is a stage: its
% inversions and completions get evidence from below only (#122). Object and
% Concept only exclude a constant from being a stage (D2); Value positions
% sort nothing. A KB that declares no sorts and no time has no stages: the
% declarations set sorted_kb, and nothing is walked without it.
:- dynamic sorted_kb/1, argument_sort/4, constant_sort/3.

'sorted-kb!'(KB, true) :- ( sorted_kb(KB) -> true ; assertz(sorted_kb(KB)) ).

'set-argument-sorts'(KB, Head, Sorts, true) :-
    'declared-head!'(Head, true),
    (   is_list(Sorts), Sorts \== [],
        forall(member(Sort, Sorts), memberchk(Sort, ['Stage','Time','Object','Concept','Value','Any']))
    ->  length(Sorts, Arity)
    ;   throw(error(domain_error(argument_sorts, [Head, Sorts]),
                    context(declaration/2, 'argument sorts are a list of Stage, Time, Object, Concept, Value or Any'))) ),
    (   source_head_arity(Head, KB, Other)
    ->  (   Other == Arity -> true
        ;   throw(error(domain_error(predicate_arity, [Head, Arity, Other]),
                        context(declaration/2, 'a predicate head takes one arity'))) )
    ;   assertz(source_head_arity(Head, KB, Arity)) ),
    'sorted-kb!'(KB, true),
    retractall(argument_sort(Head, KB, _, _)),
    forall(( nth1(Position, Sorts, Sort), Sort \== 'Any' ), assertz(argument_sort(Head, KB, Position, Sort))).

'set-constant-sort'(KB, Constant, Sort, true) :-
    (   atom(Constant), memberchk(Sort, ['Stage','Time','Object','Concept'])
    ->  'sorted-kb!'(KB, true), record_sorts(KB, [Constant-Sort])
    ;   throw(error(domain_error(constant_sort, [Constant, Sort]),
                    context(declaration/2, 'a constant sort names a symbol and one of Stage, Time, Object or Concept'))) ).

% Head's facts refer to the time point at argument Position, which is
% declared Time, and have layer Layer within it (hypothesis mining).
'set-predicate-time'(KB, Head, Position, Layer, true) :-
    'declared-head!'(Head, true),
    'sorted-kb!'(KB, true),
    retractall(argument_sort(Head, KB, Position, _)),
    assertz(argument_sort(Head, KB, Position, 'Time')),
    retractall(time_layer(Head, KB, _)),
    assertz(time_layer(Head, KB, Layer)).

% A source's constants take the sorts of their declared positions. A term
% that would be both a stage or time and an object or concept, across the
% source or against a constant's recorded sort, rejects the source before
% anything is recorded; a variable is checked within the source only.
% findall copies each solution: unifying each copy of the source with it
% gives the variables back their identity.
'record-source-sorts!'(KB, Statement, true) :-
    (   sorted_kb(KB)
    ->  findall(Statement-Pair, source_sort(KB, Statement, Pair), Found),
        pairs_keys_values(Found, Copies, Pairs),
        maplist(=(Statement), Copies),
        record_sorts(KB, Pairs)
    ;   true ).

record_sorts(KB, Pairs) :-
    forall(member(Term-Sort, Pairs),
           (   (   member(Other-OtherSort, Pairs), Other == Term
               ;   atom(Term), constant_sort(Term, KB, OtherSort) ),
               (   memberchk(Sort, ['Stage','Time'])
               ->  \+ memberchk(OtherSort, ['Stage','Time'])
               ;   memberchk(OtherSort, ['Stage','Time']) )
           ->  throw(error(domain_error(sort_conflict, [Term, OtherSort, Sort]),
                           context(sorts/2, 'a term is a stage or time, or an object or concept, never both')))
           ;   true )),
    forall(( member(Term-Sort, Pairs), atom(Term), \+ constant_sort(Term, KB, Sort) ),
           assertz(constant_sort(Term, KB, Sort))).

% The terms at declared positions of a canonical source's statements, with
% their positions' sorts. Arguments are data: nothing is read inside them.
source_sort(KB, Statement, Term-Sort) :-
    source_atom(Statement, [Head|Args]),
    argument_sort(Head, KB, Position, Sort), Sort \== 'Value',
    nth1(Position, Args, Term), ( var(Term) ; atom(Term) ).

% Whether a statement is a stage: a connective or existential claim with a
% stage part (#139), or an atom with a Stage or Time argument, by its
% position's declared sort, else by its constant's sort, else, for a
% variable, by its sort in `Sides`, the rule an inversion or completion
% instance comes from.
'stage-statement?'(KB, Statement, Sides, Stage) :-
    ( sorted_kb(KB), stage_statement(KB, Statement, Sides) -> Stage = true ; Stage = false ).

stage_statement(KB, Statement, Sides) :-
    nonvar(Statement), Statement = [Head|Args], atom(Head),
    (   ( memberchk(Head, ['And','Or','Not','ExistentialClaim']) ; 'compound-connective?'(Head, true) )
    ->  member(Part, Args), stage_statement(KB, Part, Sides)
    ;   nth1(Position, Args, Arg),
        (   argument_sort(Head, KB, Position, Sort) -> true
        ;   atom(Arg) -> constant_sort(Arg, KB, Sort)
        ;   var(Arg), member(Side, Sides), source_sort(KB, Side, Term-Sort), Term == Arg ),
        memberchk(Sort, ['Stage','Time']) ).
