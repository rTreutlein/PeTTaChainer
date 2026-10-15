:- use_module(library(prolog_wrap)).
:- dynamic branch_probe_exclusions/1, branch_probe_context/5.

% Retain the input E for an entry; its recorded cuts can be strictly smaller.
branch_probe_install :-
    retractall(branch_probe_context(_,_,_,_,_)),
    retractall(branch_probe_exclusions(_)),
    % Publication follows removal of the completed frame. Record the actual
    % frame's E there; Prolog wrapper cleanup can retain an outer call scope
    % until its choice points are discarded, beyond that frame's lifetime.
    wrap_predicate('remove-data-rows!'(Space,Pattern,_Removed), branch_probe_frame, Erase,
        ( ( Space == '&sk_branch_cuts', Pattern=[Frame,_,_], integer(Frame),
            once('&sk_branch_cuts'(Frame,E,_)) ->
                retractall(branch_probe_exclusions(_)), assertz(branch_probe_exclusions(E))
          ; true ), call(Erase) )),
    wrap_predicate('sk-cache-branch!'(S,_H,K,R,_Rule,_Inputs,_Cuts,Fresh,_V,Stored),
        branch_probe_publish, Publish,
        ( call(Publish),
          ( Fresh == true, branch_probe_exclusions(E) ->
              assertz(branch_probe_context(S,K,R,E,Stored))
          ; true ) )).

branch_probe_invalid(Rows) :-
    findall([K,E,Cuts,V],
        ( branch_probe_context(S,K,R,E,V), '&sk_branch'(S,K,R,Cuts,true,V),
          'sk-view-deps-step'(0,V,Deps), 'deps-meet?'(E,Deps,true) ), Rows).
