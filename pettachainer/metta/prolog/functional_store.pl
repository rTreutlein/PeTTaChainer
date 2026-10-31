% Immutable input declarations and assigned-key lookups.
:- dynamic functional_predicate/4, functional_value/3.
% Shared immutable input-key lookup, used by ingestion and search retirement.
functional_key(Type, Context, Key) :-
    nonvar(Type), Type = [Head|Args], nonvar(Head),
    ground(Context), Context = [Kb,'MAIN','Nil'], functional_predicate(Head, Kb, Arity, Positions),
    length(Args, Arity), maplist(functional_arg(Args), Positions, Values),
    ground(Values), Key = functional(Kb, Head, Values).
functional_arg(Args, Position, Value) :- nth1(Position, Args, Value).

'sk-functional-conflict?'([Type,Context|_], Conflict) :-
    ( functional_key(Type, Context, Key), term_hash(Key, Hash),
      functional_value(Hash, Key, Stored), \+ unifiable(Type, Stored, _)
    -> Conflict = true ; Conflict = false ).

