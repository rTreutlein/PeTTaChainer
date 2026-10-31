% Immutable proof records, semantic decoding and DAG presentation.
% These readers never construct evidence or choose inference policy.
:- dynamic proof_metadata/10, proof_template/4, '&proof'/4, '&proof_fact'/3, ccls_index/3.
% Both projections borrow the existing row terms. A synthetic prior can
% The last rule application of a proof, its premise proofs still references:
% a stored proof's own step, any other proof itself. Read by every merge and
% fold step, so one clause lookup instead of a collected match.
'sk-step-proof'(Proof, Step) :-
    ( nonvar(Proof), Proof = ['proof-ref', Pid], user:'&proof'(Pid, Value, _, _) -> Stored = Value ; Stored = Proof ),
    ( nonvar(Stored), Stored = ['fact-source',_,Source] -> Step = Source
    ; nonvar(Stored), Stored = ['zero-likelihood',Source] -> Step = Source
    ; nonvar(Stored), Stored = ['unsettled-summary',_,Source] -> 'sk-step-proof'(Source, Step)
    ; Step = Stored ).

% Different result keys can intern the same proof under different ids. Compare
% the proof DAG without its result metadata or constructing an expanded tree.
% Repeated reference pairs are visited once; variables are never unified.
'same-proof?'(A, B, Same) :-
    empty_nb_set(Seen),
    ( same_proof_terms(A, B, Seen) -> Same = true ; Same = false ).

same_proof_terms(A, B, Seen) :-
    (   A == B -> true
    ;   proof_ref_id(A, I), proof_ref_id(B, J)
    ->  (   add_nb_set(I-J, Seen, true)
        ->  user:'&proof'(I, AP, AE, _), user:'&proof'(J, BP, BE, _), AE == BE,
            \+ opaque_proof_step(AP), \+ opaque_proof_step(BP),
            same_proof_terms(AP, BP, Seen)
        ;   true )
    ;   proof_ref_id(A, I)
    ->  user:'&proof'(I, AP, _, _), same_proof_terms(AP, B, Seen)
    ;   proof_ref_id(B, J)
    ->  user:'&proof'(J, BP, _, _), same_proof_terms(A, BP, Seen)
    ;   nonvar(A), nonvar(B), A = [AH|AT], B = [BH|BT],
        same_proof_terms(AH, BH, Seen), same_proof_terms(AT, BT, Seen)
    ).

proof_ref_id(Proof, Id) :-
    is_list(Proof), Proof = [Head, Id], Head == 'proof-ref', integer(Id).

% cpu omits the computation's arguments (a fold's population, for example).
% Distinct stored computations therefore retain their reference identity.
opaque_proof_step(Step) :-
    ( Step == cpu -> true ; is_list(Step), member(Cell, Step), Cell == cpu ), !.

% References have already crossed construction. Inline temporary values cross
% the same pure normalization boundary; no secondary proof id/cache is created.
'proof-semantic'(Proof, Semantic) :-
    ( proof_ref_id(Proof, Pid)
    -> proof_metadata(Pid, _, _, Semantic, _, _, _, _, _, _)
    ; proof_semantic_inline(Proof, Semantic) ).

proof_semantic_inline(Proof, Semantic) :-
    ( nonvar(Proof), Proof=[Head|Tail], nonvar(Head)
    -> ( Head == 'fact-source', Tail=[_,Source] -> Step=Source
       ; Head == 'zero-likelihood', Tail=[Source] -> Step=Source
       ; Head == 'unsettled-summary', Tail=[_,Source] -> Step=recursive(Source)
       ; Step=Proof )
    ; Step=Proof ),
    ( nonvar(Step), Step=recursive(Inner) -> 'proof-semantic'(Inner, Semantic)
    ; nonvar(Step), Step=[Kind|Args], nonvar(Kind)
    -> proof_semantic_route(Kind, Args, Step, Semantic)
    ; Semantic=['opaque-proof',Step] ).

proof_semantic_route(Head, Tail, Step, Semantic) :-
    ( Head == by, Tail=[Rule|Premises] -> Semantic=[application,Rule,Premises]
    ; Head=[Tag|_], nonvar(Tag), Tag == inverted,
      Head=[_,Rule,with,Base,Read], Tail=[Witness]
    -> Semantic=['prior-update',inversion,Rule,Base,Read,Witness]
    ; Head=[Tag|_], nonvar(Tag), Tag == 'antecedent-completion',
      Head=[_,Rule,Index,with,Base,Read], Tail=[Witness]
    -> Semantic=['prior-update',completion,[Rule,Index],Base,Read,Witness]
    ; Head=[Tag|_], nonvar(Tag), Tag == reported,
      Head=[_,with,Base,Read], Tail=[Witness]
    -> Semantic=['prior-update',report,none,Base,Read,Witness]
    ; Head == 'node-message', Tail=[Index,Source,Parts,Likelihood]
    -> Semantic=[message,Source,Likelihood,Index,Parts]
    ; Head=[Tag|_], nonvar(Tag), Tag == 'node-jeffrey',
      Head=[_,Index,Source,Prediction,Conditionals], Tail=[Parts]
    -> Semantic=['kinematic-update',Source,Prediction,Conditionals,Index,Parts]
    ; Head=[Tag|_], nonvar(Tag), Tag == 'node-joint', Head=[_,Spec,Source], Tail=[Parts]
    -> Semantic=[joint,Source,Parts,Spec]
    ; memberchk(Head, [negated, 'factored-revision', 'merge/revision', specializes,
                      combination, conditioned, conjunction, disjunction, 'conditional-implication',
                      settled, given, forgotten])
    -> Semantic=Step
    ; Semantic=['opaque-proof',Step] ).

% Application templates cross construction during catalog installation, before
% executable joins instantiate them. These reads never inspect printed proofs.

'proof-template!'(Id, Conclusion, Premises, true) :-
    Conclusion=[_,_,Proof,_], proof_semantic_inline(Proof, Semantic),
    assertz(proof_template(Id, Semantic, Conclusion, Premises)).
proof_template_erase(Id) :- retractall(proof_template(Id, _, _, _)).
'application-rule'(Id, ['application-template',Type,Scope,Name,Premise,Premises]) :-
    proof_template(Id, [application,Name,[Premise]], [Type,Scope,_,_], Premises).
'proof-inversion-name'(Id, Name) :-
    ( proof_template(Id, ['prior-update',inversion,Rule,_,_,_], _, _) -> Name=Rule ; Name=none ).
'proof-application-name'(Id, Name) :-
    ( proof_template(Id, [application,Rule,_], _, _) -> Name=Rule ; Name=none ).

'proof-update-witness'(Proof, Witness) :-
    'proof-semantic'(Proof, Semantic),
    ( Semantic=['prior-update',_,_,_,_,W] -> Witness=W
    ; Semantic=[application,Rule,_] -> Witness=Rule
    ; Semantic=[_,Witness|_] ).

'proof-zero-likelihood?'(Proof, Zero) :-
    ( proof_ref_id(Proof, Pid) -> proof_metadata(Pid, _, _, _, _, _, Zero, _, _, _)
    ; nonvar(Proof), Proof=[Head,_,Source], Head == 'unsettled-summary' -> 'proof-zero-likelihood?'(Source, Zero)
    ; nonvar(Proof), Proof=[Head,_], Head == 'zero-likelihood' -> Zero=true
    ; Zero=false ).


'proof-unsettled-sources'(Proof, Sources) :-
    ( proof_ref_id(Proof, Pid)
    -> proof_metadata(Pid, _, _, _, _, _, _, Sources, _, _)
    ; findall(Source,
        ( sub_term(Child, Proof), nonvar(Child),
          ( Child=[Tag,Source,_], Tag == 'unsettled-summary', number(Source)
          ; proof_ref_id(Child, Id), 'proof-unsettled-sources'(['proof-ref',Id],Nested), member(Source,Nested) ) ),
        All), sort(All, Sources) ).


'proof-representative?'(Proof, Single) :-
    ( proof_ref_id(Proof, Pid)
    -> proof_metadata(Pid, _, _, _, _, _, _, _, Single, _)
    ; ( sub_term(Child,Proof), nonvar(Child),
        ( Child=[Tag|_], nonvar(Tag), memberchk(Tag,['factored-revision','merge/revision',combination,'class-mixture'])
        ; proof_ref_id(Child,Id), 'proof-representative?'(['proof-ref',Id],false) ) )
    -> Single=false
    ; Single=true ).


% Keep the conclusion index's matching and order, but take application meaning
% from its installed record. The explanation column is deliberately unread.
'application-values'(Type, Scope, Values) :-
    findall(['application-value',Type,Scope,Name,Premise,TV,Premises],
            (ccls_index([Type,Scope,_,TV], Id, Premises),
             proof_template(Id, [application,Name,[Premise]], [Type,Scope,_,TV], Premises)), Values).
% Event-node admission distinguishes a stored observation from a prediction.
% Capture this at construction as well; later reference reads are indexed.
stored_proof(Proof) :-
    nonvar(Proof),
    ( proof_ref_id(Proof, Pid) -> proof_metadata(Pid, _, _, _, _, _, _, _, _, true)
    ; Proof=[Head|Tail],
      ( Head == 'fact-source', Tail=[_,_]
      ; Head == '@', Tail=[_,Merge], stored_proof(Merge)
      ; Head == 'merge/revision', Tail=[Left,Right], stored_proof(Left), stored_proof(Right) ) ).

% A stored proof is a DAG: each view's proof is one rule application whose
% premise proofs are references to stored proofs. Expanding it as a tree
% repeats every shared subproof, exponentially in how deeply values build on
% merged values. The expansion instead prints a subproof that is referenced
% more than once and itself refers to stored proofs in full at its first
% occurrence, as (shared Id Proof), and as (shared Id) after that; a shared
% subproof with no references of its own is a fixed-size term and is printed
% where it occurs. Both passes visit each stored proof once.
proof_dag_expand(Proof, Out) :-
    empty_assoc(E),
    proof_ref_counts(Proof, E, Counts),
    proof_dag_term(Proof, Counts, E, _, Out).

proof_ref_counts(T, C0, C) :-
    (   var(T) -> C = C0
    ;   T = ['proof-ref', Pid]
    ->  (   get_assoc(Pid, C0, N)
        ->  N1 is N + 1, put_assoc(Pid, C0, N1, C)
        ;   put_assoc(Pid, C0, 1, C1),
            (   '&proof'(Pid, Stored, _, _) -> proof_ref_counts(Stored, C1, C) ; C = C1 )
        )
    ;   T = ['fact-source',_,Source] -> proof_ref_counts(Source,C0,C)
    ;   is_list(T) -> foldl(proof_ref_counts, T, C0, C)
    ;   C = C0
    ).

proof_dag_term(T, Counts, D0, D, Out) :-
    (   var(T) -> Out = T, D = D0
    ;   T = ['proof-ref', Pid], '&proof'(Pid, Stored, _, _)
    ->  (   get_assoc(Pid, Counts, N), N > 1, proof_has_ref(Stored)
        ->  (   get_assoc(Pid, D0, _)
            ->  Out = [shared, Pid], D = D0
            ;   put_assoc(Pid, D0, true, D1),
                proof_dag_term(Stored, Counts, D1, D, X),
                Out = [shared, Pid, X]
            )
        ;   proof_dag_term(Stored, Counts, D0, D, Out)
        )
    ;   T = ['zero-likelihood',Source] -> proof_dag_term(Source,Counts,D0,D,Out)
    ;   T = ['unsettled-summary',_,Source] -> proof_dag_term(Source,Counts,D0,D,Out)
    ;   T = ['fact-source',_,Source] -> proof_dag_term(Source,Counts,D0,D,Out)
    ;   is_list(T) -> proof_dag_list(T, Counts, D0, D, Out)
    ;   Out = T, D = D0
    ).

proof_dag_list([], _, D, D, []).
proof_dag_list([T|Ts], Counts, D0, D, [O|Os]) :-
    proof_dag_term(T, Counts, D0, D1, O),
    proof_dag_list(Ts, Counts, D1, D, Os).

proof_has_ref(T) :-
    nonvar(T),
    (   T = ['proof-ref', _] -> true
    ;   is_list(T), member(E, T), proof_has_ref(E) -> true
    ).
