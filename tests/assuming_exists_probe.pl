% Capture witness values before the public query removes its overlay.
:- use_module(library(prolog_wrap)).
:- dynamic assuming_exists_probe_rows/1.

assuming_exists_probe_install :-
    wrap_predicate('context-finish!'(_,_,_,_,_), assuming_exists_probe, Wrapped,
      (call(Wrapped),
       findall([Type,TV],
         (context_entry(_,_, '&sk_latest',
            [_,['sk-key',Type,_],['sk-version',_,_,['sk-val',[_,_,_,TV],_,_]]],_),
          nonvar(Type), Type=['And'|_]), Rows),
       retractall(assuming_exists_probe_rows(_)),
       assertz(assuming_exists_probe_rows(Rows)))).

assuming_exists_probe_clear :-
    unwrap_predicate('context-finish!'(_,_,_,_,_), assuming_exists_probe),
    retractall(assuming_exists_probe_rows(_)).
