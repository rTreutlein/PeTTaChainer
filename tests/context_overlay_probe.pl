% Test-only capture at the lifetime boundary: runtime entries disappear after
% result externalization. Mutations below are deliberate negative controls.
:- use_module(library(prolog_wrap)).
:- dynamic overlay_probe_rows/1, overlay_probe_mutation/1, overlay_probe_seeds/1.

overlay_probe_install(Mode) :-
    retractall(overlay_probe_mutation(_)), assertz(overlay_probe_mutation(Mode)),
    ( current_predicate(overlay_probe_installed/0) -> true
    ; assertz(overlay_probe_installed),
      wrap_predicate('context-finish!'(Goals,_Bases,_Results), overlay_probe, Wrapped,
        (call(Wrapped), overlay_probe_capture(Goals))),
      wrap_predicate('context-propagate?'(_Key,Result), overlay_probe, Propagate,
        ( (overlay_probe_mutation(never_propagate),context_active(_)) -> Result=false ; call(Propagate) )),
      wrap_predicate('context-add!'(Space,Row,Added), overlay_probe, Add,
        ( (overlay_probe_mutation(write_main),context_active(_),memberchk(Space,['&sk_latest','&sk_merged']))
          -> Head=..[Space|Row],assertz(Head),Added=true
          ; call(Add) )),
      wrap_predicate('sk-value'(ValueKey,_Filter,_Exclude,Value), overlay_probe, Read,
        (( overlay_probe_mutation(independent_main),context_active(C),
           ValueKey=['sk-key',['Shared'|_],Scope],
           \+ context_key_local(C,_,ValueKey),
           ValueKey=['sk-key',Shared,Scope], '&kb'(Shared,Scope,FactProof,TV)
         ) -> Value=['sk-val',[Shared,Scope,FactProof,TV],['ev-set',0],0]
           ; call(Read) )) ).


overlay_probe_text(Term,Text) :-
    copy_term_nat(Term,Copy),numbervars(Copy,0,_),term_string(Copy,Text,[quoted(true)]).

overlay_probe_capture(Goals) :-
    ( member(['CPU','ContextQuery',_,_],Goals) -> overlay_probe_capture_context(Goals) ; true ).

overlay_probe_capture_context(Goals) :-
    ( overlay_probe_mutation(copy_history),
      member(['CPU','ContextQuery',[[Kb,C,_]|_],_],Goals),
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
      ( ( '&sk_latest'(_,_,['sk-version',_,_,['sk-val',[_,[Kb,'MAIN','Nil'],P,_],_,D]])
        ; '&sk_merged'(_,_,_,['sk-val',[_,[Kb,'MAIN','Nil'],P,_],_,D])
        ; catch('&sk_view'(_,_,_,['sk-val',[_,[Kb,'MAIN','Nil'],P,_],_,D]),
                error(existence_error(procedure,_),_),fail)
        ; '&kb'(_,[Kb,'MAIN','Nil'],P,_)
        ; catch('&forward_aggregate_observation'(_,_,['forward-base-rate-observation-value',[_,[Kb,'MAIN','Nil'],P,_]],_,_),
                error(existence_error(procedure,_),_),fail) ),
        (overlay_probe_has_assumption(P)
        ; nonvar(D),overlay_probe_seeds(Seeds),member(H,Seeds),'deps-has?'(D,H,true)),
        overlay_probe_text([P,D],Text) ),Leaks).
