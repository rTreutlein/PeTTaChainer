:- use_module(library(http/json)).
:- initialization(main, main).
main(Files) :-
    findall(Row, (member(File, Files), setup_call_cleanup(open(File, read, S), terms(S, Rows), close(S)), member(Row, Rows)), All),
    json_write_dict(current_output, All), nl.
terms(S, Rows) :-
    read_term(S, T, [syntax_errors(error)]),
    ( T == end_of_file -> Rows=[]
    ; (T=(:- _) -> Rows=Rest
      ; (T=(H :- _) -> true ; H=T), functor(H,N,A),
        numbervars(T,0,_), term_string(T,Text,[quoted(true),numbervars(true)]),
        Rows=[_{name:N,arity:A,term:Text}|Rest]), terms(S,Rest)).
