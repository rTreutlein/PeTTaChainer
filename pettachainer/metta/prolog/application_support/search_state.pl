% Search ownership, pending components and bounded retirement.
% Fact selection belongs to the reader layer below this search service.
% An extensional functional node with its unique answer has no remaining
% producer work. Consume that key directly instead of allocating a lease and
% immediately retiring it again.
'sk-functional-exhausted?'(N, Exhausted) :-
    ( N = [Type,Context|_], functional_key(Type, Context, Key),
      term_hash(Key, Hash), functional_value(Hash, Key, _),
      'sk-node-hash'(N, H), '&sk_answer'(H, Stored, _), attribute_free_variant(Stored, N)
    -> Exhausted = true ; Exhausted = false ).

% A delivered value exhausts this subscription. Existing rows and key reads
% remain live for evidence updates; unassigned functional keys remain open.
% Snapshot only functional subscriptions, before extension binds their node.
'sk-functional-subscription'(W, Subscription) :-
    ( W = ['sk-partial',_,_,_,_,[N|_],_], N = [Type,Context|_],
      functional_key(Type, Context, Key), term_hash(Key, Hash), functional_value(Hash, Key, _)
    -> 'sk-node-hash'(N, H),
       ( sk_wait_ref(H, N, W, Ref) -> copy_term_nat([H,N,Ref], Subscription) ; Subscription = [] )
    ; Subscription = [] ).

'sk-functional-delivered!'([], true).
% A waiter a deferred join holds by its identity (sk-defer-join!) stays until
% that join is read again: its delivery was not made.
'sk-functional-delivered!'([H,N,Ref], true) :-
    ( '&sk_answer'(H, Stored, _), attribute_free_variant(Stored, N),
      clause(sk_wait_payload(_,_,_,_), true, Ref),
      \+ ( sk_wait_id_of(Ref, Id), '&sk_deferred_joins'(_, _, ['sk-join', _, _, Id]) )
    -> sk_retire_wait_ref(Ref) ; true ).

sk_queue_retirement(H, Key) :-
    ( sk_retire_queue(H, Key) -> true ; assertz(sk_retire_queue(H, Key)) ).

sk_search_init :-
    (   nb_current(sk_search_listening, true) -> true
    ;   forall(member(Space/Arity, [sk_wait_payload/4, '&sk_join_link'/2, '&sk_child'/4,
                                   '&sk_deferred_joins'/3, '&sk_deferred'/3,
                                   '&sk_expanded'/2]),
               prolog_listen(user:Space/Arity, sk_search_changed(Space))),
        nb_setval(sk_search_listening, true)
    ).

% Use the same fact selection as sk-complete-row!: forward copies, filtered
% contexts and materialized facts cannot accidentally turn a cache into a
% reason to retire a search. Only known true/false facts are absorbing under
% conditioning; a fractional confidence-1 fact keeps its derivations.
'sk-known-conclusion?'(Conclusion, Known) :-
    sk_search_init,
    (   sk_search_key(Conclusion, _, [Type, Context]),
        'sk-leaf-facts'(Type, Context, 'sk-any-filter', Facts),
        member([_, [_, FactContext, _], Proof, ['STV', S, C]], Facts),
        C >= 1, (S =:= 0; S =:= 1),
        % A borrowed world fact cannot absorb an assumption-dependent path
        % that a private judgment still needs to discover.
        ( FactContext == 'MAIN' -> true ; 'assumption-proof?'(Proof, true) )
    ->  Known = true
    ;   Known = false
    ).

sk_search_index(Conclusion, Space, Ref) :-
    (   sk_search_key(Conclusion, H, _)
    ->  assertz(sk_search_clause(H, Space, Ref))
    ;   true ).

% Ownership rows copy only the hash, store kind and exact clause reference.
% Validate collisions against the owned clause, where the key already lives.
% Join digests retain the existing 60-bit identity contract used by thawing.
sk_search_owned(H, Key, Space, Ref) :-
    term_hash(Key, H), sk_search_clause(H, Space, Ref),
    ( Space == sk_functional_wait
    -> clause(sk_wait_payload(_, [Type,Context|_], _, _), true, Ref),
       functional_key(Type, Context, Stored), Key = Stored
    ; Space == '&sk_join_link'
    -> Key = [Type,Context], ground(Key),
       'link-digest'(['sk-key',Type,Context], D),
       clause('&sk_join_link'(D,_), true, Ref)
    ; ( Space == sk_wait_payload
      -> clause(sk_wait_payload(_, _, TemplateId, B), true, Ref),
         sk_wait_template(_, _, TemplateId, ['sk-partial',_,_,C|_], B)
      ; Space == sk_child_claim -> clause(sk_child_claim(_, _, C), true, Ref)
      ; sk_search_conclusion(Space, Row, C), clause(Row, true, Ref) ),
      sk_search_key(C, _, Key) ).

% Keep the conclusion index for thaw replay, and the waiter reference for
% lifetime. Capture the original partial before its answer binds open slots.
'sk-store-join!'(Digest, Waiter, Conclusion, New) :-
    sk_search_init,
    ( Conclusion = [Head|_], Head == 'CPU'
    -> Conclusion = [_,Fun,Args,_],
       ( Fun == 'GroupedFoldAllCompiled' -> Key = ['sk-group',Args] ; Key = ['sk-fold',Args] )
    ; Conclusion = [Type,Context|_], Key = ['sk-key',Type,Context] ),
    'link-digest'(Key, KeyDigest),
    ( '&sk_join_link'(KeyDigest, Digest) -> New = false
    ; assertz('&sk_join_link'(KeyDigest, Digest), Ref),
      sk_search_index(Conclusion, '&sk_join_link', Ref),
      Waiter = ['sk-partial',_,_,_,_,[N|_],_], 'sk-node-hash'(N,H),
      ( sk_wait_ref(H, N, Waiter, WaitRef) -> assertz(sk_join_wait(WaitRef, Ref)) ; true ),
      ( sk_search_key(Conclusion, _, [T,C]) -> 'sk-retire-known!'(T,C,true) ; true ),
      New = true ).

% A join whose row could not be paid for forgets it extended, so the restart
% of its rule extends it again (sk-defer-rule!).
'sk-unstore-join!'(Digest, Conclusion, true) :-
    ( Conclusion = [Head|_], Head == 'CPU'
    -> Conclusion = [_,Fun,Args,_],
       ( Fun == 'GroupedFoldAllCompiled' -> Key = ['sk-group',Args] ; Key = ['sk-fold',Args] )
    ; Conclusion = [Type,Context|_], Key = ['sk-key',Type,Context] ),
    'link-digest'(Key, KeyDigest),
    ( retract('&sk_join_link'(KeyDigest, Digest)) -> true ; true ).

% A waiter batch already needs this digest for its child link. Retain a
% lease by clause reference, so retraction never hashes the partial again.
% Reopening an evicted cache reuses the subscription and its child lease.

'sk-store-wait!'(D, H, N, Waiter, true) :-
    sk_search_init,
    ( sk_wait_ref(H, N, Waiter, _) -> true
    ; Waiter = ['sk-partial', _, Id, C, Done, _, _], length(Done, Pos),
    ( sk_wait_template(Id, Pos, TemplateId, Template, Bindings), subsumes_term(Template, Waiter)
    -> Template = Waiter
    ; ccls_index(Conclusion, Id, Premises),
      copy_term_nat(Conclusion, Owner),
      length(Prefix, Pos), append(Prefix, Remaining, Premises), reverse(Prefix, Consumed),
      term_subsumer(['sk-partial', Owner, Id, Conclusion, Consumed, Remaining, _], Waiter, Template),
      term_variables(Template, Bindings),
      flag(sk_wait_template_id, TemplateId, TemplateId + 1),
      assertz(sk_wait_template(Id, Pos, TemplateId, Template, Bindings)),
      Template = Waiter ),
    assertz(sk_wait_payload(H, N, TemplateId, Bindings), Ref),
    variant_hash([N, TemplateId|Bindings], WaitHash), assertz(sk_wait_key(WaitHash, Ref)),
    flag(sk_wait_id, WaitId, WaitId + 1), assertz(sk_wait_id(WaitId, Ref)), assertz(sk_wait_id_of(Ref, WaitId)),
    assertz(sk_child_users(D, Ref)), sk_search_index(C, sk_wait_payload, Ref),
    ( N = [Type,Context|_], functional_key(Type, Context, Key), term_hash(Key, Hash),
      \+ functional_value(Hash, Key, _)
    -> assertz(sk_search_clause(Hash, sk_functional_wait, Ref)) ; true ) ).

% A continuation template is the compiled rule split at a premise position.
% Context routing and query proof patterns widen only the affected slots.
% Generalization preserves sharing only where both the compiled rule and
% the contextualized join share it; it never binds the join being encoded.
% Templates are shared, immutable, and leave with their last subscription.
:- use_module(library(terms), [term_subsumer/3]).
sk_retire_wait_ref(Ref) :-
    setup_call_cleanup(nb_setval(sk_retiring, true), erase(Ref), nb_delete(sk_retiring)).

'sk-store-child!'(D, H, Owner, Child, CH, true) :-
    sk_search_init, assertz('&sk_child'(H, Owner, Child, CH), Ref),
    assertz(sk_child_edge(D, Ref)).

% Fixed leases carry the actual join conclusion, not just its open owner.
'sk-keep-child!'(D, Conclusion, true) :-
    sk_search_init, 'link-digest'(['sk-child-claim', D, Conclusion], Claim),
    ( sk_child_claim(Claim, _, _) -> true
    ; assertz(sk_child_claim(Claim, D, Conclusion), Ref),
      sk_search_index(Conclusion, sk_child_claim, Ref),
      ( sk_search_key(Conclusion, _, [Type, Context]) -> 'sk-retire-known!'(Type, Context, true) ; true ) ).

sk_search_conclusion('&sk_deferred_joins', '&sk_deferred_joins'(_, _, ['sk-join', C|_]), C).
sk_search_conclusion('&sk_deferred', '&sk_deferred'(_, _, ['sk-deferred', C|_]), C).

sk_search_changed(Space, assertz, Ref) :- !,
    ( sk_search_conclusion(Space, Row, C), clause(Row, true, Ref)
    -> sk_search_index(C, Space, Ref)
    ; Space == '&sk_expanded', clause('&sk_expanded'(H, N), true, Ref)
    -> sk_unwatch_fact(H, N)
    ; true ).
sk_search_changed(Space, retract, Ref) :- !,
    retractall(sk_search_clause(_, _, Ref)),
    (   Space == sk_wait_payload
    ->  clause(sk_wait_payload(_, N, TemplateId, Bindings), true, Ref),
        variant_hash([N, TemplateId|Bindings], WaitHash), retract(sk_wait_key(WaitHash, Ref)),
        ( retract(sk_wait_id_of(Ref, WaitId)) -> retract(sk_wait_id(WaitId, Ref)) ; true ),
        ( once((clause(sk_wait_payload(_, _, TemplateId, _), true, Other), Other \== Ref)) -> true
        ; retractall(sk_wait_template(_, _, TemplateId, _, _)) ),
        ( sk_join_wait(Ref, _) -> assertz(sk_retire_wait(Ref)) ; true ),
        forall(retract(sk_child_users(D, Ref)), sk_release_child(D))
    ;   Space == '&sk_join_link'
    ->  retractall(sk_join_wait(_, Ref))
    ;   Space == '&sk_child', clause('&sk_child'(OH, O, N, NH), true, Ref),
        retract(sk_child_edge(D, Ref))
    ->  forall(clause(sk_child_claim(_, D, _), true, Claim), sk_erase_claim(Claim)),
        retractall(sk_child_debt(_, D)),
        (   nb_current(sk_retiring, true)
        ->  retractall('&sk_link'(D)), pw_unlink(OH, O, NH, N),
            pw_drop_unused(OH, O), pw_drop_unused(NH, N)
        ;   true )
    ;   true ).
sk_search_changed(_, _, _).

sk_erase_claim(Ref) :-
    retractall(sk_search_clause(_, _, Ref)), erase(Ref).

% Withdrawal uses the same lease release as known-conclusion retirement.
% Context cleanup keeps its own pending-graph transitions instead.

'sk-retire-wait!'(Hash, Premise, Waiter, true) :-
    ( sk_wait_ref(Hash, Premise, Waiter, Ref) -> sk_retire_wait_ref(Ref) ; true ).

% Ordinary context cleanup retains its existing pending-graph transitions.
% A released join can still lead to pending premise work shared with later
% queries. Keep that traversal until its component settles, then retire it
% by component index; removing it sooner changes finite-budget answers.
sk_release_child(D) :-
    (   nb_current(sk_retiring, true),
        \+ sk_child_users(D, _), \+ sk_child_claim(_, D, _), sk_child_edge(D, Ref)
    ->  clause('&sk_child'(_, _, N, NH), true, Ref),
        (   pw_known(NH, N, Id), pw_find(Id, R), pw_pending_rep(R)
        ->  ( sk_child_debt(R, D) -> true ; assertz(sk_child_debt(R, D)) )
        ;   erase(Ref) )
    ;   true ).

% Ingestion only records an indexed retirement. A bounded slice runs at query
% activation and after its answers: even closing a long-deferred outcome does
% not scan the history or erase all its owned records during the fact add.
'sk-retire-known!'(Type, Context, true) :-
    sk_search_init,
    (   sk_search_key([Type, Context], H, Key),
        once((sk_search_owned(H, Key, _, _) ; sk_search_node(H, Key, _, _))),
        'sk-known-conclusion?'([Type, Context], true)
    ->  sk_queue_retirement(H, Key)
    ;   true ).

'sk-retire-searches!'(true) :-
    setup_call_cleanup(nb_setval(sk_retiring, true), sk_retire_slice(512), nb_delete(sk_retiring)).

sk_retire_slice(0) :- !.
sk_retire_slice(Units) :-
    (   sk_retire_wait(WaitRef)
    ->  ( sk_join_wait(WaitRef, JoinRef) -> erase(JoinRef)
        ; retract(sk_retire_wait(WaitRef)) ),
        Left is Units - 1, sk_retire_slice(Left)
    ;   sk_retire_queue(H, Key)
    ->  (   sk_search_owned(H, Key, Space, Ref)
        ->  ( Key = functional(_,_,_)
            -> ( clause(sk_wait_payload(_, N, _, _), true, Ref), 'sk-functional-conflict?'(N, true)
               -> sk_retire_clause(Space, Ref)
               ; retractall(sk_search_clause(H, Space, Ref)) )
            ; sk_retire_clause(Space, Ref) )
        ;   clause(sk_search_node(H, Key, NH, N), true, NodeRef)
        ->  erase(NodeRef), pw_drop_unused(NH, N)
        ;   retract(sk_retire_queue(H, Key)) ),
        Left is Units - 1, sk_retire_slice(Left)
    ;   sk_retire_component(R)
    ->  (   pw_pending_rep(R) -> retract(sk_retire_component(R))
        ;   clause(sk_child_debt(R, D), true, Ref)
        ->  erase(Ref), sk_release_child(D)
        ;   retract(sk_retire_component(R)) ),
        Left is Units - 1, sk_retire_slice(Left)
    ;   true ).

sk_retire_clause(Space, Ref) :-
    % A ground unexpanded premise used its waiter as a fact subscription.
    % Preserve that read once per node, without the obsolete join payload.
    (   memberchk(Space, [sk_wait_payload,sk_functional_wait]), clause(sk_wait_payload(H, N, _, _), true, Ref), N = [T, C, _, _],
        sk_search_key([T, C], _, _), 'sk-functional-conflict?'(N, false),
        \+ ( '&sk_expanded'(H, S), attribute_free_variant(S, N) ),
        'link-digest'(['sk-fact-watch', N], D), \+ '&sk_fact_watch'(_, D, _)
    ->  assertz('&sk_fact_watch'(H, D, N))
    ;   true ),
    (   memberchk(Space, ['&sk_deferred_joins', '&sk_deferred']), clause(Row, true, Ref)
    ->  (   Row = '&sk_deferred_joins'(H, _, ['sk-join', O|_])
        ;   Row = '&sk_deferred'(H, _, ['sk-deferred', O|_]) ),
        'sk-work!'(H, O, -1, [])
    ;   true ),
    ( Space == sk_child_claim
    -> clause(sk_child_claim(_, D, _), true, Ref), sk_erase_claim(Ref), sk_release_child(D)
    ; erase(Ref) ).


pw_drop_unused(H, N) :-
    (   pw_known(H, N, Id), pw_find(Id, R), pw_size(R, 1), pw_deg(R, 0, 0),
        \+ holds_work(H)
    ->  (   'sk-known-conclusion?'(N, true)
        ->  forall(clause('&sk_score'(H, S, _), true, Ref), (attribute_free_variant(S, N) -> erase(Ref);true))
        ;   true ),
        'sk-drop-pending!'(H, N, [])
    ;   true ).

