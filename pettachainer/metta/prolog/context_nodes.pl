% Context values share one scheduler and one producer-node -> reader-node index.
% Physical stores are scoped by context_overlay.pl, just like aggregate state.
:- use_module(library(heaps)).
:- use_module(library(ordsets)).
:- dynamic '&sk_use'/3, '&sk_needed'/3.

cn_rows(Space,Row) :-
    context_store(Space,Arity),length(Row,Arity),
    (context_effective_scope(Space,C) -> context_overlay_rows(C,Space,Row) ; Goal=..[Space|Row],call(Goal)).
cn_add(Space,Row) :- 'context-add!'(Space,Row,_).
cn_remove(Space,Row) :- 'context-remove!'(Space,Row,_).
cn_digest(K,R,D) :- 'link-digest'([context_row,K,R],D).
cn_id(Space,D,E,Id) :- 'link-digest'([Space,D,E],Id).
cn_node(Id,Space,Row) :- cn_rows('&sk_context_id',[Id,Space,D]), Row=[D,Id|_],cn_rows(Space,Row).
cn_replace(Space,Old,New) :- cn_remove(Space,Old),cn_add(Space,New).
cn_depth(H,K,Depth) :- ('&sk_needed'(H,Stored,Depth),Stored=@=K -> true ; Depth=1000000).
cn_node_depth(Id,H,K,D) :-
    (cn_rows('&sk_context_need',[Id,Known])->D=Known
    ;cn_node(Id,_,[_,_,_,_,_,_,[],_,_,_,_])->cn_depth(H,K,D)
    ;D=1000000).
cn_demand(Id,H,K) :-
    cn_depth(H,K,KnownDepth),(nb_current(context_node_root,true)->KeyDepth=0;KeyDepth=KnownDepth),
    (cn_active(Parent),cn_node(Parent,_Store,[_,_,PH,PK|_]),cn_node_depth(Parent,PH,PK,PD)
    -> D is min(PD,KeyDepth)
    ;D=KeyDepth),
    cn_min_need(Id,D),
    (nb_current(context_node_root,true),\+cn_active(_)->cn_need_inputs([Id],[]);true).
cn_min_need(Id,D) :-
    (cn_rows('&sk_context_need',[Id,Old]),Old=<D -> true
    ;cn_remove('&sk_context_need',[Id,_]),cn_add('&sk_context_need',[Id,D])).
cn_pending(Id) :-
    (cn_active(_)->nb_setval(context_node_waiting,true),
      nb_getval(context_node_missing,Was),ord_add_element(Was,Id,Missing),nb_setval(context_node_missing,Missing);true).
cn_unpublished(pending).
cn_unpublished(wait(new,_)).
cn_note(Cuts) :-
    (cn_active(_),nb_current(context_node_cuts,Old)->ord_union(Old,Cuts,New),nb_setval(context_node_cuts,New);true).
cn_active(Id) :- nb_current(context_node_active,Id),Id\==none.
cn_link(Producer) :-
    (cn_active(Reader), Reader\==Producer,
     \+ cn_rows('&sk_context_reader',[Producer,Reader])
    -> cn_add('&sk_context_reader',[Producer,Reader]);true).
cn_queue(Id) :-
    (nb_current(context_node_heap,Heap),
     cn_node(Id,S,[_,_,H,K,_,Seq,_,_,_,_,State]),State\=wait(_,_),
     \+ (nb_current(context_node_priming,true),S=='&sk_context')
    ->cn_node_depth(Id,H,K,D),
      (nb_current(context_node_push,Ticket)->true;Ticket=0),NextTicket is Ticket+1,
      Priority=rank(D,Seq,Ticket),
      (cn_rows('&sk_context_queued',[Id,Queued]),Queued@=<Priority->true
      ;nb_setval(context_node_push,NextTicket),add_to_heap(Heap,Priority,Id,Next),nb_setval(context_node_heap,Next),
       cn_remove('&sk_context_queued',[Id,_]),cn_add('&sk_context_queued',[Id,Priority]))
    ;true).

cn_ensure(Space,H,K,R,Seq,E,Id) :-
    cn_digest(K,R,D),cn_id(Space,D,E,Id),
    (cn_rows(Space,[D,Id,_,Stored,_,_,_,_,_,_,_]),Stored=@=K -> true
    ; cn_create(H,K,Space,[D,Id,H,K,R,Seq,E,E,0,'sk-none',pending]),
      query_metric_increment('context-nodes-created',_)),
    cn_demand(Id,H,K),cn_link(Id).

cn_shared(C,H,K) :- context_active(C),\+context_key_local(C,H,K),\+context_inputs_local(C,H,K).
cn_create(H,K,S,Row) :-
    Row=[D,Id|_],
    (cn_shared(C,H,K)
    ->setup_call_cleanup(nb_setval(context_overlay,main),
       (cn_add(S,Row),cn_add('&sk_context_id',[Id,S,D])),nb_setval(context_overlay,C))
    ;cn_add(S,Row),cn_add('&sk_context_id',[Id,S,D])).
cn_scope_run(Id,Goal) :-
    (cn_node(Id,_,[_,_,H,K|_]),cn_shared(C,H,K)
    ->nb_setval(context_node_publication,none),
      setup_call_cleanup(nb_setval(context_overlay,main),Goal,nb_setval(context_overlay,C)),
      (nb_getval(context_node_publication,[Target,Changed,Causes])
       ->forall((cn_rows('&sk_context_reader',[Id,Reader]),cn_node(Reader,S,Row),Row=[D,Reader|_],
                 context_entry(D,C,S,[D,Reader|_],_)),
          ((Id==Target->true;cn_edge(Target,Reader),cn_remove('&sk_context_reader',[Id,Reader])),
           (Row=[_,_,_,_,_,_,_,_,_,_,State],(Changed==true;State==pending;State=wait(_,_))
            ->cn_notify(Target,Reader,Causes);true)))
       ;true)
    ;call(Goal)).

cn_request(Space,H,K,R,Q,E,Id) :-
    cn_ensure(Space,H,K,R,Q,E,Id),
    (cn_node(Id,_,[_,_,_,_,_,_,_,_,_,_,true])->cn_dirty(Id,true);true),cn_queue(Id).

% Cuts are accumulated on the node being evaluated, not in rebuild frames.
'sk-excludes?'(E,Deps,Result) :-
    'deps-meet?'(E,Deps,Result),
    (Result==true,cn_active(_),nb_current(context_node_cuts,Old)
    -> 'deps-excluded'(E,Deps,Found),ord_union(Old,Found,Cuts),nb_setval(context_node_cuts,Cuts)
    ; true).
'sk-wait!'(Id,R,Cost,Waiting,Waiting) :-
    (cn_node(Id,_,_)->cn_remove('&sk_given_pending',[Id,R,_]),cn_add('&sk_given_pending',[Id,R,Cost])
    ;query_metric_increment('conditions-unpaid',_)).
 'sk-context-pending?'(Pending) :- (nb_current(context_node_waiting,true)->Pending=true;Pending=false).
 'sk-member-pending?'(K,B) :-
    'index-hash'(K,H),
    (cn_active(Owner),cn_node(Owner,_,[_,_,OH,OK|_])
     ->('sk-rate-fold?'(OK,true)->E=[OH];'sk-fold-exclusions'(OH,E));E=[]),
    cn_digest(K,-1,MD),
    (cn_reusable('&sk_context_merge',MD,K,E,Settled,_),cn_node(Settled,_,[_,_,_,_,_,_,_,_,_,_,true])
     ->(cn_rows('&sk_given_pending',[Settled,-1,_])->B=true;B=false)
    ;cn_id('&sk_context_merge',MD,E,Mid),cn_node(Mid,_,[_,_,_,_,_,_,_,_,_,_,State]),State\==true ->B=true
    ;memberchk(H,E)->B=false
    ;'&sk_row'(H,Stored,R,_),Stored=@=K,cn_digest(K,R,D),
       \+ (cn_reusable('&sk_context',D,K,E,Id,_),cn_node(Id,_,[_,_,_,_,_,_,_,_,_,_,true]),
           \+cn_rows('&sk_given_pending',[Id,R,_])) ->B=true
    ;B=false).
'sk-condition-owner'(H,Owner) :- (cn_active(Id),cn_node(Id,_,[_,_,H|_])->Owner=Id;Owner=H).
'sk-fold-exclusions'(H,E) :-
    (cn_active(_),nb_current(context_node_exclusions,Outside)->true;Outside=[]),ord_add_element(Outside,H,E).
'sk-context-excludes?'(Deps,Result) :-
    (cn_active(_),nb_current(context_node_exclusions,E) -> 'sk-excludes?'(E,Deps,Result);Result=false).

% Instance parameters carry only their fold hash as dependencies. Their
% class must also agree on which observations the reader leaves out.
cn_samples(H,['sk-fold',Args],E,Samples) :- !,
    ('sk-instance-fold?'(Args,true)->'sk-left-out'(H,E,Samples);Samples=[]).
cn_samples(H,K,E,Samples) :-
    K=['sk-key',Type,_],nonvar(Type),Type=[Tag|_],Tag=='RuleTruth',!,
    findall([FH,Left],('&sk_row'(H,_,_,['sk-row',_,_,Ps,_]),
      member(['CPU','FoldAllCompiled',Args,_],Ps),'sk-instance-fold?'(Args,true),
      'index-hash'(['sk-fold',Args],FH),'sk-left-out'(FH,E,Left),Left\=[]),Found),sort(Found,Samples).
cn_samples(_,_,_,[]).

% Lookup order is independent of physical republication order. H1/H3 still
% approximate some values in this round; rotating equivalent candidates can
% otherwise make those approximations oscillate without new information.
cn_reusable(Space,D,K,E,Id,V) :-
    findall(rank(Stale,Exact,N,Cuts,Found)-[Found,Cuts,Value],
      (cn_rows(Space,[D,Found,H,Stored,_,_,Context,Cuts,Deps,Value,Fresh]),Stored=@=K,
       ord_subset(Cuts,E),'deps-meet?'(E,Deps,false),'sk-live-view?'(Value,true),
       cn_samples(H,K,E,Now),cn_samples(H,K,Cuts,Before),Now=@=Before,
       (Fresh==true->Stale=0
       ;Fresh==false,Value\=='sk-none',Space=='&sk_context',
        (nb_current(context_node_priming,true)
         ;Context=[],cn_depth(H,K,Depth),Depth>2,Depth<1000000),Stale=1),
       (Cuts==E->Exact=0;Exact=1),length(Cuts,N)),Candidates),
    keysort(Candidates,[_-[Id,Used,V]|_]),cn_note(Used).

cn_row_read(H,K,R,Seq,E,V) :-
    cn_digest(K,R,D),
    (memberchk(H,E) -> 'deps-key'(H,Dep),'sk-excludes?'(E,Dep,_),V='sk-none'
    ; cn_reusable('&sk_context',D,K,E,Id,V0)
    -> cn_demand(Id,H,K),cn_link(Id), V=V0
    ; cn_request('&sk_context',H,K,R,Seq,E,Missing),cn_pending(Missing),V='sk-none').

'sk-admitted-versions'(H,K,Filter,E,Versions) :-
    ( K=['sk-key'|_]
    -> findall([Seq,R],('&sk_row'(H,Stored,R,Row),Stored=@=K,Row=['sk-row',['sk-ident',Rule,_,_],_,_,Seq],
          ('rule-live?'(Rule,true)->'context-rule-visible?'(Rule,true);'sk-drop-row!'(H,K,R,Row,_),fail)),Rows0),sort(Rows0,Rows)
    ; Rows=[[0,0]] ),
    findall(['sk-version',Seq,R,V],
      (member([Seq,R],Rows),cn_row_read(H,K,R,Seq,E,V),'sk-admits?'(Filter,E,V,true)),Versions).

'sk-ordinary-view'(H,K,R,V) :-
    cn_digest(K,R,D),
    (cn_rows('&sk_context',[D,_,H,Stored,R,_,[],_,_,Value,State]),Stored=@=K,memberchk(State,[true,false]),'sk-live-view?'(Value,true)
    -> V=Value; V='sk-none').

% External facts and structural changes invalidate merged nodes; publications
% notify only subscribers of the particular node whose value changed.
cn_dirty(Id,Force) :-
    (cn_node(Id,S,Old),Old=[D,Id,H,K,R,Q,E,C,Deps,V,Fresh]
    -> ( (Fresh==true;Fresh=wait(old,_))->Next=false;Fresh=wait(new,_)->Next=pending;Next=Fresh),
       cn_replace(S,Old,[D,Id,H,K,R,Q,E,C,Deps,V,Next]),
       (Force==true->Causes=[H];Force==false->Causes=[];Causes=Force),
       forall(member(Cause,Causes),
         ((S=='&sk_context',K=['sk-key'|_])
          ->(cn_rows('&sk_context_forced_used',[Id,Cause])->true
            ;cn_add('&sk_context_forced_used',[Id,Cause]),
             (cn_rows('&sk_context_forced',[Id,Cause])->true;cn_add('&sk_context_forced',[Id,Cause])))
          ;(cn_rows('&sk_context_forced',[Id,Cause])->true;cn_add('&sk_context_forced',[Id,Cause])))),
       cn_node_depth(Id,H,K,Depth),cn_depth(H,K,KeyDepth),'sk-evaluation-free-depth'(Free),
       ((S=='&sk_context',K=['sk-key'|_],E=[],V\=='sk-none',KeyDepth>Free,KeyDepth<1000000,\+cn_determined(Id))->true
       ;(Depth<1000000;cn_determined(Id))->cn_queue(Id);true)
    ; true).
cn_changed(Id,Force) :-
    findall(Reader,cn_rows('&sk_context_reader',[Id,Reader]),Readers),
    forall(member(Reader,Readers),cn_notify(Id,Reader,Force)).
cn_notify(Producer,Reader,Force) :-
    cn_node(Producer,_,[_,_,H,Key|_]),
    (Force==true->Causes=[H];Force==false->Causes=[];Causes=Force),
    (cn_node(Producer,'&sk_context_merge',[_,_,_,Member|_]),
     cn_node(Reader,'&sk_context',[_,_,_,Fold|_]),'sk-rate-fold?'(Fold,true)
     ->'sk-rate-dirty!'(Fold,Member,_),sort([H|Causes],Wake)
    ;'sk-rate-fold?'(Key,true),Causes=[]->Wake=[H]
    ;Wake=Causes),
    cn_dirty(Reader,Wake).

cn_key_nodes(H,K,Space,Id) :-
    ( Space='&sk_context_merge',cn_digest(K,-1,D)
    ; Space='&sk_context',
      (K=['sk-key'|_] -> '&sk_row'(H,Stored,R,_),Stored=@=K ; R=0),cn_digest(K,R,D)),
    cn_rows(Space,[D,Id,_,Stored,_,_,_,_,_,_,_]),Stored=@=K.
'sk-drop-merged!'(K,true) :-
    'index-hash'(K,H),forall(cn_key_nodes(H,K,'&sk_context_merge',Id),cn_dirty(Id,true)).

% A fold that writes the cache it is currently evaluating has already taken
% that input change. Its publication performs the value/KL comparison; the
% cache must not enqueue a second key-level invalidation of the same fold.
'sk-cache-input-changed!'(K,true) :-
    (cn_active(Id),cn_node(Id,_,[_,_,_,Active|_]),Active=@=K->true;'sk-dirty!'(K,_)).

'sk-context-drop-row!'(H,K,R,true) :-
    cn_digest(K,R,D),findall([Id,Row],cn_rows('&sk_context',[D,Id,H,K,R|Row]),Nodes),
    forall(member([Id,Tail],Nodes),
      (cn_changed(Id,true),cn_remove('&sk_context',[D,Id,H,K,R|Tail]),
       cn_remove('&sk_context_id',[Id,'&sk_context',D]),
       cn_remove('&sk_context_reader',[_,Id]),cn_remove('&sk_context_reader',[Id,_]),
       forall(member(Store,['&sk_context_need','&sk_context_queued','&sk_context_forced','&sk_context_forced_used',
                            '&sk_given_pending','&sk_given_granted','&sk_conditioning','&sk_cond_level']),
         (context_store(Store,N),length(Pattern,N),Pattern=[Id|_],cn_remove(Store,Pattern))))).

% Plain views compare without proof allocation. Aggregate propagation is value
% bounded by the existing Beta KL setting, including scalar fold results.
cn_same(K,Old,New) :-
    (K=['sk-fold'|_];K=['sk-group'|_]),!,
    cn_coverage(Old,Cover),cn_coverage(New,Cover),
    ('sk-rate-fold?'(K,true),cn_scalar(Old,OT),cn_scalar(New,NT)
     ->context_threshold(T),cn_close(T,OT,NT)
     ;'sk-same-view?'(New,Old,true)).
cn_same(_,Old,New) :- 'sk-same-view?'(New,Old,true).
cn_coverage(['sk-goal-val',_,P,_,_],Coverage) :- !,
    'sk-step-proof'(P,Step),(Step=['partial-fold',C,N,_]->Coverage=partial(C,N);Coverage=complete).
cn_coverage(_,complete).
cn_scalar(V,TV) :-
    (V=['sk-val',[_,_,_,T],_,_];V=['sk-goal-val',['CPU',_,_,T],_,_,_]),
    (T=['InstanceEvidence',_,_]->'ImplicationInstanceTv'(T,TV)
    ;T=[Tag|_],memberchk(Tag,['STV','CTV']),TV=T).
cn_close(T,['CTV',P0,N0],['CTV',P1,N1]) :- cn_close(T,P0,P1),cn_close(T,N0,N1).
cn_close(T,Old,New) :- Old=['STV',_,_],New=['STV',_,_],
    'sk-change'(['sk-val',[a,b,c,New],['ev-set',0],0],['sk-val',[a,b,c,Old],['ev-set',0],0],D),D=<T.

cn_publish(Id,Computed) :-
    cn_node(Id,S,Old),Old=[D,Id,H,K,R,Q,E,OldCuts,OldDeps,Previous,PriorState],
    (((nb_current(context_node_waiting,true),
      \+ ((S=='&sk_context_merge';K=['sk-fold'|_];K=['sk-group'|_]),Computed\=='sk-none'))
     ;cn_rows('&sk_given_pending',[Id,R,_]),Computed=='sk-none')
    ->nb_getval(context_node_missing,Missing),
      (cn_unpublished(PriorState)->Waiting=wait(new,Missing);Waiting=wait(old,Missing)),
      cn_replace(S,Old,[D,Id,H,K,R,Q,E,OldCuts,OldDeps,Previous,Waiting])
    ; (nb_current(context_node_waiting,true);cn_rows('&sk_given_pending',[Id,R,_]))
    ->cn_settled(Id,Computed,E)
    ; (nb_current(context_node_cuts,Found)->ord_intersection(Found,E,Cuts);Cuts=E),
      cn_canonical(S,D,Id,H,K,R,Q,Cuts,Canonical),cn_settled(Canonical,Computed,Cuts)).

% A pending request initially names E. Once evaluated it is interned by the
% actual cut class. Move subscriptions, not copies of the value or old views.
cn_canonical(S,D,Id,H,K,R,Q,Cuts,Canonical) :-
    cn_id(S,D,Cuts,Canonical),
    (Id==Canonical -> true
    ; findall(P,cn_rows('&sk_context_reader',[P,Id]),Inputs),
      (cn_node(Canonical,S,_)->true
      ;cn_add(S,[D,Canonical,H,K,R,Q,Cuts,Cuts,0,'sk-none',pending]),
       cn_add('&sk_context_id',[Canonical,S,D])),
      cn_remove('&sk_context_reader',[_,Canonical]),
      forall((member(P,Inputs),P\==Canonical),cn_edge(P,Canonical)),
      cn_retarget(Id,Canonical,_),
      (cn_rows('&sk_context_need',[Id,Depth])->cn_min_need(Canonical,Depth);true),
      forall(cn_rows('&sk_context_forced',[Id,Cause]),
        ((cn_rows('&sk_context_forced_used',[Canonical,Cause]);cn_rows('&sk_context_forced',[Canonical,Cause]))
         ->true;cn_add('&sk_context_forced',[Canonical,Cause]))),
      cn_remove(S,[D,Id,_,_,_,_,_,_,_,_,_]),
      cn_remove('&sk_context_id',[Id,S,D]),cn_remove('&sk_context_need',[Id,_]),
      cn_remove('&sk_context_reader',[_,Id]),cn_remove('&sk_context_reader',[Id,_]),
      cn_remove('&sk_context_forced',[Id,_]),cn_move_state(Id,Canonical)).
% A request can become reusable while it waits on the heap. Retarget its
% readers without evaluating the row or changing the reused node's inputs.
cn_alias(Id,Canonical) :- cn_scope_run(Id,cn_alias_node(Id,Canonical)).
cn_alias_node(Id,Canonical) :-
    nb_getval(context_node_progress,Tick),Next is Tick+1,nb_setval(context_node_progress,Next),
    findall(Cause,cn_rows('&sk_context_forced',[Id,Cause]),Force),
    cn_retarget(Id,Canonical,Changed),nb_setval(context_node_publication,[Canonical,Changed,Force]),
    (cn_rows('&sk_context_need',[Id,Depth])->cn_min_need(Canonical,Depth);true),
    cn_node(Id,S,[D,Id|_]),cn_remove(S,[D,Id,_,_,_,_,_,_,_,_,_]),
    cn_remove('&sk_context_id',[Id,S,D]),cn_remove('&sk_context_need',[Id,_]),
    cn_remove('&sk_context_reader',[_,Id]),cn_remove('&sk_context_reader',[Id,_]),
    cn_remove('&sk_context_forced',[Id,_]),cn_move_state(Id,Canonical).

cn_move_state(Id,Canonical) :-
    forall(cn_rows('&sk_cond_level',[Id,R,Level]),
      (findall(L,cn_rows('&sk_cond_level',[Canonical,R,L]),Was),max_list([Level|Was],Max),
       cn_remove('&sk_cond_level',[Canonical,R,_]),cn_add('&sk_cond_level',[Canonical,R,Max]))),
    cn_remove('&sk_cond_level',[Id,_,_]),
    forall(member(S,['&sk_given_pending','&sk_given_granted','&sk_conditioning','&sk_context_forced_used']),
      (findall(Tail,cn_rows(S,[Id|Tail]),Rows),
       forall(member(Tail,Rows),(cn_rows(S,[Canonical|Tail])->true;cn_add(S,[Canonical|Tail]))),
       context_store(S,N),length(Pattern,N),Pattern=[Id|_],cn_remove(S,Pattern))).

cn_edge(P,C) :- (P==C->true;cn_rows('&sk_context_reader',[P,C])->true;cn_add('&sk_context_reader',[P,C])).

% Changing the identity of a reusable node is not an outside input change.
% Preserve H1's forcing rule and compare values before waking its readers.
cn_retarget(Id,Canonical,Changed) :-
    cn_node(Id,_,[_,_,_,K,_,_,_,_,_,Previous,State]),
    cn_node(Canonical,_,[_,_,_,_,_,_,_,_,_,Current,_]),
    ((cn_unpublished(State);\+cn_same(K,Previous,Current))->Changed=true;Changed=false),
    findall(Cause,cn_rows('&sk_context_forced',[Id,Cause]),Force),
    forall((cn_rows('&sk_context_reader',[Id,Reader]),Reader\==Canonical),
      (cn_edge(Canonical,Reader),
       ((Changed==true;cn_node(Reader,_,[_,_,_,_,_,_,_,_,_,_,wait(_,Missing)]),memberchk(Id,Missing))
        ->cn_notify(Id,Reader,Force);true))).

cn_settled(Id,Computed,Cuts) :-
    cn_node(Id,S,Old),Old=[D,Id,H,K,R,Q,E,_,OldDeps,Previous,PreviousState],
    'sk-view-deps-step'(0,Computed,Deps),
    ('deps-meet?'(E,Deps,false)->true
     ;'deps-excluded'(E,Deps,Bad),throw(error(context_node_exclusion(Id,K,Bad),cn_settled/3))),
    findall(Cause,cn_rows('&sk_context_forced',[Id,Cause]),Force),
    (cn_same(K,Previous,Computed),\+cn_unpublished(PreviousState),'sk-live-view?'(Previous,true) -> Value=Previous,Changed=false
    ; S=='&sk_context',K=['sk-key'|_],E=[],Previous\=='sk-none',Computed\=='sk-none',
      Force==[],'sk-live-view?'(Previous,true),cn_rows('&sk_support',[H,R,Support]),'deps-within?'(Deps,Support,true)
    -> query_metric_increment('views-without-support',_),Value=Previous,Changed=false
    ; (K=['sk-key'|_], '&sk_row'(H,Stored,R,['sk-row',['sk-ident',Rule,_,_],_,_,_]),Stored=@=K -> true ; Rule= -1),
      (S=='&sk_context_merge'->Value=Computed;'sk-reference-view'(Rule,Computed,Value)),Changed=true,query_metric_increment('views-stored',_) ),
    (Changed==true -> NewDeps=Deps;NewDeps=OldDeps),
    cn_replace(S,Old,[D,Id,H,K,R,Q,E,Cuts,NewDeps,Value,true]),
    % A parameter check may publish its previous estimate while its new
    % sample is still pending. Carry the outside-change force through that
    % wait so H1 cannot discard the eventual learned value.
    ('sk-rate-fold?'(K,true),cn_rows('&sk_rate_dirty',[H,_,Stored,_]),Stored=@=K
     ->true;cn_remove('&sk_context_forced',[Id,_])),
    nb_setval(context_node_publication,[Id,Changed,Force]),
    (S=='&sk_context',E=[] ->
      (cn_rows('&sk_support',[H,R,Past])->true;Past=0),'deps-union'(Past,NewDeps,Union),
      cn_remove('&sk_support',[H,R,_]),cn_add('&sk_support',[H,R,Union]);true),
    (Changed==true,'context-propagate?'([Id,K,Previous,Value],true)
     ->Propagated=true,cn_changed(Id,Force),
       (E=[]->cn_members_changed(K,NewDeps);true),
       (E=[]->'hm-screen-changed!'(H,K,_);true)
     ;Propagated=false),
    (S=='&sk_context_merge',E=[] -> 'sk-note-truth-factor!'(H,K,Value,_);true),
    ((Changed==false;Propagated==true;Value=='sk-none',cn_unpublished(PreviousState))->cn_ready(Id);true).
cn_ready(Id) :-
    forall((cn_rows('&sk_context_reader',[Id,Reader]),cn_node(Reader,_,[_,_,_,_,_,_,_,_,_,_,State]),
            (State=wait(_,Missing),memberchk(Id,Missing)
             ;State==true,cn_node(Reader,_,[_,_,_,K,_,_,_,_,_,V,_]),
              (K=['sk-fold'|_];K=['sk-group'|_]),cn_coverage(V,partial(_,_)))),cn_dirty(Reader,false)).

cn_members_changed(K,Deps) :-
    'index-hash'(K,H),
    forall(('&sk_use'(H,Stored,Fold),Stored=@=K,'index-hash'(Fold,FH),'deps-has?'(Deps,FH,false)),
      ('sk-rate-dirty!'(Fold,K,_),
       forall(cn_key_nodes(FH,Fold,_,Id),cn_dirty(Id,true)))).

% A merged node reads row nodes, so a late publication invalidates precisely
% its own exclusion class and the readers subscribed to that merge.
'sk-value'(K,Filter,E,Value) :-
    'index-hash'(K,H),cn_digest(K,-1,D),
    (memberchk(H,E)->cn_note([H]),Value='sk-none'
    ;cn_reusable('&sk_context_merge',D,K,E,Id,V)
    -> cn_demand(Id,H,K),cn_link(Id),query_metric_increment('merged-cache-hits',_),
       ( 'sk-open-filter?'(Filter,true) -> Value=V
       ; 'sk-admits?'(Filter,[],V,true) -> Value=V
       ; 'sk-admitted-versions'(H,K,Filter,E,Versions),maplist(cn_version_value,Versions,Views),
         'sk-merge-key'(H,K,Filter,E,[],Views,Value) )
    ; cn_request('&sk_context_merge',H,K,-1,-1,E,Missing),cn_pending(Missing),Value='sk-none').
cn_version_value(['sk-version',_,_,V],V).

% Compatibility and closed reads sometimes select facts directly. They still
% subscribe to the merged input node so later fact additions reach them.
% The direct fact is already available; this subscription is not a miss.
'sk-subscribe-leaves!'(K,E,true) :-
    (cn_active(Reader),'index-hash'(K,H),\+memberchk(H,E)
    ->cn_digest(K,-1,D),
      (cn_reusable('&sk_context_merge',D,K,E,Id,_)->cn_demand(Id,H,K),cn_link(Id)
      ;cn_ensure('&sk_context_merge',H,K,-1,-1,E,Id),(Id==Reader->true;cn_queue(Id)))
    ;true).

cn_compute(Id) :- cn_scope_run(Id,cn_compute_node(Id)).
cn_compute_node(Id) :-
    nb_getval(context_node_progress,Tick),NextTick is Tick+1,nb_setval(context_node_progress,NextTick),
    cn_node(Id,S,[D,_,H,K,R,_,E,_,_,_,_]),
    % H1 still keeps history-dependent ordinary values in this round. Record
    % the exclusions that rejected such a current value, so the recomputation
    % cannot collapse back onto that same incompatible empty-class node.
    findall(Cut,
      ((cn_rows(S,[D,_,_,Stored,_,_,_,PriorCuts,Deps,_,_]),Stored=@=K,
        ord_subset(PriorCuts,E),'deps-excluded'(E,Deps,Rejected),member(Cut,Rejected))
       ;member(Cut,E),cn_samples(H,K,[Cut],Left),Left\=[]),RejectedCuts),
    sort(RejectedCuts,InitialCuts),
    cn_remove('&sk_given_pending',[Id,R,_]),
    ('sk-rate-fold?'(K,true)->true;cn_remove('&sk_context_reader',[_,Id])),
    setup_call_cleanup(
      (nb_setval(context_node_active,Id),nb_setval(context_node_exclusions,E),nb_setval(context_node_cuts,InitialCuts),nb_setval(context_node_waiting,false),nb_setval(context_node_missing,[])),
      once(( S=='&sk_context_merge'
        -> query_metric_increment('merged-cache-misses',_),
           'sk-admitted-versions'(H,K,'sk-any-filter',E,Versions),maplist(cn_version_value,Versions,Views),
           'sk-merge-key'(H,K,'sk-any-filter',E,[],Views,V),cn_publish(Id,V)
        ; query_metric_increment('row-computes',_),
          (K=['sk-key'|_] -> '&sk_row'(H,Stored,R,Row),Stored=@=K,
             ('sk-row-view'([],E,H,K,R,Row,V)->true;V='sk-none'),cn_publish(Id,V)
          ; (cn_fold_value(H,K,E,V)->true;V='sk-none'),
            ('sk-rate-fold?'(K,true)->nb_setval(context_node_waiting,false);true),cn_publish(Id,V)) )),
      nb_setval(context_node_active,none)).
cn_fold_value(H,K,E,V) :-
    (K=['sk-fold',Args]
    -> 'sk-fold-view'(H,Args,Ordinary),
       ('sk-instance-fold?'(Args,true)
        ->forall((member(C,E),'sk-left-out'(H,[C],Left),Left\=[]),cn_note([C])),
          'sk-instance-without-view'(H,Args,E,LeftOut),(LeftOut\=='sk-none'->V=LeftOut;V=Ordinary)
        ;V=Ordinary)
    ; K=['sk-group',Args], 'sk-group-view'(H,K,Args,V)).

'sk-evaluation-free-depth'(D) :- ('search-id-value'(sk_forward_run,1)->D=0;D=2).
'sk-evaluation-per-step'(2).
'sk-walk-per-step'(1).
'sk-need-depth'(H,K,D) :- cn_depth(H,K,D).
'sk-needed?'(H,K,B) :- (cn_depth(H,K,D),D<1000000->B=true;B=false).
'sk-need-roots!'(Keys,true) :-
    (context_active(C)->true;C=main),nb_setval(context_node_query_scope,C),cn_remove('&sk_context_need',[_,_]),
    'search-id-value'(sk_eval_budget,B),'change-state!'(sk_need_budget,B,_),cn_need(0,Keys,[]),cn_need_cached(0,Keys).
'sk-need-keys!'(Depth,Keys,true) :- cn_need(Depth,Keys,[]),cn_need_cached(Depth,Keys).

% A cached row still needs the specific class nodes it subscribed to. Walk
% those input identities, rather than refreshing every retained class of a
% statically needed key. H3 still stops at a nonempty deep ordinary row.
cn_need_cached(Depth,Keys) :-
    findall(Id,(member(K,Keys),'index-hash'(K,H),cn_key_nodes(H,K,_,Id),
                cn_node(Id,_,[_,_,_,_,_,_,[],_,_,_,_]),cn_min_need(Id,Depth)),Ids),
    cn_need_inputs(Ids,[]).
cn_need_inputs([], _).
cn_need_inputs([Id|Rest],Seen) :-
    (ord_memberchk(Id,Seen)->cn_need_inputs(Rest,Seen)
    ;ord_add_element(Seen,Id,Next),
     cn_node(Id,S,[_,_,H,K,_,_,E,_,_,V,State]),cn_node_depth(Id,H,K,Depth),
     'sk-evaluation-free-depth'(Free),cn_depth(H,K,KeyDepth),
     ((S=='&sk_context',K=['sk-key'|_],E=[],V\=='sk-none',KeyDepth>Free,KeyDepth<1000000)->Inputs=[]
      ;findall(P,(cn_rows('&sk_context_reader',[P,Id]),cn_node(P,_,[_,_,PH,PK|_]),
                  (S=='&sk_context','sk-rate-fold?'(K,true)
                   ->cn_rows('&sk_rate_dirty',[H,_,Fold,Member]),Fold=@=K,Member=@=PK;true),
                  cn_depth(PH,PK,PD),Need is min(Depth,PD),cn_min_need(P,Need)),Inputs)),
     (State=wait(_,Missing),Missing\=[],
      forall(member(M,Missing),(cn_node(M,MS,[MD,_,_,MK,_,_,ME,_,_,_,_]),cn_reusable(MS,MD,MK,ME,_,_)))
      ->cn_dirty(Id,false);true),
     append(Rest,Inputs,Work),cn_need_inputs(Work,Next)).
cn_need(_,[],[]).
cn_need(Depth,[],Members) :- Members\=[],cn_need(Depth,Members,[]).
cn_need(Depth,Keys,Members) :- Keys\=[],
    findall([Premises,Deferred],
      (member(K,Keys),'index-hash'(K,H),\+ ('&sk_needed'(H,Stored,_),Stored=@=K),
       assertz('&sk_needed'(H,K,Depth)),cn_need_key(H,K,Depth,Premises,Deferred)),Lists),
    findall(P,member([P,_],Lists),NextLists),append(NextLists,NextKeys),
    findall(M,member([_,M],Lists),MemberLists),append(MemberLists,Later),append(Members,Later,AllMembers),
    Next is Depth+1,cn_need(Next,NextKeys,AllMembers).
cn_need_key(H,K,Depth,Keys,Deferred) :-
    'sk-evaluation-free-depth'(Free),
    (K=['sk-key',Type,Scope] ->
      Deferred=[],findall(Input,
       ('&sk_row'(H,Stored,R,['sk-row',_Ident,_Concl,Ps,Q]),Stored=@=K,
        cn_ensure('&sk_context',H,K,R,Q,[],_),
        ('sk-ordinary-view'(H,K,R,'sk-none')->Unseen=true;Unseen=false),
        (Depth=<Free->true;Unseen==true,'term-cost'(Type,Cost),Extra is Cost-1,'sk-take!'(sk_need_budget,Extra,true)),
        (Depth=<Free,\+'search-id-value'(sk_forward_run,1) -> 'search-id-value'(sk_near_reserve,N),More is N+8,'change-state!'(sk_near_reserve,More,_);true),
        member(P,Ps),'sk-direct-key-step'([],P,Found),member(Input,Found)),Premises),
      (Depth=:=0,\+'search-id-value'(sk_forward_run,1),ground(Type),
       'sk-leaf-facts'(Type,Scope,'sk-any-filter',[]),
       findall(M,'sk-rule-match'([Type,Scope,_,_],M),Matches),
       'sk-prior-folds'(Type,Matches,[['sk-prior-fold',_,Args]|_])
       -> Keys=[['sk-fold',Args]|Premises];Keys=Premises)
    ; cn_ensure('&sk_context',H,K,0,0,[],_),
      (Depth=<Free,\+'search-id-value'(sk_forward_run,1) -> 'search-id-value'(sk_near_reserve,N),More is N+8,'change-state!'(sk_near_reserve,More,_);true),
      ('sk-rate-fold?'(K,true)
       ->Keys=[],findall(M,(cn_rows('&sk_rate_dirty',[H,_,Stored,M]),Stored=@=K),Deferred)
       ;Deferred=[],(K=['sk-fold',Args],'sk-fold-node-member'(['CPU','FoldAllCompiled',Args,_],[Node|_]),'sk-answers'(Node,Keys)->true
         ;K=['sk-group',Args],'sk-group-members'(K,Args,['sk-group-found',_,Keys])->true;Keys=[]))).

cn_determined(Id) :-
    cn_node(Id,'&sk_context',[_,_,H,K,R,Q,[],_,_,_,_]),
    '&sk_row'(H,Stored,R,Row),Stored=@=K,
    'sk-determined-row?'(['sk-row-item',Q,H,K,R,Row],true).

cn_pay(Id) :-
    cn_node(Id,S,[_,_,H,K,_,_,_,_,_,_,_]),cn_node_depth(Id,H,K,Depth),
    (S=='&sk_context_merge'->true
    ;'sk-evaluation-free-depth'(Free),Depth=<Free,'sk-take!'(sk_near_reserve,1,true)->true
    ;Depth>=1000000,cn_determined(Id)->true
    ;(K=['sk-key',Type,_]->'term-cost'(Type,Cost);Cost=1),
     ('sk-take!'(sk_eval_budget,Cost,true)->true;cn_determined(Id))).

cn_drain :-
    nb_getval(context_node_heap,Heap),
    (get_from_heap(Heap,At,Id,Rest)
    -> nb_setval(context_node_heap,Rest),
       (cn_rows('&sk_context_queued',[Id,At])
       ->cn_remove('&sk_context_queued',[Id,At]),(cn_node(Id,S,[D,_,_,K,_,_,E,_,_,_,Fresh]),Fresh\==true
       -> (\+cn_rows('&sk_given_granted',[Id,_]),cn_reusable(S,D,K,E,Reuse,_),Reuse\==Id -> cn_alias(Id,Reuse)
          ;S=='&sk_context',K=['sk-key'|_],cn_node(Id,_,[_,_,H,_,R|_]),
            '&sk_row'(H,_,R,['sk-row',['sk-ident',Rule,_,_],_,_,_]),'context-rule-visible?'(Rule,false)->true
          ;cn_pay(Id)->(cn_compute(Id)->true;true);query_metric_increment('rows-unpaid',_));true)
       ;true),cn_drain
    ; true).

cn_pay_conditions :-
    findall([Depth,Cost,Q,Id,R],
      (cn_rows('&sk_given_pending',[Id,R,Cost]),\+cn_rows('&sk_given_granted',[Id,R]),
       cn_node(Id,_,[_,_,H,K,_,Q,_,_,_,_,_]),cn_node_depth(Id,H,K,Depth),Depth<1000000),Claims),
    sort(Claims,Sorted),
    (Sorted=[]->true
    ;Sorted=[[_,Cost,_,Id,R]|_],
      ('sk-take!'(sk_eval_budget,Cost,true)
       ->cn_remove('&sk_given_pending',[Id,R,_]),cn_add('&sk_given_granted',[Id,R]),
         cn_dirty(Id,true),cn_drain,cn_pay_conditions
       ;query_metric_increment('conditions-unpaid',_))).

cn_need_closer(Depth,Keys) :-
    forall((member(K,Keys),'index-hash'(K,H),'&sk_needed'(H,Stored,Was),Stored=@=K,Was>Depth),
           retractall('&sk_needed'(H,Stored,Was))),cn_need(Depth,Keys,[]),cn_need_cached(Depth,Keys).
cn_seed_needed :-
    forall(('&sk_needed'(H,K,D),cn_key_nodes(H,K,_,Id),
            cn_node(Id,_,[_,_,_,_,_,_,E,_,_,V,Fresh]),Fresh\==true,
            (E=[]->(D=<2;V=='sk-none');cn_rows('&sk_context_need',[Id,Depth]),Depth<1000000)),cn_queue(Id)),
    forall((cn_rows('&sk_context_need',[Id,Depth]),Depth<1000000,
            cn_node(Id,S,[_,_,H,K,_,_,E,_,_,V,State]),State\==true,
            \+ (S=='&sk_context',K=['sk-key'|_],E=[],V\=='sk-none',
               cn_depth(H,K,D),D>2,D<1000000,\+cn_determined(Id))),cn_queue(Id)).
cn_instance_checks :-
    findall([H,F],(cn_rows('&sk_instance_changed',[H,F]),
                   \+cn_rows('&sk_instance_checked',[H])),Checks0),sort(Checks0,Checks),
    (Checks=[]->true
    ;forall(member([H,F],Checks),
      (cn_remove('&sk_instance_changed',[H,F]),cn_add('&sk_instance_checked',[H]),
       findall(M,(cn_rows('&sk_rate_dirty',[H,_,Stored,M]),Stored=@=F),Ms),
       findall(K,(cn_rows('&sk_row_input',[H,S,KH,R]),S=@=F,'&sk_row'(KH,K,R,_)),Readers),
       ('sk-ordinary-view'(H,F,0,V),V\=='sk-none',Ms\=[],Readers\=[]
       ->cn_need_closer(0,Readers),cn_need_closer(1,[F]),cn_need_closer(2,Ms),
         forall(cn_key_nodes(H,F,_,Id),cn_dirty(Id,true));true))),
     cn_seed_needed,cn_drain,cn_instance_checks).

cn_finish :-
    nb_getval(context_node_progress,Before),
    cn_instance_checks,cn_pay_conditions,cn_seed_needed,cn_drain,
    nb_getval(context_node_progress,After),(After>Before->cn_finish;cn_unpaid_folds).

% A cached consumer of an exact fold cannot remain current when the allowance
% leaves that fold unavailable. Its next read is pending on this same heap.
% Statistical parameters publish through the value/KL comparison instead.
cn_unpaid_folds :-
    findall(Id,(cn_rows('&sk_context',[_,Id,H,K,_,_,_,_,_,_,State]),
      (K=['sk-fold'|_];K=['sk-group'|_]),\+'sk-rate-fold?'(K,true),
      (State==false;State=wait(old,_)),cn_node_depth(Id,H,K,Depth),Depth<1000000),Ids),
    cn_stale_consumers(Ids,[]).
cn_stale_consumers([], _).
cn_stale_consumers([Id|Rest],Seen) :-
    (ord_memberchk(Id,Seen)->cn_stale_consumers(Rest,Seen)
    ;ord_add_element(Seen,Id,Next),
     findall(Reader,(cn_rows('&sk_context_reader',[Id,Reader]),
       cn_node(Reader,_,[_,_,_,ReaderKey|_]),
       (cn_node(Reader,_,[_,_,_,_,_,_,_,_,_,_,true])->cn_dirty(Reader,true);true),
       \+'sk-rate-fold?'(ReaderKey,true),
       \+ (cn_node(Reader,'&sk_context',[_,_,H,K,_,_,[],_,_,V,_]),K=['sk-key'|_],
           V\=='sk-none',cn_depth(H,K,D),D>2)),Readers),
     append(Rest,Readers,Work),cn_stale_consumers(Work,Next)).

'sk-evaluate!'(true) :-
    (context_active(C)->true;C=main),nb_setval(context_node_query_scope,C),
    empty_heap(Heap),nb_setval(context_node_heap,Heap),nb_setval(context_node_active,none),nb_setval(context_node_progress,0),nb_setval(context_node_push,0),
    cn_remove('&sk_context_queued',[_,_]),cn_remove('&sk_context_forced_used',[_,_]),
    forall((cn_rows('&sk_context_forced',[Id,Cause]),cn_node(Id,'&sk_context',[_,_,_,['sk-key'|_]|_])),
           cn_add('&sk_context_forced_used',[Id,Cause])),cn_remove('&sk_instance_checked',[_]),cn_remove('&sk_given_granted',[_,_]),
    forall(cn_rows('&sk_dirty',[_,K]),
      ('index-hash'(K,H),forall((cn_key_nodes(H,K,S,Id),(K=['sk-key'|_]->S=='&sk_context_merge';true)),cn_dirty(Id,true)),
       % Instance tallies are maintained even when the query asks for another
       % key. Their recorded observation inputs identify just the affected
       % samples; the ordinary need/heap then computes those samples.
       forall((cn_rows('&sk_instance_read',[H,FH,MH,Member]),'&sk_use'(MH,Stored,Fold),Stored=@=Member,
               'index-hash'(Fold,FH)),
         ('sk-rate-dirty!'(Fold,Member,_),forall(cn_key_nodes(MH,Member,_,Id),cn_dirty(Id,true)))),
       cn_members_changed(K,0))),cn_remove('&sk_dirty',[_,_]),
    forall(cn_rows('&sk_new',['sk-row-item',Q,H,K,R,_]),
      ('sk-drop-merged!'(K,_),cn_ensure('&sk_context',H,K,R,Q,[],Id),
       (cn_determined(Id)->cn_queue(Id);true))),
    cn_remove('&sk_new',[_,_,_,_,_,_]),
    cn_seed_needed,
    cn_drain,
    forall('&sk_needed'(_H,K,0),'sk-value'(K,'sk-any-filter',[],_)),cn_drain,cn_finish,
    'sk-context-metrics!'(_).

% Answer adapters can discover a prior or a constrained read after ordinary
% roots were evaluated. Drain those misses on this same heap and allowance.
 'sk-answer-roots!'(Goals,Materialize,Results) :-
    setup_call_cleanup(nb_setval(context_node_root,true),cn_answer(Goals,Values),nb_setval(context_node_root,false)),
    maplist('sk-publish-results'(Materialize),Values,Results),'sk-context-metrics!'(_).
cn_answer(Goals,Values) :-
    nb_getval(context_node_progress,Before),
    maplist(cn_read_root,Goals,Read),cn_drain,cn_finish,
    nb_getval(context_node_progress,After),(After>Before->cn_answer(Goals,Values);Values=Read).

cn_read_root(Goal,Values) :- copy_term_nat(Goal,Read),'sk-root-values'(Read,Values).

'sk-prime-keys!'(Keys,true) :-
    % Seed values are taken before the wave refreshes their readers. Priming
    % may merge new input facts, but must not consume downstream changes as
    % if the caller had already taken those derived values as seeds.
    cn_remove('&sk_context_need',[_,_]),
    setup_call_cleanup((nb_setval(context_node_priming,true),nb_setval(context_node_root,true)),
      ('sk-evaluate!'(_),forall(member(K,Keys),'sk-value'(K,'sk-any-filter',[],_)),cn_drain),
      (nb_setval(context_node_priming,false),nb_setval(context_node_root,false))).


'sk-readers-pending?'(K,B) :-
    'index-hash'(K,H),
    ((cn_rows('&sk_row_input',[H,S,RH,R]),S=@=K,'&sk_row'(RH,Owner,R,_),cn_digest(Owner,R,D),
      cn_rows('&sk_context',[D,Id,_,_,_,_,[],_,_,_,State]),
      (State\==true;cn_rows('&sk_given_pending',[Id,_,_])))
    ;cn_key_nodes(H,K,'&sk_context_merge',Source),cn_rows('&sk_context_reader',[Source,Id]),
      cn_node(Id,_,[_,_,_,_,_,_,_,_,_,_,State]),State\==true),!,B=true.
'sk-readers-pending?'(_,false).

'sk-context-metrics!'(true) :-
    (query_metrics_enabled(true)
    -> findall(D,cn_rows('&sk_context',[D,_,_,_,_,_,_,_,_,_,_]),Ds),msort(Ds,Sorted),
       cn_counts(Sorted,Counts),sum_list(Counts,Total),length(Counts,Rows),
       (Counts=[]->Max=0,Mean=0;max_list(Counts,Max),Mean is Total/Rows),
       query_metric_set('context-node-count',Total,_),query_metric_set('context-classes-max',Max,_),query_metric_set('context-classes-mean',Mean,_)
    ;true).
cn_counts([],[]).
cn_counts([D|Ds],[N|Ns]) :- cn_run(D,Ds,Rest,1,N),cn_counts(Rest,Ns).
cn_run(D,[D|Ds],Rest,N,Count) :- !,Next is N+1,cn_run(D,Ds,Rest,Next,Count).
cn_run(_,Rest,Rest,N,N).

'sk-ordinary-versions'(H,K,Versions) :-
    findall(['sk-version',Q,R,V],
      (cn_key_nodes(H,K,'&sk_context',Id),cn_node(Id,_,[_,_,_,_,R,Q,[],_,_,V,State]),
       (State==true;State==false,cn_depth(H,K,Depth),Depth>2),'sk-live-view?'(V,true)),Unsorted),sort(Unsorted,Versions).
