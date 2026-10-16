:- use_module(library(prolog_wrap)).
:- dynamic context_probe_count/1, context_probe_bad/1.

% Check while dependency handles and overlay proofs are live. Keep only a
% count and text diagnostics; the audit must not retain expired proof/deps IDs.
context_probe_install :-
    (current_predicate(context_probe_installed/0)->true
    ;assertz(context_probe_installed),assertz(context_probe_count(0)),
     wrap_predicate(cn_settled(Id,_Computed,_Cuts),context_probe,Publish,
       (cn_node(Id,_,[_,_,_,K,_,_,E,_,_,_,_]),call(Publish),
        cn_node(Id,_,[_,_,_,_,_,_,_,Cuts,D,V,true]),
        retract(context_probe_count(N)),Next is N+1,assertz(context_probe_count(Next)),
        ('deps-meet?'(E,D,true)->term_string([K,E,Cuts,V],Text),assertz(context_probe_bad(Text));true)))).

context_probe_invalid(Rows) :- findall(Text,context_probe_bad(Text),Rows).
