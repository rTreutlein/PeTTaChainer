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
'sk-functional-delivered!'([H,N,Ref], true) :-
    ( '&sk_answer'(H, Stored, _), attribute_free_variant(Stored, N),
      clause(sk_wait_payload(_,_,_,_), true, Ref)
    -> sk_retire_wait_ref(Ref) ; true ).

sk_queue_retirement(H, Key) :-
    ( sk_retire_queue(H, Key) -> true ; assertz(sk_retire_queue(H, Key)) ).

% --- Pending work (skeleton.metta, "Pending work") ---------------------------
%
% Which nodes' searches may still have work: the node or one below it is
% unexpanded or holds parked deliveries, deferred joins or deferred rows. A
% skeleton is cyclic (inverted rules, a rule's truth read through its own
% instances), and every node of a cycle reaches what any of them reaches, so
% the nodes are kept as their strongly connected components, condensed into an
% acyclic graph. A component counts its nodes' work items and its child
% components that are pending; it is pending while either count is positive.
% A change in a component's state moves its parents' counts, up to the first
% parent whose state stays, so the state is always exact and a lookup is a
% union-find step.
%
% A child link joins two components when the child's component reaches the
% owner's: a search forward from the child and backward from the owner, one
% component at a time each, until one side is exhausted, so it costs the
% smaller side (a new node has no children, a new root no parents). The
% components on the paths from child to owner become one.
%
% pw_id(NodeHash, Node, Id); pw_up(Id, Parent) for a merged id; for a
% component Rep: pw_size(Rep, Nodes), pw_work(Rep, Items), pw_pend(Rep,
% PendingChildren), pw_deg(Rep, Children, Parents); pw_out(Rep, Child, Links)
% and pw_in(Child, Rep, Links) for the condensed edges, with the child links
% each stands for.
:- dynamic pw_id/3, pw_up/2, pw_size/2, pw_work/2, pw_pend/2, pw_deg/3, pw_out/3, pw_in/3.
:- dynamic '&sk_expanded'/2, '&sk_link'/1, '&sk_join_link'/2, '&sk_child'/4,
           '&sk_parked'/3, '&sk_deferred_joins'/3, '&sk_deferred'/3, '&sk_fact_watch'/3.

% Search work is indexed by the ground statement/context it concludes, apart
% from its awaited premise index. Clause references erase exactly that work;
% retract listeners keep the index correct for ordinary context cleanup too.
% None of the values, facts, rows or sample/tally stores belong to this index.
:- dynamic sk_search_clause/3, sk_search_node/4, sk_retire_queue/2,
           sk_child_edge/2, sk_child_users/2, sk_child_claim/3,
           sk_child_debt/2, sk_retire_component/1, sk_join_wait/2, sk_retire_wait/1.
sk_search_init :-
    (   nb_current(sk_search_listening, true) -> true
    ;   forall(member(Space/Arity, [sk_wait_payload/4, '&sk_join_link'/2, '&sk_child'/4,
                                   '&sk_deferred_joins'/3, '&sk_deferred'/3,
                                   '&sk_expanded'/2]),
               prolog_listen(user:Space/Arity, sk_search_changed(Space))),
        nb_setval(sk_search_listening, true)
    ).

sk_search_key([Type, Context|Rest], Hash, [Type, Context]) :-
    % Query adapters read a statement and reconstruct its proof; they are
    % exempt from the known-row rule in sk-complete-row! too.
    ( Rest = [Proof|_], nonvar(Proof), Proof = [Head|_], var(Head) -> fail ; true ),
    nonvar(Context), Context = [_, _, _], ground(Type-Context),
    term_hash([Type, Context], Hash).

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

% A waiter batch already needs this digest for its child link. Retain a
% lease by clause reference, so retraction never hashes the partial again.
% Reopening an evicted cache reuses the subscription and its child lease.

'sk-store-wait!'(D, H, N, Waiter, true) :-
    sk_search_init,
    ( sk_wait_ref(H, N, Waiter, _) -> true
    ; Waiter = ['sk-partial', _, Id, C, Done, _, _], length(Done, Pos),
    ( sk_wait_template(Id, Pos, TemplateId, Template, Bindings), subsumes_term(Template, Waiter)
    -> Template = Waiter
    ; rules('runtime-rule-row', Id, Conclusion, Premises),
      copy_term_nat(Conclusion, Owner),
      length(Prefix, Pos), append(Prefix, Remaining, Premises), reverse(Prefix, Consumed),
      term_subsumer(['sk-partial', Owner, Id, Conclusion, Consumed, Remaining, _], Waiter, Template),
      term_variables(Template, Bindings),
      flag(sk_wait_template_id, TemplateId, TemplateId + 1),
      assertz(sk_wait_template(Id, Pos, TemplateId, Template, Bindings)),
      Template = Waiter ),
    assertz(sk_wait_payload(H, N, TemplateId, Bindings), Ref),
    variant_hash([N, TemplateId|Bindings], WaitHash), assertz(sk_wait_key(WaitHash, Ref)),
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

sk_search_conclusion('&sk_deferred_joins', '&sk_deferred_joins'(_, _, ['sk-join', ['sk-partial', _, _, C|_], _]), C).
sk_search_conclusion('&sk_deferred', '&sk_deferred'(_, _, ['sk-deferred', _, _, C|_]), C).

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

% The node hash is already available at expansion/context cleanup. Only its
% few compact subscriptions need alpha comparison; no digest is computed.
sk_unwatch_fact(H, N) :-
    forall(clause('&sk_fact_watch'(H, _, Stored), true, Ref),
           ( attribute_free_variant(Stored, N) -> erase(Ref) ; true )).

% The typed native boundary exposes records whose schema is supplied here,
% rather than by a MeTTa add-atom specialization.
'sk-fact-watches'(H, Nodes) :- findall(N, '&sk_fact_watch'(H, _, N), Nodes).

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
    ->  (   Row = '&sk_deferred_joins'(H, _, ['sk-join', ['sk-partial', O|_], _])
        ;   Row = '&sk_deferred'(H, _, ['sk-deferred', O|_]) ),
        'sk-work!'(H, O, -1, [])
    ;   true ),
    ( Space == sk_child_claim
    -> clause(sk_child_claim(_, D, _), true, Ref), sk_erase_claim(Ref), sk_release_child(D)
    ; erase(Ref) ).

% Removing one actual child link removes just its share of a condensed edge.
% A merged component need not be split: its remaining nodes and work still
% share the conservative component, as on context retirement; obsolete
% outgoing links no longer keep any parent pending.
pw_unlink(OH, O, NH, N) :-
    (   pw_known(OH, O, U), pw_known(NH, N, V), pw_find(U, RU), pw_find(V, RV), RU \== RV,
        retract(pw_out(RU, RV, M0))
    ->  retract(pw_in(RV, RU, M0)),
        (   M0 > 1 -> M is M0 - 1, assertz(pw_out(RU, RV, M)), assertz(pw_in(RV, RU, M))
        ;   pw_deg_add(RU, -1, 0), pw_deg_add(RV, 0, -1),
            ( pw_pending_rep(RV) -> pw_add_pend(RU, -1) ; true ) )
    ;   true ).

pw_drop_unused(H, N) :-
    (   pw_known(H, N, Id), pw_find(Id, R), pw_size(R, 1), pw_deg(R, 0, 0),
        \+ holds_work(H)
    ->  (   'sk-known-conclusion?'(N, true)
        ->  forall(clause('&sk_score'(H, S, _), true, Ref), (attribute_free_variant(S, N) -> erase(Ref);true))
        ;   true ),
        'sk-drop-pending!'(H, N, [])
    ;   true ).

% A node's id, created with one work item when the node is unexpanded.
pw_node(H, N, Id) :-
    (   pw_known(H, N, Id) -> true
    ;   flag(pw_next_id, Id, Id + 1),
        assertz(pw_id(H, N, Id)),
        ( '&sk_expanded'(H, S), attribute_free_variant(S, N) -> W = 0 ; W = 1 ),
        ( sk_search_key(N, KH, Key) -> assertz(sk_search_node(KH, Key, H, N)) ; true ),
        assertz(pw_size(Id, 1)), assertz(pw_work(Id, W)), assertz(pw_pend(Id, 0)), assertz(pw_deg(Id, 0, 0))
    ).

pw_known(H, N, Id) :- pw_id(H, S, Id), attribute_free_variant(S, N), !.

pw_find(Id, Rep) :-
    (   pw_up(Id, Up)
    ->  pw_find(Up, Rep),
        ( Up == Rep -> true ; retract(pw_up(Id, Up)), assertz(pw_up(Id, Rep)) )
    ;   Rep = Id
    ).

pw_pending_rep(R) :- ( pw_work(R, W), W > 0 -> true ; pw_pend(R, P), P > 0 ).

'sk-pending?'(H, N, B) :-
    (   pw_known(H, N, Id), pw_find(Id, R), pw_pending_rep(R) -> B = true ; B = false ).

% A node's pending children, each as (sk-node-at hash child).
'sk-pending-children'(H, N, Children) :-
    findall(['sk-node-at', CH, C],
            ( '&sk_child'(H, O, C, CH), attribute_free_variant(O, N),
              pw_known(CH, C, Id), pw_find(Id, R), pw_pending_rep(R) ),
            Children).

'sk-holds-work?'(H, B) :- ( holds_work(H) -> B = true ; B = false ).

holds_work(H) :- ( '&sk_parked'(H, _, _) ; '&sk_deferred_joins'(H, _, _) ; '&sk_deferred'(H, _, _) ), !.

% A node's work items change by Delta: one for being unexpanded (taken when it
% is expanded), one per parked delivery, deferred join and deferred row. A
% node without an id has none counted; work added gives it one.
'sk-work!'(H, N, Delta, []) :-
    (   Delta > 0 -> pw_node(H, N, Id), pw_add_work(Id, Delta)
    ;   pw_known(H, N, Id) -> pw_add_work(Id, Delta)
    ;   true
    ).

pw_add_work(Id, Delta) :-
    pw_find(Id, R),
    ( pw_pending_rep(R) -> Old = true ; Old = false ),
    retract(pw_work(R, W0)), W is W0 + Delta, assertz(pw_work(R, W)),
    pw_changed(R, Old).

% After a component's counts changed: when its state flipped, each parent's
% count of pending children moves with it.
pw_changed(R, Old) :-
    ( pw_pending_rep(R) -> New = true ; New = false ),
    (   Old == New -> true
    ;   ( New == true -> D = 1 ; D = -1 ),
        forall(pw_in(R, P, _), pw_add_pend(P, D)),
        ( New == false, sk_child_debt(R, _), \+ sk_retire_component(R)
        -> assertz(sk_retire_component(R)) ; true )
    ).

pw_add_pend(P, D) :-
    ( pw_pending_rep(P) -> Old = true ; Old = false ),
    retract(pw_pend(P, P0)), P1 is P0 + D, assertz(pw_pend(P, P1)),
    pw_changed(P, Old).

% A new child link from owner to child.
'sk-link-pending!'(OH, Owner, CH, Child, []) :-
    pw_node(OH, Owner, U), pw_node(CH, Child, V),
    pw_find(U, RU), pw_find(V, RV),
    (   RU == RV -> true
    ;   retract(pw_out(RU, RV, M0))
    ->  M is M0 + 1, assertz(pw_out(RU, RV, M)),
        retract(pw_in(RV, RU, M0)), assertz(pw_in(RV, RU, M))
    ;   pw_deg(RV, Children, _), Children > 0, pw_deg(RU, _, Parents), Parents > 0,
        pw_reaching(RV, RU, Merge)
    ->  pw_merge(Merge)
    ;   assertz(pw_out(RU, RV, 1)), assertz(pw_in(RV, RU, 1)),
        pw_deg_add(RU, 1, 0), pw_deg_add(RV, 0, 1),
        ( pw_pending_rep(RV) -> pw_add_pend(RU, 1) ; true )
    ).

% A child with no children, or an owner with no parents, closes no cycle,
% which settles most links (a new node, a new root) without a search. The
% degrees say so: pw_out and pw_in share their first argument with every link
% of a component with many children, such as a fold over one member per
% decision, so a lookup by it would read all of them.
%
% The components on a path from From to To, when there is one: a search
% forward from From and one backward from To read one link each in turn
% until one is exhausted. Neither passes the other's start, since a path from
% From to To ends at To. The exhausted search found every component on such a
% path; those are the ones whose links within what it found lead back to the
% other start. So the cost is twice the smaller search's links: linking a new
% node under a large component never reads that component's links.
pw_reaching(From, To, Merge) :-
    empty_nb_set(F), add_nb_set(From, F), empty_nb_set(B), add_nb_set(To, B),
    pw_alternate([To], [From], 0, 0, From, To, F, B, Side),
    (   Side == forward
    ->  add_nb_set(To, F, false), pw_on_paths(F, pw_out, To, Merge)
    ;   add_nb_set(From, B, false), pw_on_paths(B, pw_in, From, Merge)
    ).

% pw_alternate(+BackwardStack, +ForwardStack, +BackwardLinks, +ForwardLinks,
% ..., -Exhausted): each turn the search that will have read fewer links
% after expanding its next component expands it.
pw_alternate([], _, _, _, _, _, _, _, backward) :- !.
pw_alternate(_, [], _, _, _, _, _, _, forward) :- !.
pw_alternate([Z|Bs], [X|Fs], CB, CF, From, To, F, B, Side) :-
    ( Z == From -> DB = 0 ; pw_deg(Z, _, DB) ),
    ( X == To -> DF = 0 ; pw_deg(X, DF, _) ),
    (   CB + DB =< CF + DF
    ->  ( Z == From -> Bs1 = Bs ; findall(P, pw_in(Z, P, _), Ps), pw_visit(Ps, B, Bs, Bs1) ),
        CB1 is CB + DB,
        pw_alternate(Bs1, [X|Fs], CB1, CF, From, To, F, B, Side)
    ;   ( X == To -> Fs1 = Fs ; findall(Y, pw_out(X, Y, _), Ys), pw_visit(Ys, F, Fs, Fs1) ),
        CF1 is CF + DF,
        pw_alternate([Z|Bs], Fs1, CB, CF1, From, To, F, B, Side)
    ).

pw_visit([], _, Stack, Stack).
pw_visit([Y|Ys], Set, Stack0, Stack) :-
    (   add_nb_set(Y, Set, true) -> pw_visit(Ys, Set, [Y|Stack0], Stack)
    ;   pw_visit(Ys, Set, Stack0, Stack)
    ).

% The components of a search's set from which its Edge links, staying in
% the set, lead to Start: Start's own links are not read.
pw_on_paths(Set, Edge, Start, Found) :-
    nb_set_to_list(Set, Members),
    findall(Y-Z, ( member(Z, Members), Z \== Start, call(Edge, Z, Y, _), add_nb_set(Y, Set, false) ), Back),
    keysort(Back, Sorted), group_pairs_by_key(Sorted, Grouped), list_to_assoc(Grouped, Into),
    empty_nb_set(Seen), add_nb_set(Start, Seen),
    pw_back([Start], Into, Seen),
    nb_set_to_list(Seen, Found).

pw_back([], _, _).
pw_back([Y|Ys], Into, Seen) :-
    (   get_assoc(Y, Into, Zs) -> findall(Z, ( member(Z, Zs), add_nb_set(Z, Seen, true) ), New) ; New = [] ),
    append(New, Ys, Next),
    pw_back(Next, Into, Seen).

% Merges components into the largest (the lowest id among equals): their
% links to one another vanish, their other links move to it, and each outside
% parent counts the merged component once, by its state after the merge.
% Each count changes in one step that passes a flipped state on, so every
% parent always counts its children's current states.
pw_merge(Members) :-
    findall(S-R, ( member(R, Members), pw_size(R, S0), S is -S0 ), Sized),
    keysort(Sized, [_-R0|_]),
    findall(R, ( member(R, Members), pw_pending_rep(R) ), Pending),
    findall(P, ( member(R, Members), pw_in(R, P, _), \+ memberchk(P, Members) ), Ps),
    sort(Ps, Parents),
    findall(P-K, ( member(P, Parents),
                   aggregate_all(count, ( member(R, Pending), pw_in(R, P, _) ), K) ),
            ParentCounts),
    forall(( member(Y, Members), Y \== R0, retract(pw_out(R0, Y, _)) ),
           ( retract(pw_in(Y, R0, _)), pw_deg_add(R0, -1, 0),
             ( memberchk(Y, Pending) -> pw_bump(pw_pend, R0, -1) ; true ) )),
    forall(( member(X, Members), X \== R0 ), pw_absorb(R0, X, Members)),
    ( pw_pending_rep(R0) -> Now = 1 ; Now = 0 ),
    forall(member(P-K, ParentCounts),
           ( D is Now - K, ( D =:= 0 -> true ; pw_add_pend(P, D) ) )),
    ( Now =:= 0, sk_child_debt(R0, _), \+ sk_retire_component(R0)
    -> assertz(sk_retire_component(R0)) ; true ).

pw_absorb(R0, X, Members) :-
    assertz(pw_up(X, R0)),
    forall(retract(sk_child_debt(X, D)), assertz(sk_child_debt(R0, D))),
    retractall(sk_retire_component(X)),
    retract(pw_size(X, SX)), pw_bump(pw_size, R0, SX),
    retract(pw_work(X, WX)), pw_bump(pw_work, R0, WX),
    retract(pw_pend(X, _)), retract(pw_deg(X, _, _)),
    forall(retract(pw_out(X, Y, M)),
           (   retract(pw_in(Y, X, M)),
               (   memberchk(Y, Members) -> ( Y == R0 -> pw_deg_add(R0, 0, -1) ; true )
               ;   retract(pw_out(R0, Y, M0))
               ->  M1 is M0 + M, assertz(pw_out(R0, Y, M1)), retract(pw_in(Y, R0, M0)), assertz(pw_in(Y, R0, M1)),
                   pw_deg_add(Y, 0, -1)
               ;   assertz(pw_out(R0, Y, M)), assertz(pw_in(Y, R0, M)), pw_deg_add(R0, 1, 0),
                   ( pw_pending_rep(Y) -> pw_bump(pw_pend, R0, 1) ; true )
               ) )),
    forall(retract(pw_in(X, P, M)),
           (   retract(pw_out(P, X, M)),
               (   memberchk(P, Members) -> true
               ;   retract(pw_out(P, R0, M0))
               ->  M1 is M0 + M, assertz(pw_out(P, R0, M1)), retract(pw_in(R0, P, M0)), assertz(pw_in(R0, P, M1)),
                   pw_deg_add(P, -1, 0)
               ;   assertz(pw_out(P, R0, M)), assertz(pw_in(R0, P, M)), pw_deg_add(R0, 0, 1)
               ) )).

pw_deg_add(R, DO, DI) :-
    retract(pw_deg(R, O0, I0)), O is O0 + DO, I is I0 + DI, assertz(pw_deg(R, O, I)).

pw_bump(Count, R, D) :-
    Old =.. [Count, R, V0], retract(Old), V is V0 + D, New =.. [Count, R, V], assertz(New).

% A node of a query's hypothetical context leaves with it. Its component goes
% once all its nodes went, with its links; before, its counts stay as they
% are, which can only keep a node pending longer.
'sk-drop-pending!'(H, N, []) :-
    ( nb_current(sk_retiring, true) -> true ; sk_unwatch_fact(H, N) ),
    (   pw_known(H, N, Id)
    ->  pw_find(Id, R),
        forall(clause(pw_id(H, S, Id), true, Ref), ( attribute_free_variant(S, N) -> erase(Ref) ; true )),
        (   sk_search_key(N, KH, _)
        ->  forall(clause(sk_search_node(KH, _, H, SNode), true, NRef),
                   ( attribute_free_variant(SNode, N) -> erase(NRef) ; true ))
        ;   true ),
        retractall(pw_up(Id, _)),
        pw_bump(pw_size, R, -1),
        ( pw_size(R, 0) -> pw_drop_rep(R) ; true )
    ;   true
    ).

pw_drop_rep(R) :-
    retractall(sk_child_debt(R, _)), retractall(sk_retire_component(R)),
    ( pw_pending_rep(R) -> D = -1 ; D = 0 ),
    forall(retract(pw_out(R, Y, _)), ( retract(pw_in(Y, R, _)), pw_deg_add(Y, 0, -1) )),
    findall(P, retract(pw_in(R, P, _)), Ps),
    forall(member(P, Ps), ( retract(pw_out(P, R, _)), pw_deg_add(P, -1, 0) )),
    retractall(pw_size(R, _)), retractall(pw_work(R, _)), retractall(pw_pend(R, _)), retractall(pw_deg(R, _, _)),
    forall(member(P, Ps), ( D =:= 0 -> true ; pw_add_pend(P, D) )).

