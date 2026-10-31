:- use_module(library(prolog_wrap)).

execution_scope_probe_install(Mode) :-
    wrap_predicate('sk-evaluate!'(_Done), execution_scope_probe, Wrapped,
      (context_active(_) -> (Mode == throw -> throw(error(execution_scope_probe, test)) ; fail)
      ; call(Wrapped))).

execution_scope_probe_clear :-
    unwrap_predicate('sk-evaluate!'(_), execution_scope_probe).

execution_scope_probe_closed :-
    \+ context_active(_),
    \+ context_scope(_,_), \+ context_root(_,_,_,_), \+ context_seed(_,_,_),
    \+ context_entry(_,_,_,_,_), \+ context_hidden(_,_,_,_,_),
    \+ catch('&temp_query_ref'(clause_ref,_),error(existence_error(procedure,_),_),fail),
    \+ catch('&sk_branch_cuts'(_,_,_),error(existence_error(procedure,_),_),fail),
    'search-id-value'(sk_branch_at,0).
