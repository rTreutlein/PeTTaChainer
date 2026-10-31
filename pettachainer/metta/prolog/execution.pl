% The MeTTa executor supplies both operations. Preserve exceptions and run
% cleanup on success, failure and pruning, without reduce/2 swallowing errors.
'execution-finally'(Work, Cleanup, Result) :-
    setup_call_cleanup(true, once(apply_fn1(Work,[],Result)),
                       once(apply_fn1(Cleanup,[],_))).

% Nonbinding result-pattern compatibility at the scope boundary.
'terms-unifiable?'(Left,Right,Result) :-
    (\+ \+ (Left=Right) -> Result=true ; Result=false).

% Register the executor's cross-module contracts before its mutually recursive
% clients compile. Native declarations alone do not register input arities.
'execution-declare!'(Mode, Entries, true) :-
    forall(member([Name|Types],Entries),
           (length(Types,Arity),(arity(Name,Arity) -> true ; assertz(arity(Name,Arity))))),
    'declare-natives!'(Mode,Entries,true).
