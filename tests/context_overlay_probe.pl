% Test-only capture at the lifetime boundary: runtime entries disappear after
% result externalization. Mutations below are deliberate negative controls.
:- use_module(library(prolog_wrap)).
:- dynamic overlay_probe_rows/1, overlay_probe_mutation/1, overlay_probe_seeds/1, overlay_probe_write/2.

overlay_probe_install(Mode) :-
    retractall(overlay_probe_mutation(_)), assertz(overlay_probe_mutation(Mode)),
    retractall(overlay_probe_write(_,_)),
    ( current_predicate(overlay_probe_installed/0) -> true
    ; assertz(overlay_probe_installed),
      % Wrappers can run in a specialization module; audit the physical MAIN
      % relations explicitly, and inject faults into those same relations.
      forall(context_store(Space,Arity,_),
        prolog_listen(user:Space/Arity,user:overlay_probe_physical_write(Space))),
      wrap_predicate('context-clear!'(_Done), overlay_probe, Wrapped,
        (findall(['query-scope',[Kb,C,'Nil'],Facts,_Inner,Proof,TV],
                 user:context_root(C,Kb,Facts,[Proof,TV]),Goals),
         user:overlay_probe_capture(Goals),call(Wrapped))),
      wrap_predicate('execution-allowances!'(_Units,_Backward,Done), overlay_probe, Allowance,
        ((overlay_probe_mutation(shared_budget),context_active(_)) -> Done=[] ; call(Allowance))),
      wrap_predicate('context-propagate?'(_Key,Result), overlay_probe, Propagate,
        ( (overlay_probe_mutation(never_propagate),context_active(_)) -> Result=false ; call(Propagate) )),
      wrap_predicate('context-add!'(Space,Row,Added), overlay_probe, Add,
        ( ((overlay_probe_mutation(write_main),memberchk(Space,['&sk_latest','&sk_merged'])
            ;overlay_probe_mutation(write_main_rate), Space='&base_rate_cache'
            ;overlay_probe_mutation(write_main_tally), Space='&sk_instance_tally'
            ;overlay_probe_mutation(write_main_aggregate), Space='&forward_aggregate_state'),context_active(_))
          -> Head=..[Space|Row],assertz(user:Head),Added=true
          ; call(Add) )),
      wrap_predicate('sk-value'(ValueKey,_Filter,_Exclude,Value), overlay_probe, Read,
        (( overlay_probe_mutation(independent_main),context_active(C),
           ValueKey=['sk-key',['Shared'|_],Scope],
           \+ context_key_local(C,_,ValueKey),
           ValueKey=['sk-key',Shared,Scope], '&kb'(Shared,Scope,FactProof,TV)
         ) -> Value=['sk-val',[Shared,Scope,FactProof,TV],['ev-set',0],0]
           ; call(Read) )) ).


% Numeric caches and tallies deliberately carry no transitive proof. Observe
% their physical mutation boundary instead: independent cold work explicitly
% switches to MAIN; an active C must write only context_entry/context_hidden.
overlay_probe_physical_write(Space,Action,Ref) :-
    ( context_active(C), context_scope(C,Kb), memberchk(Action,[asserta,assertz,retract])
    -> clause(Head,_,Ref), overlay_probe_text([Space,Action,Head],Text),
       assertz(overlay_probe_write(Kb,Text))
    ; true ).

overlay_probe_text(Term,Text) :-
    copy_term_nat(Term,Copy),numbervars(Copy,0,_),term_string(Copy,Text,[quoted(true)]).

overlay_probe_capture(Goals) :-
    ( member(['query-scope'|_],Goals) -> overlay_probe_capture_context(Goals) ; true ).

overlay_probe_capture_context(Goals) :-
    ( overlay_probe_mutation(copy_history),
      member(['query-scope',[Kb,C,_]|_],Goals),
      '&sk_latest'(CopyHash,['sk-key',['History'|Args],[Kb,'MAIN','Nil']],Version)
    -> assertz(context_entry(CopyHash,C,'&sk_latest',[CopyHash,['sk-key',['History'|Args],[Kb,'MAIN','Nil']],Version],added))
    ; true ),
    findall(Hash,context_seed(Hash,_,_),Seeds),
    retractall(overlay_probe_seeds(_)),assertz(overlay_probe_seeds(Seeds)),
    findall([Space,Head,Text],
            (context_entry(_,_,Space,Row,_),
             (Row=[_,['sk-key',[H|_],_]|_],nonvar(H) -> Head=H ; Head=other),
             overlay_probe_text(Row,Text)),Rows),
    retractall(overlay_probe_rows(_)),assertz(overlay_probe_rows(Rows)).

overlay_probe_local(Rows) :- overlay_probe_rows(Rows).

overlay_probe_has_assumption(Proof) :-
    proof_dag_expand(Proof,Expanded),sub_term(Token,Expanded),ground(Token),Token=[ctx,proof|_],!.

overlay_probe_main_leaks(Kb,Leaks) :-
    findall(Text,
      (overlay_probe_write(Kb,Text)
      ; overlay_probe_provenance_leak(Kb,Text)),Leaks).

% The seed and its borrowed MAIN key have one identity. A dependency on that
% key is legitimate when MAIN already has its own independent fact or value;
% assumption proof tokens and scoped physical writes remain forbidden.
overlay_probe_provenance_leak(Kb,Text) :-
      ( ( '&sk_latest'(_,_,['sk-version',_,_,['sk-val',[_,[Kb,'MAIN','Nil'],P,_],_,D]])
        ; '&sk_merged'(_,_,_,['sk-val',[_,[Kb,'MAIN','Nil'],P,_],_,D],_)
        ; catch('&sk_view'(_,_,_,['sk-val',[_,[Kb,'MAIN','Nil'],P,_],_,D]),
                error(existence_error(procedure,_),_),fail)
        ; '&kb'(_,[Kb,'MAIN','Nil'],P,_)
        ; catch('&forward_aggregate_observation'(_,_,['forward-base-rate-observation-value',[_,[Kb,'MAIN','Nil'],P,_]],_,_,_),
                error(existence_error(procedure,_),_),fail) ),
        (overlay_probe_has_assumption(P)
        ; nonvar(D),overlay_probe_seeds(Seeds),member(H,Seeds),
          \+ ('&sk_latest'(H,_,['sk-version',_,_,Main]),Main\=='sk-none'),
          \+ ('&sk_keys'(H,['sk-key',Type,Scope]),'&kb'(Type,Scope,_,_)),
          'deps-has?'(D,H,true)),
        overlay_probe_text([P,D],Text) ).

% A dominated alternative matters to a reader excluding the dominant view.
overlay_probe_filtered_change(Kb,Result) :-
    Key=['sk-key',['FilteredProbe',x],[Kb,'MAIN','Nil']],
    'index-hash'(Key,H), 'index-hash'(['sk-key',['Reader',x],[Kb,'MAIN','Nil']],Target),
    'index-hash'(['sk-key',['Action',x],[Kb,'MAIN','Nil']],Action),
    'evidence-set'([a,b],EV1),'evidence-set'([a],EV2),
    'deps-key'(Target,D1),'deps-key'(Action,D2),
    Main=['sk-val',[['FilteredProbe',x],[Kb,'MAIN','Nil'],dominant,['STV',0.5,0.8]],EV1,D1],
    Local=['sk-val',[['FilteredProbe',x],[Kb,'MAIN','Nil'],alternative,['STV',0.5,0.4]],EV2,D2],
    C=filtered_probe,
    setup_call_cleanup(
      (assertz('&sk_latest'(H,Key,['sk-version',0,1,Main]),Ref),
       assertz(context_entry(H,C,'&sk_latest',[H,Key,['sk-version',1,2,Local]],added)),nb_setval(context_overlay,C)),
      once(('sk-value'(Key,'sk-any-filter',[],Merged),
            'sk-value'(Key,'sk-any-filter',[Target],Filtered),
            'context-propagate?'(Key,Propagate),
            Result=_{merged:Merged,main:Main,filtered:Filtered,propagate:Propagate})),
      (nb_setval(context_overlay,main),erase(Ref),'sk-drop-merged!'(Key,_),'context-clear!'(_))).

% Shared MAIN searches can have open and proof-constrained nodes for one key.
% Node hashes deliberately omit proof/TV constraints; erase the selected index
% clause rather than leaving retract/1 alternatives for the other node.
overlay_probe_retire_shared(Kb,Count,Left) :-
    sk_search_init,
    Scope=[Kb,'MAIN','Nil'],Key=[['RetireOverlayProbe',x],Scope],
    term_hash(Key,H),
    N1=[['RetireOverlayProbe',x],Scope,_,_],
    N2=[['RetireOverlayProbe',x],Scope,known,_],
    'sk-node-hash'(N1,NH),'sk-node-hash'(N2,NH),
    setup_call_cleanup(
      (assertz(sk_search_node(H,Key,NH,N1)),assertz(sk_search_node(H,Key,NH,N2)),
       assertz(sk_retire_queue(H,Key))),
      (findall(done,'sk-retire-searches!'(true),Results),length(Results,Count),
       aggregate_all(count,sk_search_node(H,Key,_,_),Left)),
      (retractall(sk_search_node(H,Key,_,_)),retractall(sk_retire_queue(H,Key)))).
