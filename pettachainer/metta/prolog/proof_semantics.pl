% Proof construction, semantic metadata and its collection lifetime.
% &proof remains the explanation/evidence DAG. This owner alone publishes its
% result fact and metadata, under the same immutable, never-reused proof id.

'record-proof!'(Pid, Rule, Proof, Ev, Deps, Fact, ['proof-ref', Pid]) :-
    'record-view-rule!'(Pid, Rule, Proof, Owner),
    'proof-term-contains-negated?'(Proof, Negated),
    ( Negated == true -> Flags is 2*Owner+1 ; Flags is 2*Owner ),
    'proof-semantic'(Proof, Semantic),
    proof_given_evidence(Proof, Given),
    ( Fact=[Type,Scope,TV] -> Output=[Type,Scope] ; Output=_ ),
    ( source_catalog_application(Rule, _, _, Output, Role, _, _) -> true ; Role='structural-source' ),
    'proof-zero-likelihood?'(Proof, Zero),
    'proof-unsettled-sources'(Proof, Sources),
    'proof-representative?'(Proof, Representative),
    ( stored_proof(Proof) -> Observed=true ; Observed=false ),
    Metadata=metadata(Role, Semantic, Given, Deps, Zero, Sources, Representative, Observed),
    term_size(Metadata, Words), flag(refs_gc_words, Before, Before+Words),
    assertz(proof_metadata(Pid, Role, Owner, Semantic, Given, Deps, Zero, Sources, Representative, Observed)),
    assertz(user:'&proof'(Pid, Proof, Ev, Flags)),
    ( Fact=[Type,Scope,TV] -> assertz(user:'&proof_fact'(Pid, Type, TV)) ; true ).

% A hard fact read as a completion's given sibling carries no dependence
% between that context and another update. Keep the full signed source set;
% the MeTTa consumer checks the facts' current certainty in their exact scope.
% Construction computes each immutable reference's context from its immediate
% children. Collection follows and removes it with the proof record.

'proof-given-evidence'(Proof, ['ev-set', Set]) :-
    proof_given_evidence(Proof, Set).

proof_given_evidence(Proof, Set) :-
    (   proof_ref_id(Proof, Pid)
    ->  proof_metadata(Pid, _, _, _, Set, _, _, _, _, _)
    ;   nonvar(Proof), Proof = [FactTag, _, _], FactTag == 'fact-source' -> Set = 0
    ;   nonvar(Proof), Proof = [NegTag, Inner], NegTag == negated
    ->  proof_given_evidence(Inner, InnerSet),
        'evidence-negated'(['ev-set', InnerSet], ['ev-set', Set])
    ;   nonvar(Proof), Proof = [Head, Compound], nonvar(Head), Head = [Completion | _],
        Completion == 'antecedent-completion', nonvar(Compound), Compound = [Conjunction | Witnesses],
        Conjunction == conjunction
    ->  append(Siblings, [_Observation], Witnesses),
        'proof-term-evidence'('proof-walk-in-kb', [conjunction | Siblings], ['ev-set', Given]),
        proof_given_children(Proof, Nested), ev_union(Given, Nested, Set)
    ;   is_list(Proof) -> proof_given_children(Proof, Set)
    ;   Set = 0 ),
    refs_gc_touch_set(Set).

proof_given_children([], 0).
proof_given_children([Child | Rest], Set) :-
    proof_given_evidence(Child, ChildSet), proof_given_children(Rest, RestSet),
    ev_union(ChildSet, RestSet, Set).

% Publication receives the identity from the exact row being evaluated.
% Folds have identity -1; temporary query rows cannot be withdrawn. Encoding
% the owner as id+1 reserves metadata zero without losing real rule id zero.
'record-view-rule!'(Pid, Rule, Proof, Owner) :-
    term_size(Proof, Words), flag(refs_gc_words, Before, Before + Words),
    ( Rule >= 0, Rule < 1000000000 -> Owner is Rule + 1 ; Owner = 0 ),
    % A frozen summary's rows are gone. Its source identities must survive
    % physical retirement until this proof has captured its transitive set.
    forall(( sub_term(Ref, Proof), nonvar(Ref), Ref = [Tag, H, E], Tag == forgotten,
             integer(H), integer(E) ), (assertz(summary_user(Pid, H, E)), assertz(summary_ref(H, E, Pid)))).



