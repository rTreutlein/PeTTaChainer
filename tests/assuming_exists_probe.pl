% Capture witness values before the public query removes its overlay.
:- use_module(library(prolog_wrap)).
:- dynamic assuming_exists_probe_rows/1.

assuming_exists_probe_install :-
    wrap_predicate('context-clear!'(_), assuming_exists_probe, Wrapped,
      (findall([Type,TV],
         (user:context_entry(_,_, '&sk_latest',
            [_,['sk-key',Type,_],['sk-version',_,_,['sk-val',[_,_,_,TV],_,_]]],_),
          nonvar(Type), Type=['And'|_]), Rows),
       retractall(user:assuming_exists_probe_rows(_)),
       assertz(user:assuming_exists_probe_rows(Rows)), call(Wrapped))).

assuming_exists_probe_clear :-
    unwrap_predicate('context-clear!'(_), assuming_exists_probe),
    retractall(user:assuming_exists_probe_rows(_)).
