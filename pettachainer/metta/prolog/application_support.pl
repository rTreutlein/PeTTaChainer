:- ensure_loaded('../runtime/configuration_validation').
% Compiled application bindings, support admission and input policy.
% borrow a rule owner without having that rule's contextual instruction.
'rule-completion-inputs'(Rule, Premises, Inputs) :-
    (   once(match('&completion_recipe', [Rule,['completion-recipe',Statement,Contextual,Opening]], true, true)),
        'rule-contextual-premise'(Contextual, Premises, ['CPU','CompoundEvidence',[_,Compound,_,Scope],_]),
        'split-statement-premise'(Statement, Premises, [Before,Observation,After])
    ->  Inputs = ['completion-inputs',['sk-key',Compound,Scope],Before,Observation,After,Opening]
    ;   Inputs = 'no-completion-inputs' ).

% Contextual instructions survive construction-time CPU evaluation. Their
% compiled ordinal selects an existing instruction without copying its args.
'rule-contextual-premise'(Index, Premises, Selected) :-
    include([Input]>>(Input=[Head,Fun|_], Head=='CPU', 'contextual-cpu?'(Fun,true)), Premises, Contexts),
    nth0(Index, Contexts, Selected).

% Split at a statement-input position; construction may have erased CPU steps.
'split-statement-premise'(Index, [Input|Rest], [Before, Observation, After]) :-
    Input = [Head|_], ( Head == 'CPU' -> Next = Index ; Next is Index - 1 ),
    ( Next < 0 -> Before = [], Observation = Input, After = Rest
    ; Before = [Input|Prefix],
      'split-statement-premise'(Next, Rest, [Prefix, Observation, After]) ).

'rule-premise'(Index, Premises, Premise) :- nth0(Index, Premises, Premise).

% Open only canonical slots, preserving free outer variables and co-reference.
% The map belongs to this binder alone; callers never unify source binders.
'existential-source'(Canonical, Source) :-
    (   nonvar(Canonical), Canonical = [Head, Body], Head == 'ExistentialClaim'
    ->  empty_assoc(Empty),
        existential_source(Body, Open, Empty, Slots),
        assoc_to_values(Slots, Vars),
        Source = ['Exists', Vars, Open]
    ;   nonvar(Canonical), Canonical = [Head, A, B], Head == 'Implication'
    ->  'existential-source'(A, SA), 'existential-source'(B, SB),
        Source = ['Implication', SA, SB]
    ;   Source = Canonical ).

existential_source(Term, Source, Before, After) :-
    (   nonvar(Term), Term = [Head, I], Head == 'exists-slot', integer(I)
    ->  ( get_assoc(I, Before, Source) -> After = Before
        ; put_assoc(I, Before, Source, After) )
    ;   is_list(Term)
    ->  foldl(existential_source, Term, Source, Before, After)
    ;   Source = Term, After = Before ).

% The shape a fold's member is compiled for (sk-shape-members). A user
% predicate compiles to its own lookup goal, and a connective over user
% predicates to adapters that only its structure decides, so the predicates'
% ground arguments become variables: folds that differ only in constants,
% such as one per decision step, share one compilation. Variables stay
% shared. Any other pattern (chainer vocabulary) is its own shape. A
% connective with such a child cannot fall through as a user predicate:
% abstracting its children would change what its member compiler receives.
'pattern-shape'(Pattern, Shape) :-
    (   statement_shape(Pattern, Shape) -> true ; Shape = Pattern ).

connective_shape(Pattern, Shape) :-
    nonvar(Pattern), Pattern = [Connective|Children], Children \== [],
    atom(Connective), memberchk(Connective, ['And', 'Or', 'Not']),
    maplist(statement_shape, Children, Shapes),
    Shape = [Connective|Shapes].

statement_shape(Statement, Shape) :-
    (   connective_shape(Statement, Shape) -> true
    ;   nonvar(Statement), Statement = [Head|Args], atom(Head),
        \+ memberchk(Head, ['And', 'Or', 'Not', 'ImplicationInstanceSample', 'RuleTruth', 'Implication', 'Equivalence',
            'BiImplication', 'ForAll', 'Exists', 'WithPrior', 'Evaluation', 'Similarity',
            'Compute', 'CPU', 'FoldAll', 'FoldAllValue', 'FoldAllTruth', 'MapDist', 'Map2Dist',
            'AverageDist', 'KnownExistential', 'ExistentialResidual', 'GreaterThan', '>',
            'Assuming', 'LikelierThan', 'ExistentialAlternatives']),
        maplist(argument_shape, Args, ArgShapes),
        Shape = [Head|ArgShapes] ).

argument_shape(Arg, Shape) :-
    (   ground(Arg) -> true
    ;   Shape = Arg ).

% The hypothetical context a key lies in, 'MAIN' for the main context (or one
% left open); a fold scoped to a context lies in it. Only an Assuming query's
% contexts are query-local: an implication's contexts hold the derivation of a
% main-context belief and stay. Fields are read without binding anything, so
% a key is not copied.
'key-context'(Key, Ctx) :-
    (   nonvar(Key), Key = [Head, _, KbCtx|_], Head == 'sk-key', nonvar(KbCtx), KbCtx = [_, C|_], nonvar(C) -> Ctx = C
    ;   nonvar(Key), Key = [Head, Args|_], Head == 'sk-fold', nonvar(Args), Args = [Scope|_] -> 'scope-context'(Scope, Ctx)
    ;   Ctx = 'MAIN' ).

'scope-context'(Scope, Ctx) :-
    (   nonvar(Scope), Scope = [_, C|_], nonvar(C) -> Ctx = C ; Ctx = 'MAIN' ).

% A rule is dormant when one of its statement premises can be proved, apart
% from a stored fact, only through the rule's own conclusion with the same
% arguments: self-support exclusion would drop whatever it derives
% (docs/metta/dormant_rules.md). The search runs backward over rules and
% facts on patterns, bounded: past the bound a premise counts as supported,
% so a useful rule is never put to sleep. Forward copies of derived values
% are not support. The verdict is memoized per rule with the heads the
% search found no fact for; a new fact with one of those heads, or any new
% rule, wakes the rule for another look. A rule application concluding a
% complete predicate is never dormant: its join is how a closed read sees
% that a derivation exists (docs/metta/complete_predicates.md). An
% antecedent completion reads the other parts of the antecedent at their
% population prior when nothing else gives them a value (sk-start-prior!), so
% a part that no rule application concludes and that is not complete
% supports it.
:- dynamic rule_dormancy/3.

'rule-dormant?'(Id, Dormant) :-
    (   rule_dormancy(Id, Dormant, _) -> true
    ;   dormancy_analysis(Id, Dormant, Heads), assertz(rule_dormancy(Id, Dormant, Heads)) ).

dormancy_analysis(Id, Dormant, Heads) :-
    nb_setval(dormancy_budget, 2000), nb_setval(dormancy_heads, []),
    (   dormancy_row(ccls_index([Type, Ctx, Proof|_], Id, Premises)),
        \+ ( 'derivation-proof?'(Type, Proof, true), dormancy_complete(Type, Ctx) ),
        member([PType, PCtx, _, _], Premises), PType \== 'CPU',
        \+ dormancy_premise_supported(Proof, PType, PCtx, Type-Ctx, [], 8)
    ->  Dormant = true
    ;   Dormant = false ),
    nb_getval(dormancy_heads, Heads0), sort(Heads0, Heads).

dormancy_supported(Type, Ctx, Forbidden, Path, Depth) :-
    nb_getval(dormancy_budget, Budget),
    (   Budget =< 0 -> true
    ;   Budget1 is Budget - 1, nb_setval(dormancy_budget, Budget1),
        (   Type-Ctx == Forbidden -> fail
        ;   dormancy_complete(Type, Ctx) -> true
        ;   member(Seen, Path), Seen =@= Type-Ctx -> fail
        ;   Depth =< 0 -> true
        ;   \+ dormancy_judged(Type, Ctx) -> true
        ;   dormancy_fact(Type, Ctx) -> true
        ;   \+ dormancy_row(ccls_index([Type, Ctx|_], _, _)) -> true
        ;   dormancy_note_head(Type),
            Depth1 is Depth - 1,
            dormancy_row(ccls_index([Type, Ctx, Proof|_], _, Premises)),
            (   memberchk(['CPU', 'SettlesFormula'|_], Premises) -> \+ \+ dormancy_settles(Premises)
            ;   forall(( member([PType, PCtx, _, _], Premises), PType \== 'CPU' ),
                       dormancy_premise_supported(Proof, PType, PCtx, Forbidden, [Type-Ctx|Path], Depth1)) ) ) ).

dormancy_premise_supported(Proof, Type, Ctx, Forbidden, Path, Depth) :-
    (   Type-Ctx \== Forbidden, 'proof-semantic'(Proof, ['prior-update',completion,_,_,_,_]), \+ dormancy_derived(Type, Ctx) -> true
    ;   dormancy_supported(Type, Ctx, Forbidden, Path, Depth) ).

dormancy_derived(Type, Ctx) :-
    (   dormancy_complete(Type, Ctx) -> true
    ;   \+ \+ ( dormancy_row(ccls_index([Type, Ctx, Proof|_], _, _)),
                 'rule-application-proof?'(Proof, true) ) ).

% A complete statement always has a value once its search settles: its rule
% applications read closed, and with none it is unfounded, false
% (docs/metta/complete_predicates.md). So it supports a reader even when its
% only derivations run through a loop back to it: a loop disjunct read closed
% is false, and the rest of its antecedent decides.
% A connective with a complete part is complete too (`complete-statement?`).
dormancy_complete(Type, [Kb|_]) :- 'complete-part?'(Kb, false, Type, true).

% A settled rule reads only a part whose certain stored fact settles its
% compound (docs/metta/connective_settling.md), so it supports its conclusion
% only through such a fact: the part's formulas run on the fact up to the
% settling check. A refined rule's truth goal is supported.
dormancy_settles([['CPU', Fun, Args, Res]|Rest]) :- !,
    append(Args, [Out], CallArgs), G =.. [Fun|CallArgs],
    catch(G, _, fail), Out = Res, ( Fun == 'SettlesFormula' -> true ; dormancy_settles(Rest) ).
dormancy_settles([[Type, _, _, _]|Rest]) :-
    nonvar(Type), Type = [Head|_], Head == 'RuleTruth', !, dormancy_settles(Rest).
dormancy_settles([[Type, Ctx, Proof, Tv]|Rest]) :-
    dormancy_row('&kb'(Type, Ctx, Proof, Tv)), Tv = ['STV', _, C], number(C), C >= 1.0,
    dormancy_settles(Rest).

% A statement no fact and no rule speaks of yet is an input still to come,
% not one only the rule's conclusion supports, so it counts as supported.
% The search judges only what it fully sees: user predicates in the main
% context (or one a rule leaves open). An assumption context supplies its own
% premises, and the chainer's own vocabulary has support the search does not
% model: rules installed when a node expands (implications), member folds and
% samples. Anything else counts as supported.
dormancy_judged(Type, [_, Context|_]) :-
    ( var(Context) ; Context == 'MAIN' ),
    \+ ( Type = [Head|_], memberchk(Head, ['ImplicationInstanceSample', 'RuleTruth', 'Implication', 'Equivalence', 'And', 'Or', 'Not',
        'ForAll', 'WithPrior', 'Evaluation', 'Similarity']) ).

dormancy_fact(Type, Ctx) :-
    \+ \+ ( dormancy_row('&kb'(Type, Ctx, Proof, Tv)),
            \+ ( 'index-hash'(['sk-key', Type, Ctx], Hash),
                 dormancy_row('&sk_forward_stored'(Hash, _, Copy, _, _)), Copy == [Type, Ctx, Proof, Tv] ) ).

% A space has no clauses, and so no predicate, until its first row.
dormancy_row(Row) :- catch(user:Row, error(existence_error(procedure, _), _), fail).

dormancy_note_head(Type) :-
    (   Type = [Head|_] -> true ; Head = Type ),
    nb_getval(dormancy_heads, Heads), nb_setval(dormancy_heads, [Head|Heads]).

% The dormant rules a new fact or query rule concluding this statement could
% wake; their verdicts are dropped. A statement of any head may wake any.
'rule-dormancy-wake!'(Type, Ids) :-
    statement_head(Type, Head),
    (   Head == '$var' -> 'rule-dormancy-reset!'(Ids)
    ;   findall(Id, ( rule_dormancy(Id, true, Heads), memberchk(Head, Heads) ), Ids0), sort(Ids0, Ids),
        forall(member(Id, Ids), retractall(rule_dormancy(Id, _, _))) ).

% A query's own rules leave with it, and so do their verdicts.
'rule-dormancy-forget-temp!'(true) :-
    forall(( rule_dormancy(Id, _, _), Id >= 1000000000 ), retractall(rule_dormancy(Id, _, _))).

% A new rule can give any premise support: every dormant rule is looked at
% again, and every verdict is dropped.
'rule-dormancy-reset!'(Ids) :-
    findall(Id, rule_dormancy(Id, true, _), Ids0), sort(Ids0, Ids),
    retractall(rule_dormancy(_, _, _)).

statement_head(T, H) :-
    (   var(T) -> H = '$var'
    ;   T = [H0|_] -> ( var(H0) -> H = '$var' ; H = H0 )
    ;   H = T ).

% The trie compares variants exactly, without binding caller variables or
% Functional input relations are immutable value tables. Ground certain-true
% facts assign a key; no other fact or rule may define that relation.
% This is stronger than merely knowing an uncertain most likely value.
:- dynamic '&kb'/4, '&sk_answer'/3, ccls_index/3.
'set-functional-predicate'(Kb, Head, Arity, Positions, true) :-
    'declared-head!'(Head, true),
    ( atom(Head), integer(Arity), Arity > 1, is_list(Positions),
      Positions \== [], sort(Positions, Positions), length(Positions, N), N < Arity,
      forall(member(P, Positions), (integer(P), between(1, Arity, P)))
    -> true ; throw(error(domain_error(functional_predicate, [Head,Arity,Positions]), _)) ),
    ( functional_predicate(Head, Kb, Arity, Positions) -> true
    ; ( functional_predicate(Head, Kb, _, _)
      ; '&kb'([Head|_], [Kb|_], _, _)
      ; ccls_index([[Head|_],[Kb|_]|_], _, _) )
    -> throw(error(permission_error(declare, functional_predicate, Head), _))
    ; assertz(functional_predicate(Head, Kb, Arity, Positions)),
      'set-positive-only-predicate'(Kb, Head, true) ).

% Validate before publication, including no-check/bulk ingestion. Declarations
% are KB-local and apply to main-world inputs; private hypothetical facts do
% not assign or conflict with the world's immutable value.
functional_check_fact([Type, Context, _, TV], Assignment) :-
    ( nonvar(Type), Type = [Head|_], Context = [Kb,'MAIN','Nil'],
      functional_predicate(Head, Kb, _, _)
    -> ( ground(Type-TV), TV = ['STV',S,C], S =:= 1, C >= 1 -> true
       ; throw(error(domain_error(functional_input, Type-TV), _)) ),
       ( functional_key(Type, Context, Key) -> true
       ; throw(error(domain_error(functional_arity, Type), _)) ),
       term_hash(Key, Hash),
       ( functional_value(Hash, Key, Stored), Stored \== Type
       -> throw(error(permission_error(assign, functional_key, Key-Type), _)) ; true ),
       Assignment = [Hash,Key,Type]
    ; Assignment = [] ).

% Validate a source's complete lowering before publishing any of it. The
% local map also catches two conflicting conjuncts within that one source.
'functional-check-additions!'(Kb, Adds, true) :-
    ( functional_predicate(_, Kb, _, _)
    -> empty_assoc(Empty), foldl(functional_check_addition, Adds, Empty, _)
    ; true ).
functional_check_addition(Add, Before, After) :-
    ( Add = [rules,[_, '|-', Conclusion]]
    -> 'functional-rule!'(Conclusion, true), After = Before
    ; functional_check_fact(Add, Assignment),
      ( Assignment = [_,Key,Type]
      -> ( get_assoc(Key, Before, Stored), Stored \== Type
         -> throw(error(permission_error(assign, functional_key, Key-Type), _)) ; true ),
         put_assoc(Key, Before, Type, After)
      ; After = Before ) ).

'functional-fact!'(Fact, true) :-
    functional_check_fact(Fact, Assignment),
    ( Assignment = [Hash,Key,Type], \+ functional_value(Hash, Key, _)
    -> assertz(functional_value(Hash, Key, Type)),
       ( sk_search_owned(Hash, Key, _, _) -> sk_queue_retirement(Hash, Key) ; true )
    ; true ).

'functional-rule!'([Type, Context|_], true) :-
    ( nonvar(Context), Context = [Kb|_], nonvar(Kb),
      functional_predicate(Head, Kb, _, _),
      ( var(Type) ; Type = [Candidate|_], (var(Candidate) ; Candidate == Head) )
    -> throw(error(permission_error(derive, functional_predicate, Head), _))
    ; true ).

% A producer must cover the entire query, without specializing either term.
'term-covers?'(General, Specific, Result) :-
    ( subsumes_term(General, Specific) -> Result = true ; Result = false ).

% Unlike a sampling declaration, immutable inputs forbid every derived value.
'functional-pattern?'(Kb, Pattern, Result) :-
    'implication-side-conjuncts'(Pattern, Parts),
    ( member(Part, Parts), 'canon'(Part, [Type, _]),
      nonvar(Type), Type = [Head|_], functional_predicate(Declared, Kb, _, _),
      ( var(Head) ; Head == Declared )
    -> Result = true ; Result = false ).

