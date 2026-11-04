% Source meaning is published at ingestion, independently of executable rows.
% Source IDs own descriptors; application IDs link their semantic views to the
% existing proof/withdrawal lifetime. Statement prefix/open indexes serve
% matching; exact fact identity uses a separate scalar hash and clause reference.
:- dynamic source_catalog_descriptor/3, source_catalog_refs/2, source_catalog_application/7,
           source_catalog_output/2, source_catalog_open/2, source_catalog_child/4, source_catalog_fact/4,
           source_catalog_generation/2, source_catalog_prior/5, source_catalog_sequence/2,
           source_catalog_identity/2.

source_catalog_intern(Descriptor, Source) :-
    variant_hash(Descriptor, Hash),
    ( source_catalog_descriptor(Hash, Stored, Source), Stored =@= Descriptor -> true
    ; flag(source_catalog_id, Source, Source+1),
      assertz(source_catalog_descriptor(Hash, Descriptor, Source)), assertz(source_catalog_refs(Source, 0)) ),
    retract(source_catalog_refs(Source, N)), M is N+1, assertz(source_catalog_refs(Source, M)).
source_catalog_release(Source) :-
    retract(source_catalog_refs(Source, N)),
    ( N =:= 1 -> retractall(source_catalog_descriptor(_, _, Source))
    ; M is N-1, assertz(source_catalog_refs(Source, M)) ).

'source-catalog-rule!'(Backend, Id, ['source-info', Descriptor, Role, Priors, Parents, _Recipe], Conclusion, true) :-
    Conclusion = [Type, Scope, _, _], Scope=[KB|_],
    source_catalog_intern(Descriptor, Source),
    assertz(source_catalog_application(Id, Source, Backend, [Type, Scope], Role, Parents, Priors)),
    flag(source_catalog_order, Order, Order+1), assertz(source_catalog_sequence(Id, Order)),
    'statement-prefix-hashes'(Type, Prefixes),
    ( nonvar(Type), Type=[Head|_], atomic(Head) -> 'index-hash'(Head, HH) ; HH=0 ),
    forall(member(Prefix, [HH|Prefixes]),
           ('prefix-key'(KB, Prefix, Hash), assertz(source_catalog_output(Hash, Id)))),
    ( ground(Type) -> true
    ; 'statement-open-hash'(Type, OpenPrefix), 'prefix-key'(KB, OpenPrefix, OpenHash),
      assertz(source_catalog_open(OpenHash, Id)) ),
    ( Role = ['forward-source'|_]
    -> forall(nth0(Index, Parents, [P,S]),
              (S=[PKB|_], 'statement-open-hash'(P, PH), 'prefix-key'(PKB, PH, H),
               assertz(source_catalog_child(H, Id, Index, [P,S]))))
    ; true ),
    ( Descriptor = ['source-rule', Name, _, _, _, _, _, InstancePrior, _]
    -> ( InstancePrior == 'no-prior' -> Prior=population ; Prior=['instance-prior',InstancePrior] )
    ; Role = ['reverse-source', Name, Token]
    -> ( Token == cpu -> Prior=population ; Prior=['instance-prior',Token] )
    ; Name=none, Prior=population ),
    ( ground(Name), Name \== none
    -> term_hash(Name, NH), assertz(source_catalog_prior(NH, Id, Name, Scope, Prior)) ; true ),
    'source-catalog-changed!'(KB, true).

'source-catalog-fact!'(Backend, Role, Fact, true) :-
    Fact = [FactType, Scope, _, _], Scope=[KB|_],
    'statement-open-hash'(FactType, Prefix), 'prefix-key'(KB, Prefix, Hash),
    variant_hash(Fact, Identity),
    ( source_catalog_identity(Identity, Ref),
      clause(source_catalog_fact(Hash, Stored, Backend, Role), true, Ref), Stored =@= Fact -> true
    ; assertz(source_catalog_fact(Hash, Fact, Backend, Role), Ref),
      assertz(source_catalog_identity(Identity, Ref)), Scope = [KB|_], 'source-catalog-changed!'(KB, true) ).
'source-catalog-unindex!'(Fact, true) :-
    Fact = [Type, Scope|_], Scope=[KB|_],
    'statement-open-hash'(Type, Prefix), 'prefix-key'(KB, Prefix, Hash),
    variant_hash(Fact, Identity),
    forall((source_catalog_identity(Identity, Ref),
            clause(source_catalog_fact(Hash, Stored, _, _), true, Ref), Stored =@= Fact),
           source_catalog_erase_fact(Identity, Ref)).

source_catalog_erase_fact(Identity, Ref) :-
    clause(source_catalog_fact(_, [_,[KB|_],_,_], _, _), true, Ref),
    erase(Ref), retractall(source_catalog_identity(Identity, Ref)), 'source-catalog-changed!'(KB, true).

'source-catalog-remove!'(Id, true) :-
    proof_template_erase(Id),
    ( retract(source_catalog_application(Id, Source, _, [_, [KB|_]], _, _, _))
    -> retractall(source_catalog_sequence(Id, _)), retractall(source_catalog_output(_, Id)), retractall(source_catalog_open(_, Id)), retractall(source_catalog_child(_, Id, _, _)),
       retractall(source_catalog_prior(_, Id, _, _, _)),
       source_catalog_release(Source), 'source-catalog-changed!'(KB, true)
    ; true ).
'source-catalog-clear-temp!'(true) :-
    forall(source_catalog_application(Id, _, temp, _, _, _, _), 'source-catalog-remove!'(Id, true)),
    forall(clause(source_catalog_fact(_, Fact, temp, _), true, Ref),
           (variant_hash(Fact, Identity), source_catalog_erase_fact(Identity, Ref))).
'source-catalog-changed!'(KB, true) :-
    ( retract(source_catalog_generation(KB, N)) -> Next is N+1 ; Next=1 ),
    assertz(source_catalog_generation(KB, Next)).
source_catalog_stamp(KB, Generation) :-
    ( source_catalog_generation(KB, Generation) -> true ; Generation=0 ).

% Include the wildcard prefix as well as concrete statement prefixes.
source_catalog_hashes(Type, [KB|_], Hashes) :-
    statement_index_hashes('statement-prefix-hashes', Type, Prefixes),
    maplist('prefix-key'(KB), Prefixes, Hashes).

source_catalog_match(Type, Scope, Id, Role, Parents, Priors) :-
    source_catalog_hashes(Type, Scope, [Longest|Shorter]),
    findall(Order-Candidate,
            ((source_catalog_output(Longest, Candidate)
             ; member(H, Shorter), source_catalog_open(H, Candidate)),
             source_catalog_sequence(Candidate, Order)), Candidates),
    keysort(Candidates, Ordered), member(_-Id, Ordered),
    source_catalog_application(Id, _, _, [Type,Scope], Role, Parents, Priors),
    'rule-live?'(Id, true), 'context-rule-visible?'(Id, true).
source_catalog_neighbours(Type, Scope, Neighbours) :-
    findall(P, (source_catalog_match(Type,Scope,_,_,Parents,_), member([P,Scope],Parents), ground(P)), Parents),
    source_catalog_hashes(Type, Scope, Hashes),
    findall(Child, (member(H,Hashes), source_catalog_child(H,Id,Index,[Type,Scope]),
                    source_catalog_application(Id,_,_,[Child,Scope],_,Inputs,_), nth0(Index,Inputs,[Type,Scope]),
                    'rule-live?'(Id,true), 'context-rule-visible?'(Id,true), ground(Child)), Children),
    append(Parents,Children,Neighbours).

source_catalog_template(Type, Scope, Model) :-
    findall(Name-(Id-Parent-TV-Negative-Admission),
            source_catalog_match(Type,Scope,Id,['forward-source',Name,Parent,TV,Negative,Admission],_,_), Producers),
    ( Producers == [] -> Model=root
    ; keysort(Producers, Sorted), group_pairs_by_key(Sorted, Groups),
      maplist({Scope}/[Name-Roles,(Id-Name)-(Parent-TV)]>>(
          ground(Name), Name \= [no_inverse|_],
          \+ ( source_catalog_named_prior(Name, Scope, Prior), Prior \== population ),
          forall(member(_-_-_-Negative-_, Roles), Negative == false),
          member(Id-Parent-TV-false-Admission, Roles),
          source_catalog_admitted(Admission, Scope), ground(Parent),
          ( ground(TV) -> true
          ; var(TV), source_catalog_application(Id, Source, _, _, _, _, _),
            source_catalog_descriptor(_, ['source-rule',_,_,A,B,['CTV'|_]|_], Source),
            TV = ['CTV', ['rule-truth', ['RuleTruth', ['Implication', A, B]]], refined] ), !), Groups, Chosen),
      pairs_keys_values(Chosen, Rules, Branches),
      ( Branches = [Parent-['CTV',Pos,Neg]] -> true
      ; Pos = ['STV',1,1], maplist([_-['STV',S,C]]>>(S=:=1, C=:=1), Branches),
        pairs_keys(Branches, Ps0), sort(Ps0, Ps),
        ( Ps = [Parent] -> true ; Parent = ['Or'|Ps] ),
        Neg = base ), Model=conditional(Parent,Rules,Pos,Neg) ).
source_catalog_admitted(true, _).
source_catalog_admitted(['raw-scopes', Scopes], Scope) :- maplist(=(Scope), Scopes).

source_catalog_named_prior(Name, Scope, Prior) :-
    % Name is ground at admission; this is a selective source lookup, not a
    % scan through generated inverse/proof/CPU rows.
    term_hash(Name, Hash), source_catalog_prior(Hash, Id, Name, Scope, Prior),
    'rule-live?'(Id,true), 'context-rule-visible?'(Id,true).

source_catalog_sources(Type, Scope, Facts) :-
    source_catalog_hashes(Type, Scope, Hashes),
    findall(Role-[Type,Scope,P,TV],
            (member(H,Hashes),source_catalog_fact(H,[Type,Scope,P,TV],_,Role)), Sources),
    \+ member(summary-_, Sources),
    findall(Fact, member(observation-Fact, Sources), Main),
    'context-leaves'(['sk-key',Type,Scope], Local), append(Main,Local,Leaves),
    findall(Fact, (member(Fact,Leaves), Fact=[_,_,_,['STV',_,C]], C>0), Facts).

'source-catalog-priors'(Type, Scope, Folds) :-
    findall(['sk-prior-fold',Id,Args],
       ( source_catalog_match(Type,Scope,Id,_,_,Priors), member([KB,Pattern],Priors),
         \+ (nonvar(Pattern),Pattern=[Head|_],nonvar(Head),memberchk(Head,['And','Or','Not'])),
         ( 'positive-only-pattern?'(KB,Pattern,true) -> 'user-base-rate?'(KB,Pattern,true) ; true ),
         copy_term_nat(Pattern,Probe), copy_term_nat(Type,Want), Probe=Want,
         Args=[KB,Pattern,'extract-tv',['BaseRateEvidence',0.0,0.0],'BaseRateAcc','base-rate','result-tv'] ), Folds).
