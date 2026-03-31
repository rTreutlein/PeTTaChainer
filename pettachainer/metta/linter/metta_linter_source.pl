:- use_module(library(readutil)).

load_metta_source(File, Space, true) :-
    read_file_to_string(File, Source, []),
    string_codes(Source, Codes0),
    strip_lint_comments(Codes0, 0, Codes),
    phrase(lint_top_forms(Forms, 1), Codes),
    maplist(lint_parse_form, Forms, ParsedForms),
    maplist(add_source_form(Space), ParsedForms), !.

add_source_form(Space, parsed(Kind, Line, Term)) :-
    'add-atom'(Space, ['source-form', Line, Kind, Term], true), !.

lint_parse_form(form(Line, Source), parsed(function, Line, Term)) :-
    sread(Source, Term),
    Term = [=, [Fun|Args], _],
    atom(Fun),
    length(Args, _), !.
lint_parse_form(form(Line, Source), parsed(expression, Line, Term)) :-
    sread(Source, Term), !.
lint_parse_form(runnable(Line, Source), parsed(runnable, Line, Term)) :-
    sread(Source, Term), !.

lint_newlines(C0, C2) --> blanks_to_nl, !, { C1 is C0 + 1 }, lint_newlines(C1, C2).
lint_newlines(C, C) --> blanks.

lint_grab_until_balanced(D, Acc, Cs, LC0, LC2, InString) -->
    [C],
    { ( C = 0'" -> InString1 is 1 - InString ; InString1 = InString ),
      ( InString = 0
        -> ( C = 0'( -> D1 is D + 1
           ; C = 0') -> D1 is D - 1
           ; D1 = D )
        ; D1 = D ),
      Acc1 = [C|Acc],
      ( C = 10 -> LC1 is LC0 + 1 ; LC1 = LC0 ) },
    ( { D1 =:= 0, InString1 = 0 }
      -> { reverse(Acc1, Cs), LC2 = LC1 }
      ; lint_grab_until_balanced(D1, Acc1, Cs, LC1, LC2, InString1) ).

lint_top_forms([], _) --> blanks, eos.
lint_top_forms([Form|Forms], LC0) -->
    lint_newlines(LC0, LC1),
    ( "!" -> { Tag = runnable } ; { Tag = form } ),
    ( "(" -> []
    ; string_without("\n", Rest),
      { format(atom(Msg), "expected '(' or '!(', line ~w:~n~s", [LC1, Rest]),
        throw(error(syntax_error(Msg), none)) } ),
    ( lint_grab_until_balanced(1, [0'(], Codes, LC1, LC2, 0)
      -> { true }
      ; string_without("\n", Rest),
        { format(atom(Msg), "missing ')', starting at line ~w:~n~s", [LC1, Rest]),
          throw(error(syntax_error(Msg), none)) } ),
    { string_codes(Source, Codes), Form =.. [Tag, LC1, Source] },
    lint_top_forms(Forms, LC2).

strip_lint_comments([], _, []).
strip_lint_comments([0'"|Rest], 0, [0'"|Out]) :- !, strip_lint_comments(Rest, 1, Out).
strip_lint_comments([0'"|Rest], 1, [0'"|Out]) :- !, strip_lint_comments(Rest, 0, Out).
strip_lint_comments([0'\n|Rest], InString, [0'\n|Out]) :- !, strip_lint_comments(Rest, InString, Out).
strip_lint_comments([0';|Rest], 0, Out) :- !,
    append(_, [0'\n|Tail], Rest),
    strip_lint_comments(Tail, 0, Out).
strip_lint_comments([C|Rest], InString, [C|Out]) :-
    strip_lint_comments(Rest, InString, Out).
