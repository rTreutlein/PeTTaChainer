% The MeTTa executor supplies both operations. Preserve exceptions and run
% cleanup on success, failure and pruning, without reduce/2 swallowing errors.
'execution-finally'(Work, Cleanup, Result) :-
    setup_call_cleanup(true, once(apply_fn1(Work,[],Result)),
                       once(apply_fn1(Cleanup,[],_))).

% Register the executor's cross-module contracts before its mutually recursive
% clients compile. Native declarations alone do not register input arities.
'execution-declare!'(Mode, Entries, true) :-
    forall(member([Name|Types],Entries),
           (length(Types,Arity),(arity(Name,Arity) -> true ; assertz(arity(Name,Arity))))),
    'declare-natives!'(Mode,Entries,true).

% Register the table's direct native calls and feed its signatures through the
% ordinary PeTTa loader, preserving type checks and load-cache ownership.
'declare-natives!'(Mode, Entries, true) :-
    findall(Source,
            ( member(Entry, Entries),
              ( Entry = [Name|Types] -> swrite([:, Name, [Mode|Types]], Source)
              ; Name = Entry, Source = "" ),
              import_prolog_function(Name, true) ), Sources),
    atomics_to_string(Sources, "\n", Source),
    process_metta_string(Source, _, '&self').
