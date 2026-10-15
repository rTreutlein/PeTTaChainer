% Assuming overlays share logical keys and search rows with MAIN. Only mutable
% evaluation entries live here; overlay writes never copy or mutate borrowed
% MAIN clauses. Independent cold reads perform ordinary MAIN maintenance.
:- dynamic context_root/4, context_rule/2, context_seed/3, context_scope/2, context_threshold/1.
:- dynamic context_entry/5, context_hidden/5, context_propagated/4.
:- dynamic '&sk_row'/4.
% Mutable settings must be runtime entries: a source-owned dynamic clause
% prevents PeTTa from recording and replaying the library load snapshot.
:- (context_threshold(_) -> true ; assertz(context_threshold(0.000001))).

'set-context-reuse-threshold'(Threshold, true) :-
    must_be(number, Threshold),
    ( Threshold >= 0 -> retractall(context_threshold(_)), assertz(context_threshold(Threshold))
    ; domain_error(not_less_than_zero, Threshold) ).

'context-create!'([Kb,C|_], true) :-
    ( context_scope(C,Kb) -> true ; assertz(context_scope(C,Kb)) ).

context_active(C) :- nb_current(context_overlay, C), C \== main.

% Reads are indexed first by the original store's scalar lookup key, then by
% context and space. The complete term checks collisions and open identities.
context_overlay_rows(C, Space, Row) :-
    ( Row = [Hash|_], context_entry(Hash, C, Space, Row, _)
    ; \+ context_local_only(Space),
      Goal =.. [Space|Row], call(Goal),
      \+ context_removed(C, Space, Row), context_borrowable(C,Space,Row) ).

context_borrowable(C,'&sk_latest',[H,Key,['sk-version',_,Rhash,_]]) :- !,
    \+ (context_entry(H,C,'&sk_latest',[H,Stored,['sk-version',_,Rhash,_]],_), Stored =@= Key).
context_borrowable(C,'&sk_merged',[H,Key,_,_]) :- !,
    \+ context_key_local(C,H,Key).
context_borrowable(_,_,_).
context_key_local(C,H,Key) :-
    ( context_seed(H,C,[Type,Scope,_,_]), Key =@= ['sk-key',Type,Scope]
    ; context_entry(H,C,'&sk_latest',[H,Stored,_],_), Stored =@= Key
    ; context_hidden(H,C,'&sk_latest',[H,Stored,_],_), Stored =@= Key ), !.

context_removed(C, Space, Row) :-
    Row = [Hash|_],
    ( context_hidden(Hash, C, Space, Pattern, Mode) ; context_hidden(all, C, Space, Pattern, Mode) ),
    ( Mode == variant -> Pattern =@= Row ; subsumes_term(Pattern, Row) ).

'context-add!'(Space, Row, true) :-
    ( context_active(C)
    -> Row = [Hash|_], assertz(context_entry(Hash, C, Space, Row, added))
    ; Head =.. [Space|Row], assertz(Head) ).

'context-remove!'(Space, Pattern, true) :-
    ( context_active(C)
    -> forall((clause(context_entry(_,C,Space,Row,_),true,Ref), Row = Pattern), erase(Ref)),
       ( Pattern=[Hash|_], ground(Hash) -> Index=Hash ; Index=all ),
       assertz(context_hidden(Index, C, Space, Pattern, removed))
    ; Head =.. [Space|Pattern], retractall(Head) ).

% Transient scheduling state starts empty. Durable values, aggregate tallies
% and per-reader compatibility history fall through to MAIN.
context_local_only('&sk_new').
context_local_only('&sk_dirty').
context_local_only('&sk_queued').
context_local_only('&sk_forced').
context_local_only('&sk_forced_used').
context_local_only('&sk_fold_pending').
context_local_only('&sk_refresh').
context_local_only('&sk_given_granted').
context_local_only('&sk_given_pending').
context_local_only('&sk_conditioning').
context_local_only('&sk_restale').
context_local_only('&sk_held').
context_local_only('&sk_instance_changed').
context_local_only('&sk_instance_checked').
context_local_only('&sk_branch_wanted').

context_store('&sk_latest',3).
context_store('&sk_view',4).
context_store('&sk_branch',6).
context_store('&sk_branch_owner',5).
context_store('&sk_branch_dirty',1).
context_store('&sk_branch_reader',3).
context_store('&sk_branch_wanted',5).
context_store('&sk_support',3).
context_store('&sk_merged',4).
context_store('&sk_reader',4).
context_store('&sk_stale_reader',4).
context_store('&sk_stale',2).
context_store('&sk_new',6).
context_store('&sk_dirty',2).
context_store('&sk_queued',3).
context_store('&sk_forced',3).
context_store('&sk_forced_used',3).
context_store('&sk_fold_pending',2).
context_store('&sk_partial',2).
context_store('&sk_given_pending',3).
context_store('&sk_given_granted',2).
context_store('&sk_conditioning',2).
context_store('&sk_cond_level',3).
context_store('&sk_refresh',2).
context_store('&sk_restale',2).
context_store('&sk_held',2).
context_store('&sk_instance_changed',2).
context_store('&sk_instance_checked',1).
context_store('&sk_instance_tally',3).
context_store('&sk_instance_member',6).
context_store('&sk_instance_regime',3).
context_store('&sk_instance_digest',2).
context_store('&sk_instance_sig',3).
context_store('&sk_instance_read',4).
context_store('&sk_rate_dirty',4).
context_store('&sk_rate_folds',2).
context_store('&sk_truth_factor',2).
context_store('&base_rate_cache',2).
context_store('&forward_aggregate_identity',2).
context_store('&forward_aggregate_interest_by_trigger',2).
context_store('&forward_aggregate_triggers',2).
context_store('&forward_aggregate_state',4).
context_store('&forward_aggregate_observation',5).
context_store('&forward_aggregate_fold',2).

% Separate read relations leave the ordinary physical MAIN stores inspectable
% by collectors and provenance audits. No runtime predicate is monkey-patched.
% MAIN is a direct indexed call, not a constructed meta-call. Empty stores
% are declared here so the direct call also fails cleanly before a first write.
% The load-cache prelude can consult this source twice; bootstrap each facade
% once, since compile_predicates makes it static.
:- forall(context_store(Space, Arity),
          ( dynamic(Space/Arity),
            atom_concat('&', Name, Space), atom_concat('&ctx_', Name, Read),
            ( current_predicate(Read/Arity) -> true
            ; functor(Head,Read,Arity), Head=..[_|Args], Main=..[Space|Args],
              assertz((Head :- (context_active(C) -> context_overlay_rows(C,Space,Args) ; Main))),
              compile_predicates([Read/Arity]) ) )).


% A cold read of an unchanged key is ordinary MAIN work. Test only actual
% local values of this key or its direct inputs; this is not reachability from
% an assumed head or a key. The indexed producer rows and fold member nodes
% are the same ones evaluation reads.
'context-cold-merged'(H,Key,Filter,Merged) :-
    ( context_active(C), \+ (context_key_local(C,H,Key); context_inputs_local(C,H,Key))
    -> setup_call_cleanup(nb_setval(context_overlay,main),
                          once('sk-merge-open!'(H,Key,Filter,Merged)),
                          nb_setval(context_overlay,C))
    ; 'sk-merge-open!'(H,Key,Filter,Merged) ).

context_inputs_local(C,H,Key) :-
    '&sk_row'(H,Stored,_,['sk-row',_,_,Premises,_]), Stored =@= Key,
    member(Premise,Premises), 'sk-direct-key-step'([],Premise,Keys),
    context_local_member(C,Keys), !.
context_inputs_local(C,_,['sk-fold',Args]) :-
    'sk-fold-node-member'(['CPU','FoldAllCompiled',Args,_],Nodes),
    member(Node,Nodes), 'sk-answers'(Node,Keys), context_local_member(C,Keys), !.
context_inputs_local(C,_,Key) :-
    Key=['sk-group',Args],
    'sk-group-members'(Key,Args,['sk-group-found',_,Keys]), context_local_member(C,Keys).

context_local_member(C,Keys) :-
    member(Key,Keys), 'index-hash'(Key,H), context_key_local(C,H,Key), !.

'context-searching?'(Kb, Result) :-
    ( context_root(_, Kb, _, _) -> Result=true ; Result=false ).

'context-rule-enabled?'(C, Result) :-
    ( context_active(C) -> Result=true ; Result=false ).

'context-rule-visible?'(Rule, Result) :-
    ( context_rule(Rule,C) -> ( context_active(C) -> Result=true ; Result=false )
    ; Result=true ).

% A query marker holds its ordinary compiled goal, retaining all of that
% goal's adapters. Its assumptions are still installed only in their private
% KB context. Search sees the canonical MAIN key, never an assumption TV.
'context-search-goal'(['CPU','ContextQuery',[Scope,Facts,Goal,Proof,TV],_], Main) :- !,
    'inference-clock'(Started),
    Scope=[Kb,C|_],
    assertz(context_root(C,Kb,Facts,[Proof,TV])), Main=Goal,
    forall((catch('&kb'(Type,[Kb,C,Vars],P,T),error(existence_error(procedure,_),_),fail),
            \+ (nonvar(P),P=['rule-axiom'|_])),
           (Key=['sk-key',Type,[Kb,'MAIN',Vars]], 'index-hash'(Key,H),
            assertz(context_seed(H,C,[Type,[Kb,'MAIN',Vars],P,T])),
            'sk-register-key!'(Key,_))),
    forall((context_rule(Id,C), catch(rules('runtime-rule-row',Id,Concl,Ps),error(existence_error(procedure,_),_),fail)),
           ( 'sk-activate-rule-row'(Id,[],['sk-rule-def',Concl,Ps],_) )),
    'inference-add!'(Started,_).
'context-search-goal'(Goal,Goal).

% An assumption can enable a dormant producer of an already-expanded MAIN
% node. Start those existing indexed templates structurally; no TV is supplied.
'context-start!'(true) :-
    forall(context_seed(_,_,[Type,Scope,_,_]),
           once('sk-forward-start!'(['sk-key',Type,Scope],_))).

'context-answer-seeds!'(Node, true) :-
    Node=[Type,[Kb,'MAIN',Vars],_,_], !,
    forall((context_seed(_,_,[Seed,[Kb,'MAIN',Vars],_,_]), \+ \+ (Type=Seed)),
           (copy_term_nat([Type,Seed], [T,S]), T=S,
            'sk-add-answer!'(Node,['sk-key',S,[Kb,'MAIN',Vars]],_))).
'context-answer-seeds!'(_,true).

'context-seeded?'(Type, Scope, Result) :-
    ( context_seed(_,_,[Seed,S,_,_]), \+ \+ (Type=Seed,Scope=S) -> Result=true ; Result=false ).

% Compiled assumptions' own rules are valid only in their context. Their
% canonical structural rows can be shared, but normal MAIN evaluation never
% applies them. Query adapters, whose proof has no assumption token, are
% ordinary MAIN work.
'context-addition'(['rules',[Premises,'|-',Conclusion]], ['rules',[MainPs,'|-',MainConcl]]) :- !,
    context_canonical(Conclusion,MainConcl), context_canonical(Premises,MainPs).
'context-addition'(Fact, Fact).

context_canonical(Term, Main) :-
    ( var(Term) -> Main=Term
    ; Term=[Kb,C,Vars], nonvar(C), context_scope(C,StoredKb), Kb==StoredKb
    -> Main=[Kb,'MAIN',Vars]
    ; is_list(Term) -> maplist(context_canonical,Term,Main)
    ; Main=Term ).

% An assumed implication is an input, not a MAIN rule axiom. Reading its
% canonical key keeps its structural row harmless in normal MAIN evaluation.
'context-rule-premises'(Concl, Premises, WithAssumption) :-
    ( Concl=[_,_,Proof,_], sub_term(Token,Proof), ground(Token), Token=[ctx,proof,C|_], context_scope(C,Kb),
      catch('&kb'(Type,[Kb,C,Vars],StoredProof,_TV),error(existence_error(procedure,_),_),fail),
      StoredProof =@= Token, nonvar(Type), Type=['Implication'|_]
    -> append(Premises,[['CPU','ContextRule',[['sk-key',Type,[Kb,'MAIN',Vars]],C],[]]],WithAssumption)
    ; WithAssumption=Premises ).

'context-note-rule!'(Id,Concl,true) :-
    ( Concl=[_,_,Proof,_], sub_term(Token,Proof), ground(Token), Token=[ctx,proof,C|_], context_scope(C,_)
    -> assertz(context_rule(Id,C)) ; true ).

'context-leaves'(Key, Leaves) :-
    ( context_active(C), Key=['sk-key',Type,Scope]
    -> 'index-hash'(Key,H),
       findall([Type,Scope,P,T], (context_seed(H,C,[S,K,P,T]), [S,K]=@=[Type,Scope]), Leaves)
    ; Leaves=[] ).

'context-finish!'(Allowance, Reserve, Goals, MainResults, Results) :-
    context_finish(Goals,MainResults,Allowance,Reserve,Results).
context_finish([],[],_,_,[]).
context_finish([Goal|Goals],[Base|Bases],Allowance,Reserve,[Result|Results]) :-
    ( Goal=['CPU','ContextQuery',[[Kb,C,_],Facts,Inner,WantProof,WantTV],_]
    -> setup_call_cleanup(nb_setval(context_overlay,C),
           once(('change-state!'(sk_eval_budget,Allowance,_),
                 'sk-branch-share'(BranchShare), BranchBudget is Allowance * BranchShare,
                 'change-state!'(sk_branch_budget,BranchBudget,_),
                 'change-state!'(sk_near_reserve,Reserve,_),
                 context_evaluate(C,Inner,Kb,Facts,WantProof,WantTV,Result))),
           nb_setval(context_overlay,main))
    ; Result=Base ),
    context_finish(Goals,Bases,Allowance,Reserve,Results).

context_evaluate(C,Goal,Kb,Facts,WantProof,WantTV,Results) :-
    'inference-clock'(Started),
    'change-state!'(sk_holding,1,_),
    'sk-refresh-near!'(_),
    forall(context_seed(_,C,[Type,Scope,_,_]),
           (Key=['sk-key',Type,Scope], 'sk-drop-merged!'(Key,_), 'sk-dirty!'(Key,_))),
    % Search and needed closure are shared. Each context evaluates a different
    % input world with its own allowance; preceding contexts cannot spend it.
    'sk-evaluate!'(_),
    'inference-add!'(Started,_),
    'sk-root-results'(false,Goal,Answers),
    findall([['Assuming',Facts,Type],[Kb,'MAIN','Nil'],[assuming,P],TV],
            ( member([Type,_,P,TV],Answers), \+ \+ (WantProof=[assuming,P], WantTV=TV) ), Results),
    'sk-stale-held!'(_).

% Keep the evaluator's reader-specific compatibility checks at threshold zero.
% At positive thresholds compare row views as well as the open merge: a view
% dominated in the open merge can be the only admissible input to a reader
% excluding that merge's self-support. Non-STV values have no scalar Beta.
'context-propagate?'(Key, Result) :-
    ( context_active(C), Key=['sk-key',_,_]
    -> context_threshold(T),
       ( T =:= 0 -> Result=true
       ; 'index-hash'(Key,H),
       ( context_propagated(H,C,Stored,state(Old,OldViews)), Stored =@= Key -> true
       ; setup_call_cleanup(nb_setval(context_overlay,main),
                            once('sk-value'(Key,'sk-any-filter',[],Old)),
                            nb_setval(context_overlay,C)),
         findall([R,V],('&sk_latest'(H,K,['sk-version',_,R,V]),K =@= Key),OldViews) ),
       'sk-value'(Key,'sk-any-filter',[],New),
       findall([R,V],(context_overlay_rows(C,'&sk_latest',[H,K,['sk-version',_,R,V]]),K =@= Key),NewViews),
       ( ( context_numerical_change(T,Old,New)
         ; member([R,V],NewViews),
           (memberchk([R,Previous],OldViews) -> true ; Previous='sk-none'),
           context_numerical_change(T,Previous,V)
         ; member([R,V],OldViews), \+ memberchk([R,_],NewViews),
           context_numerical_change(T,V,'sk-none') )
       -> Result=true,
         forall((clause(context_propagated(H,C,K,_),true,Ref), K =@= Key), erase(Ref)),
         assertz(context_propagated(H,C,Key,state(New,NewViews)))
       ; Result=false ) )
    ; Result=true ).
context_numerical_change(T,Old,New) :-
    ( T > 0,
      ( Old == 'sk-none'
      -> New=['sk-val',[_,_,_,['STV',_,_]],_,_]
      ; Old=['sk-val',[Type,Scope,_,['STV',_,_]],_,_],
        ( New == 'sk-none' -> true
        ; New=['sk-val',[NewType,NewScope,_,['STV',_,_]],_,_], [Type,Scope]=@=[NewType,NewScope] ) )
    -> 'sk-change'(New,Old,Divergence), Divergence > T
    ; 'sk-same-view?'(New,Old,false) ).

'context-clear!'(true) :-
    retractall(context_propagated(_,_,_,_)),
    retractall(context_entry(_,_,_,_,_)), retractall(context_hidden(_,_,_,_,_)),
    retractall(context_scope(_,_)), retractall(context_root(_,_,_,_)), retractall(context_rule(_,_)), retractall(context_seed(_,_,_)),
    nb_setval(context_overlay,main).
