:- use_module(library(http/json)).
:- initialization(main, main).
main(Files) :- findall(Row, (member(File, Files), setup_call_cleanup(open(File, read, S), rows(S, File, Rows), close(S)), member(Row, Rows)), All), json_write_dict(current_output, All), nl.
rows(S, F, Rows) :- read_term(S, T, [syntax_errors(error)]), (T == end_of_file -> Rows = [] ; (row(T, F, R) -> Rows = [R|Rest] ; Rows = Rest), rows(S, F, Rest)).
row((H :- B), F, _{file:F, name:N, refs:Refs}) :- !, callable(H), functor(H,N,_), findall(R, calls(B,R), R0), sort(R0,Refs).
row(H, F, _{file:F, name:N, refs:[]}) :- callable(H), functor(H,N,_), N \= (:-), N \= (-->) .
calls(T, _) :- var(T), !, fail.
calls((A,B), R) :- !, (calls(A,R); calls(B,R)).
calls((A;B), R) :- !, (calls(A,R); calls(B,R)).
calls((A->B), R) :- !, (calls(A,R); calls(B,R)).
calls((A*->B), R) :- !, (calls(A,R); calls(B,R)).
calls(\+ A, R) :- !, calls(A,R).
calls(_:A, R) :- !, calls(A,R).
calls(T, R) :- callable(T), functor(T,N,_), (R=N ; meta_position(N, I), arg(I,T,A), calls(A,R)).
meta_position(N, 1) :- memberchk(N, [maplist,include,exclude,partition,foldl,foldr,call,once,ignore,catch,forall,setup_call_cleanup,call_cleanup]).
meta_position(N, 2) :- memberchk(N, [findall,bagof,setof,forall,setup_call_cleanup,call_cleanup,aggregate_all,>>]).
meta_position(N, 3) :- memberchk(N, [catch,setup_call_cleanup]).
