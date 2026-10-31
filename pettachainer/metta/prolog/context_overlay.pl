:- ensure_loaded(execution).
% Assuming overlays share logical keys and search rows with MAIN. Only mutable
% evaluation entries live here; overlay writes never copy or mutate borrowed
% MAIN clauses. Independent cold reads perform ordinary MAIN maintenance.
:- dynamic context_root/4, context_rule/2, context_seed/3, context_scope/2, context_threshold/1.
:- dynamic context_entry/5, context_hidden/5, context_propagated/4.
:- dynamic sk_forced_seen/2.
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
    ; \+ context_store(Space,_,local),
      Goal =.. [Space|Row], call(Goal),
      \+ context_removed(C, Space, Row), context_borrowable(C,Space,Row) ).

context_borrowable(C,'&sk_latest',[H,Key,['sk-version',_,Rhash,_]]) :- !,
    \+ (context_entry(H,C,'&sk_latest',[H,Stored,['sk-version',_,Rhash,_]],_), Stored =@= Key).
context_borrowable(C,'&sk_merged',[H,Key,_,_,_]) :- !,
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
    -> ( Pattern=[Hash|_], ground(Hash) -> Lookup=Hash ; true ),
       forall(clause(context_entry(Lookup,C,Space,Pattern,_),true,Ref), erase(Ref)),
       ( ground(Lookup) -> Index=Lookup ; Index=all ),
       assertz(context_hidden(Index, C, Space, Pattern, removed))
    ; Head =.. [Space|Pattern], retractall(Head) ).

% Store metadata and specialized MAIN read facades are generated once from
% store_schema.pl. The load-cache prelude may consult this source twice.
:- ensure_loaded(store_schema).
:- forall((store_schema(Space, Policy, Text), memberchk(Policy,[main,local])),
          ( sread(Text, Row), length(Row, Arity),
            dynamic(Space/Arity),
            atom_concat('&', Name, Space), atom_concat('&ctx_', Name, Read),
            ( current_predicate(Read/Arity) -> true
            ; dynamic(context_store/3), assertz(context_store(Space,Arity,Policy)),
              functor(Head,Read,Arity), Head=..[_|Args], Main=..[Space|Args],
              assertz((Head :- (context_active(C) -> context_overlay_rows(C,Space,Args) ; Main))),
              compile_predicates([Read/Arity]) ) )).
:- compile_predicates([context_store/3]).

'context-searching?'(Kb, Result) :-
    ( context_root(_, Kb, _, _) -> Result=true ; Result=false ).

'context-rule-enabled?'(C, Result) :-
    ( context_active(C) -> Result=true ; Result=false ).

'context-rule-visible?'(Rule, Result) :-
    ( context_rule(Rule,C) -> ( context_active(C) -> Result=true ; Result=false )
    ; Result=true ).

% Scope declarations are installed by the executor before additions. Preparing
% a search records canonical seed identities, without activating or evaluating.
'context-prepare!'([Kb,C|_], Facts, Proof, TV, true) :-
    assertz(context_root(C,Kb,Facts,[Proof,TV])),
    forall(('&kb'(Type,[Kb,C,Vars],P,T), \+ (nonvar(P),P=['rule-axiom'|_])),
           (Key=['sk-key',Type,[Kb,'MAIN',Vars]], 'index-hash'(Key,H),
            assertz(context_seed(H,C,[Type,[Kb,'MAIN',Vars],P,T])))).

'context-current'(C) :- (context_active(Active) -> C=Active ; C=main).
'context-with-scope'(C, Work, Result) :-
    'context-current'(Previous),
    setup_call_cleanup(nb_setval(context_overlay,C), once(apply_fn1(Work,[],Result)),
                       nb_setval(context_overlay,Previous)).

'context-seeds'(C, Seeds) :- findall(Seed,context_seed(_,C,Seed),Seeds).
'context-rule-rows'(C, Rows) :-
    findall(['sk-rule-def',Id,Concl,Ps],
            (context_rule(Id,C),rules('runtime-rule-row',Id,Concl,Ps)),Rows).
'context-answer-keys'(Node, Keys) :-
    ( Node=[Type,[Kb,'MAIN',Vars],_,_]
    -> findall(['sk-key',S,[Kb,'MAIN',Vars]],
               (context_seed(_,_,[Seed,[Kb,'MAIN',Vars],_,_]),
                copy_term_nat([Type,Seed],[T,S]), T=S),Keys)
    ; Keys=[] ).
'context-key-local?'(C,H,Key,Result) :-
    (context_key_local(C,H,Key) -> Result=true ; Result=false).

'context-seeded?'(Type, Scope, Result) :-
    ( context_seed(_,_,[Seed,S,_,_]), \+ \+ (Type=Seed,Scope=S) -> Result=true ; Result=false ).

% Compiled assumptions' own rules are valid only in their context. Their
% canonical structural rows can be shared, but normal MAIN evaluation never
% applies them. Query adapters, whose proof has no assumption token, are
% ordinary MAIN work.
'context-addition'(['source-plan',Source,Role,Priors,Parents,Addition], ['source-plan',MainSource,MainRole,MainPriors,MainParents,MainAddition]) :- !,
    context_canonical(Source,MainSource), context_canonical(Role,MainRole), context_canonical(Priors,MainPriors), context_canonical(Parents,MainParents),
    'context-addition'(Addition,MainAddition).
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
      StoredProof =@= Token, nonvar(Type), Type=[Head|_], Head == 'Implication'
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

% Propagation snapshots are physical overlay data. The executor decides
% whether the values differ and whether to publish a new snapshot.
'context-reuse-threshold'(T) :- context_threshold(T).
'context-propagated'(Key, Snapshot) :-
    context_active(C), 'index-hash'(Key,H),
    (context_propagated(H,C,Stored,state(Old,Views)),Stored =@= Key
    -> Snapshot=['context-snapshot',Old,Views] ; Snapshot='context-unread').
'context-store-propagated!'(Key,Value,Views,true) :-
    context_active(C), 'index-hash'(Key,H),
    forall((clause(context_propagated(H,C,K,_),true,Ref),K =@= Key),erase(Ref)),
    assertz(context_propagated(H,C,Key,state(Value,Views))).
'context-views'(Key,Views) :-
    'index-hash'(Key,H),
    findall([R,V],('&ctx_sk_latest'(H,K,['sk-version',_,R,V]),K =@= Key),Views).
'context-view-changes'(Old,New,Changes) :-
    findall([Before,After],
       (member([R,After],New), (memberchk([R,Before],Old) -> true ; Before='sk-none')
       ;member([R,Before],Old), \+ memberchk([R,_],New), After='sk-none'), Changes).

'context-clear!'(true) :-
    forall(( member(Store, ['&rule_evidence_names','&given_rules','&deterministic_rules']),
             Row =.. [Store, Name, Kb],
             catch(Row, error(existence_error(procedure,_),_), fail), Name = [ctx|_] ),
           'remove-atom'(Store, [Name, Kb], _)),
    forall(retract(support_identity_owner(Id)),retractall(support_identity(Id,_,_))),
    forall(retract(sk_forced_seen(_,Trie)),trie_destroy(Trie)),
    retractall(context_propagated(_,_,_,_)),
    retractall(context_entry(_,_,_,_,_)), retractall(context_hidden(_,_,_,_,_)),
    retractall(context_scope(_,_)), retractall(context_root(_,_,_,_)), retractall(context_rule(_,_)), retractall(context_seed(_,_,_)),
    nb_setval(context_overlay,main).
