:- use_module(library(prolog_wrap)).
:- dynamic ctx_demand/3, ctx_class/3, ctx_count/2.

ctx_inc(Name) :- (retract(ctx_count(Name,N)) -> M is N+1 ; M=1), assertz(ctx_count(Name,M)).
ctx_set(Pattern) :- (call(Pattern) -> true ; assertz(Pattern)).

% Cumulative observations survive cache pruning. Row-view evaluations supply
% empty classes; every fresh branch publication supplies its recorded cuts.
% Raw E demand is a separate conservative envelope: it includes exclusions
% that never remove a proof, filtered rows, and conditioning-only reads.
ctx_install :-
    nb_setval(ctx_merge_depth,0),
    wrap_predicate('sk-value'(Key,_Filter,Exclude,_Result), ctx_census, Read,
      ( findall([Hash,Row,Exclude],
          ('index-hash'(Key,Hash),'&sk_latest'(Hash,Stored,['sk-version',_,Row,_]),Stored =@= Key), Demands),
        forall(member([DH,DR,DE],Demands),ctx_set(ctx_demand(DH,DR,DE))),call(Read) )),
    wrap_predicate('sk-row-view'(_Given,RE,RH,_RK,RR,_Row,_Value), ctx_census, Evaluate,
      ( call(Evaluate), (RE==[] -> ctx_set(ctx_class(RH,RR,[]));true) )),
    wrap_predicate('sk-cache-branch!'(_Slot,CH,_CK,CR,_Rule,_Inputs,Cuts,Fresh,_Computed,_Stored), ctx_census, Cache,
      ( (Fresh==true -> sort(Cuts,Canonical),ctx_set(ctx_class(CH,CR,Canonical));true),call(Cache) )),
    wrap_predicate('sk-merge-key'(_MH,_MK,_MF,ME,_MGiven,_Views,_Merged), ctx_census, Merge,
      ( nb_getval(ctx_merge_depth,Depth),
        (ME==[] -> call(Merge)
        ; ctx_inc(exclusion_merges), Next is Depth+1,
          setup_call_cleanup(nb_setval(ctx_merge_depth,Next),call(Merge),nb_setval(ctx_merge_depth,Depth)) ) )),
    wrap_predicate('sk-claim-charge!'(Given,Charged), ctx_census, Charge,
      ( call(Charge), (Given\=[],Charged==true,nb_getval(ctx_merge_depth,D),D>0 -> ctx_inc(exclusion_conditioned);true) )).

ctx_stats(Classes,Requests,Merges,Conditioned) :-
    findall([H,R,C],ctx_class(H,R,C),Classes),
    findall([H,R,E],ctx_demand(H,R,E),Requests),
    (ctx_count(exclusion_merges,Merges)->true;Merges=0),
    (ctx_count(exclusion_conditioned,Conditioned)->true;Conditioned=0).
