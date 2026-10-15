:- use_module(library(prolog_wrap)).
:- dynamic branch_probe_scope/1, branch_probe_context/5.

% Retain the input E for an entry; its recorded cuts can be strictly smaller.
branch_probe_install :-
    retractall(branch_probe_context(_,_,_,_,_)),
    wrap_predicate('sk-rebuild-view'(H,K,R,E,V), branch_probe_build, Wrapped,
        setup_call_cleanup(asserta(branch_probe_scope(E), Ref), call(Wrapped), erase(Ref))),
    wrap_predicate('sk-cache-branch!'(S,H,K,R,_Rule,_Inputs,_Cuts,Fresh,V,Stored),
        branch_probe_publish, Publish,
        ( call(Publish),
          ( Fresh == true, once(branch_probe_scope(E)) ->
              assertz(branch_probe_context(S,K,R,E,Stored))
          ; true ) )).

branch_probe_invalid(Rows) :-
    findall([K,E,Cuts,V],
        ( branch_probe_context(S,K,R,E,V), '&sk_branch'(S,K,R,Cuts,true,V),
          'sk-view-deps-step'(0,V,Deps), 'deps-meet?'(E,Deps,true) ), Rows).
