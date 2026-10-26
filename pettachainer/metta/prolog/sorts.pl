% Sorts (docs/metta/API.md, "Sorts"). A head's argument positions may be
% declared Stage, Time, Object, Concept or Value, and a constant gets the
% sort of each declared position an ingested source states it at, or a
% declared one. A statement with a Stage or Time argument is a stage: its
% inversions and completions get evidence from below only (#122). Object and
% Concept only exclude a constant from being a stage (D2); Value positions
% sort nothing. A KB that declares no sorts and no time has no stages: the
% declarations set sorted_kb, and nothing is walked without it.
:- dynamic sorted_kb/1, argument_sort/4, constant_sort/3, time_layer/4, stage_position/3.

'sorted-kb!'(KB, true) :- ( sorted_kb(KB) -> true ; assertz(sorted_kb(KB)) ).

'set-argument-sorts'(KB, Head, Sorts, true) :-
    'declared-head!'(Head, true),
    (   is_list(Sorts), Sorts \== [],
        forall(member(Sort, Sorts), memberchk(Sort, ['Stage','Time','Object','Concept','Value','Any']))
    ->  length(Sorts, Arity)
    ;   throw(error(domain_error(argument_sorts, [Head, Sorts]),
                    context(declaration/2, 'argument sorts are a list of Stage, Time, Object, Concept, Value or Any'))) ),
    (   time_layer(Head, KB, Position, _), \+ ( nth1(Position, Sorts, Sort), memberchk(Sort, ['Time','Any']) )
    ->  throw(error(domain_error(predicate_time, [Head, Position]),
                    context(declaration/2, 'the position set-predicate-time declares is Time')))
    ;   true ),
    (   source_head_arity(Head, KB, Other)
    ->  (   Other == Arity -> true
        ;   throw(error(domain_error(predicate_arity, [Head, Arity, Other]),
                        context(declaration/2, 'a predicate head takes one arity'))) )
    ;   assertz(source_head_arity(Head, KB, Arity)) ),
    'sorted-kb!'(KB, true),
    retractall(argument_sort(Head, KB, _, _)),
    forall(( nth1(Position, Sorts, Declared),
             ( time_layer(Head, KB, Position, _) -> Sort = 'Time' ; Sort = Declared ), Sort \== 'Any' ),
           assertz(argument_sort(Head, KB, Position, Sort))).

'set-constant-sort'(KB, Constant, Sort, true) :-
    (   atom(Constant), memberchk(Sort, ['Stage','Time','Object','Concept'])
    ->  'sorted-kb!'(KB, true), record_sorts(KB, [Constant-Sort]),
        forall(( memberchk(Sort, ['Stage', 'Time']), catch('&kb'(Type, [KB|_], _, _), error(existence_error(procedure, _), _), fail) ), note_stage_positions(KB, Type))
    ;   throw(error(domain_error(constant_sort, [Constant, Sort]),
                    context(declaration/2, 'a constant sort names a symbol and one of Stage, Time, Object or Concept'))) ).

% Head's facts refer to the time point at argument Position, which is
% Time, and have layer Layer within it (hypothesis mining). It commutes with
% set-argument-sorts: whichever comes first, the position stays Time, and
% one that gives it another sort, lies beyond the head's arity or moves the
% time to another position is rejected.
'set-predicate-time'(KB, Head, Position, Layer, true) :-
    'declared-head!'(Head, true),
    (   integer(Position), Position >= 1,
        \+ ( time_layer(Head, KB, Other, _), Other \== Position ),
        \+ ( argument_sort(Head, KB, Position, Sort), Sort \== 'Time' ),
        \+ ( source_head_arity(Head, KB, Arity), Position > Arity )
    ->  'sorted-kb!'(KB, true),
        ( argument_sort(Head, KB, Position, 'Time') -> true ; assertz(argument_sort(Head, KB, Position, 'Time')) ),
        retractall(time_layer(Head, KB, Position, _)),
        assertz(time_layer(Head, KB, Position, Layer))
    ;   throw(error(domain_error(predicate_time, [Head, Position]),
                    context(declaration/2, 'a predicate time is one Time position within the head\'s arity'))) ).

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
        record_sorts(KB, Pairs),
        note_stage_positions(KB, Statement)
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

% Whether a rule A -> B is stationary: no variable of it can bind a stage,
% so its rate never changes (rule-change hazard 0). A variable can bind a
% stage at a position declared Stage or Time, or at one where a constant of
% sort Stage or Time was stated (stage_position). A KB that declares no sorts
% has no stages, so every rule of it is stationary.
'stationary-rule?'(KB, A, B, Result) :-
    ( stationary_rule(KB, A, B) -> Result = true ; Result = false ).

stationary_rule(KB, A, B) :-
    \+ ( sorted_kb(KB), member(Side, [A, B]), source_atom(Side, [Head|Args]),
          nth1(Position, Args, Arg), var(Arg), stage_capable(Head, KB, Position) ).

stage_capable(Head, KB, Position) :-
    (   argument_sort(Head, KB, Position, Sort), memberchk(Sort, ['Stage', 'Time']) -> true
    ;   stage_position(Head, KB, Position) ).

% The positions where a Stage or Time constant was stated, as its sources are
% recorded (record-source-sorts!) or its sort is declared after them.
note_stage_positions(KB, Statement) :-
    forall(( source_atom(Statement, [Head|Args]), atom(Head), nth1(Position, Args, Arg), atom(Arg),
             constant_sort(Arg, KB, Sort), memberchk(Sort, ['Stage', 'Time']),
             \+ stage_position(Head, KB, Position) ),
           assertz(stage_position(Head, KB, Position))).

% Whether A -> B is a class link: (Sub X) -> (Super X), two classes of one
% variable.
'class-link?'(A, B, Result) :-
    (   nonvar(A), nonvar(B), A = [Sub, X], B = [Super, Y], atom(Sub), atom(Super), var(X), X == Y
    ->  Result = true ; Result = false ).

% Whether A -> B is an instance of a class link: (Sub T) -> (Super T) with T
% one variable or one constant, the link applied to it.
'class-link-instance?'(A, B, Result) :-
    (   nonvar(A), nonvar(B), A = [Sub, X], B = [Super, Y], atom(Sub), atom(Super), X == Y, ( var(X) ; atomic(X) )
    ->  Result = true ; Result = false ).
