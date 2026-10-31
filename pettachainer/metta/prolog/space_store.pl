% Raw row writes and scalar state. Overlay routing is the write boundary.
% Data-only spaces have no function definitions or compiler metadata. In
% particular, an open first column must not enter remove-atom's function case.
'remove-data-rows!'(Space, Pattern, true) :-
    context_store(Space,_,_), context_active(_), !, 'context-remove!'(Space,Pattern,true).
'remove-data-rows!'(Space, Pattern, true) :-
    Row =.. [Space|Pattern],
    retractall(Row).

% Add a row that add-atom could not prove against the space's declared type
% when compiled: the space is named at run time, or a column's type is only
% known then. add-atom checks such a row on every call, which costs more than
% the add itself (PeTTa's analysis hooks raise and catch an exception per
% checked column); the callers build rows of the declared shape.
'add-space-atom!'(Space, Row, true) :-
    context_store(Space,_,_), !, 'context-add!'(Space,Row,true).
'add-space-atom!'(Space, Row, true) :-
    Term =.. [Space|Row],
    assertz(Term).

% A counter's value (change-state!), 0 before it is set.
'search-id-value'(Key, Value) :- ( nb_current(Key, Stored) -> Value = Stored ; Value = 0 ).

% Erase the one stored row that is a variant of Row. A removal by unification
% could also take a different row with the same coarse hash; a variant cannot.
'remove-variant-row!'(Space, Row, true) :-
    context_store(Space,_,_), context_active(C), !,
    ( Row=[Hash|_], ground(Hash) -> Lookup=Hash ; true ),
    forall((clause(context_entry(Lookup,C,Space,Stored,_),true,Ref), Stored =@= Row), erase(Ref)),
    ( ground(Lookup) -> Index=Lookup ; Index=all ),
    assertz(context_hidden(Index,C,Space,Row,variant)).
'remove-variant-row!'('&sk_wait', [H, N, W], true) :- !,
    ( sk_wait_ref(H, N, W, Ref) -> erase(Ref) ; true ).
% Find candidates through the caller's bound indexes, but inspect the
% original stored head before erasing: lookup unification can instantiate
% an open stored row and must not turn it into a false variant match.
'remove-variant-row!'(Space, Row, true) :-
    Head =.. [Space|Row],
    copy_term_nat(Head,Lookup),
    ( clause(Lookup,true,Ref), clause(Stored,true,Ref), Stored =@= Head
    -> erase(Ref) ; true ).


:- dynamic sk_wait_payload/4, sk_wait_template/5, sk_wait_key/2.
% The read-only relation exposes the existing transient delivery shape. The
% only owned clauses are compact payloads, indexed by the awaited node hash.
% sk_wait_key(Hash, Ref) finds one payload by the variant hash of its node,
% template and bindings: a node can hold many payloads of one template.
'&sk_wait'(H, N, Waiter) :-
    sk_wait_payload(H, N, TemplateId, Bindings),
    sk_wait_template(_, _, TemplateId, Waiter, Bindings).

% Select by continuation, then by the variant hash of node and bindings
% (variant_hash ignores attributes, as attribute_free_variant does); the alpha
% comparison rejects hash collisions.
sk_wait_ref(H, N, Waiter, Ref) :-
    Waiter = ['sk-partial',_,Id,_,Done,_,_], length(Done, Pos),
    sk_wait_template(Id, Pos, TemplateId, Template, Bindings),
    subsumes_term(Template, Waiter), Template = Waiter,
    variant_hash([N, TemplateId|Bindings], WaitHash), sk_wait_key(WaitHash, Ref),
    clause(sk_wait_payload(H, Stored, TemplateId, B), true, Ref),
    attribute_free_variant(Stored-B, N-Bindings), !.


% The node hash is already available at expansion/context cleanup. Only its
% few compact subscriptions need alpha comparison; no digest is computed.
sk_unwatch_fact(H, N) :-
    forall(clause('&sk_fact_watch'(H, _, Stored), true, Ref),
           ( attribute_free_variant(Stored, N) -> erase(Ref) ; true )).

% The typed native boundary exposes records whose schema is supplied here,
% rather than by a MeTTa add-atom specialization.
'sk-fact-watches'(H, Nodes) :- findall(N, '&sk_fact_watch'(H, _, N), Nodes).

