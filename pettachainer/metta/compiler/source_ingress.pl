% Pure source/application encoding and normalization. No catalog mutation.
'source-plan-addition'(['source-plan', _, _, _, _, Addition], Addition) :- !.
'source-plan-addition'(Addition, Addition).

% Pure compiler boundary. These annotations are built by semantic emitters;
% CPU instructions are neither interpreted nor run here.
'source-plan-parts'(Plan, [Source, Role, Priors, Premises, Conclusion]) :-
    source_plan_parts(Plan, generated, 'structural-source', [], Source, Role, Priors, [Premises, '|-', Conclusion]).
source_plan_parts(['source-rule-plan', Source, Plan], _, R0, P0, S, R, P, A) :- !,
    source_plan_parts(Plan, Source, R0, P0, S, R, P, A).
source_plan_parts(['source-application-plan', Role, Priors, Plan], S0, _, _, S, R, P, A) :- !,
    source_plan_parts(Plan, S0, Role, Priors, S, R, P, A).
source_plan_parts(Plan, S, R, P, S, R, P, Plan).

% Both compiler products and the public raw API cross this compiler-owned
% boundary. Downstream storage receives semantic inputs, never CPU recipes.
'compile-source-plan'(Source, Role, Priors, Addition,
                      ['source-plan', Source, Role, Priors, Parents, Addition]) :-
    ( Addition = [rules, [Ps, '|-', _]] -> source_plan_parents(Ps, Parents) ; Parents=[] ).
'prepare-source-addition'(['source-plan', Source, Role, Priors, Parents, Addition],
                          [['source-info', Source, PublishedRole, Priors, Parents, Recipe], Prepared]) :- !,
    source_completion(Addition, Prepared, Recipe),
    ( Addition=[rules,_] -> PublishedRole=Role
    ; Addition=[_,_,Proof,_], nonvar(Proof), Proof=[Tag,_,_], Tag==forgotten
    -> PublishedRole=summary
    ; PublishedRole=observation ).
'prepare-source-addition'(Addition, Prepared) :-
    ingestion_addition(Addition),
    ( Addition = [rules, [Ps, '|-', [Type, Scope, Proof, TV]]]
    -> source_raw_role(Proof, Scope, Ps, Role),
       findall([KB, Pattern],
               ( member(['CPU', 'FoldAllCompiled', Args, _], Ps),
                 'base-rate-aggregate-key'(Args, ['base-rate-aggregate-key-value', KB, Pattern, _]) ), Priors),
       Source=['raw-source', Type, Scope, Role, TV]
    ; Source=['fact-source', Addition], Role='structural-source', Priors=[] ),
    'compile-source-plan'(Source, Role, Priors, Addition, Plan),
    'prepare-source-addition'(Plan, Prepared).

% A raw application has no original annotated source. Its proof name and TV
% dataflow are the only available representation at this *ingress* boundary.
source_raw_role(Proof, Scope, Ps, Role) :-
    ( nonvar(Proof), Proof = [Head, Name, _], Head == by
    -> ( foldl(source_raw_premise(Scope), Ps, []-none, _-conditional(A, Pos, Neg))
       -> source_plan_parents(Ps, Parents),
          source_raw_scopes(Parents, Scopes),
          Role = ['forward-source', Name, A, ['CTV', Pos, Neg], false, ['raw-scopes', Scopes]]
       ; Role = ['forward-source', Name, unsupported, unknown, false, false] )
    ; nonvar(Proof), Proof = [Head, [InnerHead, Name, _]], Head == negated, InnerHead == by
    -> Role = ['forward-source', Name, unsupported, unknown, true, false]
    ; nonvar(Proof), Proof = [[Head, Name, with, Token, _], _], Head == inverted
    -> Role = ['reverse-source', Name, Token]
    ; Role = 'structural-source' ).
source_raw_premise(Scope, Premise, State, Next) :-
    Premise=[Head|_],
    ( Head == 'CPU'
    -> Premise=['CPU',Function,Args,Result], source_raw_cpu(Function,Args,Result,State,Next)
    ; Premise=[Type,ReadScope,_,TV], unifiable(ReadScope,Scope,_), var(TV),
      State=Env-none, Next=[TV-Type|Env]-none ).
source_raw_cpu(Fun, _, _, State, State) :- Fun == 'ContextRule', !.
source_raw_cpu(Fun, [A,B], TV, Env-none, [TV-F|Env]-none) :- Fun == 'AndFormula',
    source_raw_boolean(A, Env, FA), source_raw_boolean(B, Env, FB),
    ( FA == constant(true) -> F = FB ; FB == constant(true) -> F = FA ; F = ['And', FA, FB] ).
source_raw_cpu(Fun, [A], TV, Env-none, [TV-['Not', F]|Env]-none) :- Fun == 'NotFormula',
    source_raw_boolean(A, Env, F).
source_raw_cpu(Fun, [A, ['CTV', Pos, Neg]], _, Env-none, Env-conditional(Parent, Pos, Neg)) :-
    Fun == 'CTVModusPonensFormula', source_raw_boolean(A, Env, Parent), Parent \== constant(true).
source_raw_scopes([], []).
source_raw_scopes([[_,Scope]|Rest], [Scope|Scopes]) :- source_raw_scopes(Rest,Scopes).
source_raw_boolean(TV, Env, F) :-
    ( member(Token-F0, Env), Token == TV -> F = F0
    ; nonvar(TV), TV = ['STV', S, C], S =:= 1, C =:= 1, F = constant(true) ).

source_plan_parents([], []).
source_plan_parents([Premise|Rest], Parents) :-
    Premise=[Head|_],
    ( Head == 'CPU' -> Parents=More
    ; Premise=[P,S,_,_], Parents=[[P,S]|More] ),
    source_plan_parents(Rest, More).

% Completion recipes are normalized at the same ingress. Authored compiler
% products carry the recipe; the public raw form needs this one-time recovery.
source_completion([rules, [Ps, '|-', C]], [rules, [Prepared, '|-', C]], Recipe) :- !,
    ( Ps=[['CPU','ReadLikelihoodContext',R,_]|Rest], nonvar(R), R=['completion-recipe'|_]
    -> Recipe=R, Prepared=Rest
    ; C=[_,_,Proof,_], nonvar(Proof), Proof=[Operator|_], nonvar(Operator),
      Operator=[Tag|_], Tag=='antecedent-completion'
    -> foldl(source_completion_step, Ps, completion(-1,0,false,0), completion(I,J,Open,_)),
       Recipe=['completion-recipe',I,J,Open], Prepared=Ps
    ; Recipe='no-completion', Prepared=Ps ).
source_completion(Fact, Fact, 'no-completion').
source_completion_step([Head|Tail], completion(I,J,Open,N), completion(I1,J1,Open1,N1)) :-
    ( Head=='CPU'
    -> Tail=[Fun,Args,_], I1=I,
       ( Fun=='CompoundEvidence' -> J1=N, N1 is N+1, Open1=Open
       ; Fun=='CompletionLikelihoodsFormula'
       -> Args=[Connective,Negated|_], J1=J, N1=N,
          ( Connective=='And' -> (Negated==true -> Open1=false ; Open1=true)
          ; (Negated==true -> Open1=true ; Open1=false) )
       ; J1=J, Open1=Open,
         ( memberchk(Fun,['ContextRule','ReadRate','ReadLikelihoodContext','CompoundEvidence'])
         -> N1 is N+1 ; N1=N ) )
    ; I1 is I+1, J1=J, Open1=Open, N1=N ).
