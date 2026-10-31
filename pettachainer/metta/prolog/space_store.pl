% Raw row writes and scalar state. Overlay routing is the write boundary.
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

% A counter's value (change-state!), 0 before it is set.
'search-id-value'(Key, Value) :- ( nb_current(Key, Stored) -> Value = Stored ; Value = 0 ).

