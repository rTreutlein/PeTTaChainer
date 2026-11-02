% Feed the table's signatures through the ordinary PeTTa loader, preserving
% type checks and load-cache ownership, then register its direct native calls:
% an import recompiles earlier callers, which must see the signature.
'declare-natives!'(Mode, Entries, true) :-
    findall(Source,
            ( member(Entry, Entries),
              ( Entry = [Name|Types] -> swrite([:, Name, [Mode|Types]], Source) ; Source = "" ) ),
            Sources),
    atomics_to_string(Sources, "\n", Source),
    process_metta_string(Source, _, '&self'),
    forall(member(Entry, Entries),
           ( Entry = [Name|_] -> import_prolog_function(Name, true) ; import_prolog_function(Entry, true) )).

% Declare MeTTa functions defined later, so mutually recursive modules compile
% calls to them. Native declarations alone do not register input arities.
'declare-forward!'(Mode, Entries, true) :-
    forall(member([Name|Types],Entries),
           (length(Types,Arity),(arity(Name,Arity) -> true ; assertz(arity(Name,Arity))))),
    'declare-natives!'(Mode,Entries,true).

% Run Work, then Cleanup however Work ends. Errors propagate instead of being
% swallowed by reduce/2.
finally(Work, Cleanup, Result) :-
    setup_call_cleanup(true, once(apply_fn1(Work,[],Result)),
                       once(apply_fn1(Cleanup,[],_))).

% A host's call of a MeTTa function (pettachainer.py): Fn applied to the
% arguments each MeTTa source in Sources reads as, every result collected in
% order, as a runnable `!(Fn Args)` returns them. Arguments that are data,
% which a runnable passes as they are, are passed without compiling one; any
% other argument, such as a nested call or a lambda a runnable evaluates
% first, is compiled as a runnable. As text, a result is printed as MeTTa
% prints it; as terms, an expression arrives through janus as a list and a
% symbol or string as a str, and since janus passes no unbound variable each
% is named as MeTTa prints it.
metta_call(Fn, Sources, Results) :-
    atom_string(Name, Fn),
    foldl(metta_call_source(Name), Sources, Results, []).
metta_call_source(Name, Source, Results, Rest) :-
    format(string(Expression), "(~s)", [Source]),
    sread(Expression, Args),
    (   maplist(metta_data, Args)
    ->  append(Args, [Result], CallArgs),
        Goal =.. [Name|CallArgs],
        findall(Result, Goal, Results, Rest)
    ;   format(string(Code), "!(~w ~s)", [Name, Source]),
        process_metta_string(Code, Own),
        append(Own, Rest, Results)
    ).
% What a runnable passes unevaluated: a variable, a number, symbol or string,
% or an expression of such terms whose head names no function, special form
% or translator rule.
metta_data(Term) :- var(Term), !.
metta_data(Term) :- atomic(Term), !.
metta_data([Head|Args]) :-
    (   atom(Head)
    ->  \+ fun(Head), \+ translator_rule(Head), \+ special_builtin_form(Head, Args, _)
    ;   metta_data(Head)
    ),
    maplist(metta_data, Args).
metta_call_text(Fn, Sources, Texts) :-
    metta_call(Fn, Sources, Results),
    maplist(swrite, Results, Texts).
metta_call_terms(Fn, Sources, Results) :-
    metta_call(Fn, Sources, Results),
    term_variables(Results, Variables),
    foldl([Variable, N0, N]>>(format(atom(Variable), '$_~d', [N0]), N is N0 + 1),
          Variables, 0, _).
