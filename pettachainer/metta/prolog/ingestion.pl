% Source ingestion checks run before the compiler can unify or publish input.
% Settings are KB-local runtime entries so cached library loads remain valid.
:- dynamic ingestion_limit/2.

'set-max-term-bytes'(KB, Limit, true) :-
    must_be(positive_integer, Limit),
    retractall(ingestion_limit(KB, _)),
    assertz(ingestion_limit(KB, Limit)).

'validate-ingestion!'(KB, Statement, true) :-
    ( ingestion_limit(KB, Limit) -> true ; Limit = 65536 ),
    swrite(Statement, Text),
    string_bytes(Text, Bytes, utf8),
    length(Bytes, Size),
    ( Size =< Limit -> true
    ; throw(error(resource_error(stored_term_bytes(Size, Limit)),
                  context(compileadd/2, 'stored term exceeds max-term-bytes'))) ),
    Statement = [':', _, Type, TV],
    ingestion_check(Type, TV),
    ingestion_negation(Type, TV),
    ( ingestion_closed([], Type) -> true
    ; throw(error(domain_error(fact_without_free_variables, Type),
                  context(compileadd/2, 'fact contains free variables'))) ).

ingestion_check(Type, TV) :-
    forall((source_atom(Type, Atom), (atom(Atom) -> Head=Atom ; Atom=[Head|_]),
            memberchk(Head, ['Premises','Conclusions'])),
           throw(error(domain_error(rule_syntax, Atom),
                       context(compileadd/2, 'use (Implication antecedent consequent), with And for multiple statements')))),
    ingestion_tv(TV).

ingestion_tv(TV) :-
    ( var(TV) -> true
    ; TV=[Head|Branches], Head=='CTV' -> maplist(ingestion_tv, Branches)
    ; TV=[Head,S,C], Head=='STV'
    -> forall((member(Value, [S,C]), nonvar(Value)),
              ( number(Value), Value >= 0, Value =< 1 -> true
              ; throw(error(domain_error(truth_value, TV),
                            context(compileadd/2, 'STV strength and confidence must be in [0,1]'))) ))
    ; true ).

ingestion_addition([rules, [Premises, '|-', Conclusion]]) :- !,
    maplist(ingestion_addition, [Conclusion|Premises]).
ingestion_addition([Type, _, _, TV]) :-
    ( Type == 'CPU' -> true ; ingestion_check(Type, TV) ).

% A fact's context, proof name and statement are its evidence identity. A new
% observation is new evidence, never a replacement (append-only), so a source
% that gives a stored identity another value is rejected before any of it is
% published (#113). Restating the stored value is accepted: values compare
% by number, so (STV 1 1) restates (STV 1.0 1.0) and a negation's stored
% complement 1 - 0.8 restates 0.2.
'proof-identities-free!'(Adds, true) :- maplist(ingestion_identity_free, Adds).

ingestion_identity_free(Add) :-
    (   Add = [Type, Ctx, Proof, TV], ingestion_stored_value(Type, Ctx, Proof, Stored),
        \+ ingestion_same_value(Stored, TV)
    ->  throw(error(permission_error(restate, proof, Proof),
                    context(compileadd/2, 'proof name already stores another value for this statement')))
    ;   true ).

ingestion_same_value(A, B) :- number(A), number(B), !, abs(A - B) =< 1.0e-9.
ingestion_same_value(A, B) :- is_list(A), is_list(B), !, maplist(ingestion_same_value, A, B).
ingestion_same_value(A, B) :- A == B.

% The values stored under an identity, read through the fact's own index row
% as kb-fact-present? reads it; an open statement is compared as a variant.
ingestion_stored_value(Type, Ctx, Proof, TV) :-
    (   ground(Type)
    ->  (   'kb-fact-prefix-hashes'(Type, [])
        ->  catch('&kb'(Type, Ctx, Proof, TV), error(existence_error(procedure, _), _), fail)
        ;   'kb-fact-open-hash'(Type, Hash),
            catch('&kb_prefix'(Hash, Type, Ctx, Proof, TV), error(existence_error(procedure, _), _), fail) )
    ;   'kb-fact-open-hash'(Type, Hash),
        catch('&kb_open'(Hash, Stored, Ctx, Proof, TV), error(existence_error(procedure, _), _), fail),
        Stored =@= Type ).

% Asserted negations are stored at their canonical key by compile_, with the
% strength complemented. Validate the entire leading chain before compilation:
% exact destructuring would silently fail on Not/0 or Not/2, and an outer Not
% must not hide an invalid inner negation. Only an STV has a complement.
ingestion_negation(Type, TV) :-
    ( nonvar(Type), Type = [Head|Args], Head == 'Not'
    -> ( Args = [Inner] -> ingestion_negation(Inner, TV)
       ; throw(error(domain_error(unary_negation, Type),
                     context(compileadd/2, 'negation requires exactly one argument'))) ),
       ( nonvar(TV), TV = ['STV'|_] -> true
       ; throw(error(domain_error(negated_fact_value, TV),
                     context(compileadd/2, 'a negated statement takes an STV'))) )
    ; true ).

% The kind a truth value states (LANGUAGE_SPEC, "PTV and FTV"): (PTV s c),
% the probability of a ground statement's event, and (FTV s c), the degree or
% frequency a rule states. An STV is the kind its statement takes by default,
% so each explicit kind reads as the STV of a statement of that kind, and a
% kind the statement does not take is rejected. A statement takes the kind of
% what the compiler builds of it: under its negations (stored at the
% statement they negate), a rule, a bidirectional implication (two rules) or
% a class link (a rule) is a frequency; anything else is an event.
'source-tv-canon'(Source, Canonical) :-
    (   nonvar(Source), Source = [':', Name, Statement, Value]
    ->  tv_canon(Statement, Value, Canon), Canonical = [':', Name, Statement, Canon]
    ;   Canonical = Source ).

tv_canon(Statement, Value, Canon) :-
    (   nonvar(Value), Value = [Kind, S, C], nonvar(Kind), memberchk(Kind, ['PTV', 'FTV'])
    ->  ( tv_frequency(Statement) -> Takes = 'FTV' ; Takes = 'PTV' ),
        (   Kind == Takes -> Canon = ['STV', S, C]
        ;   throw(error(domain_error(tv_kind, [Kind, Statement]),
                        context(compileadd/2, 'a PTV states a ground statement, an FTV a rule'))) )
    ;   Canon = Value ).

tv_frequency(Statement) :-
    nonvar(Statement),
    (   Statement = [Head, Inner], Head == 'Not' -> tv_frequency(Inner)
    ;   ingestion_rule(Statement) -> true
    ;   Statement = [Head, _, _], atom(Head),
        ( Head == 'Inheritance' ; 'bidirectional-implication-form?'(Head, true) ) ).

% Heads must be inspected without unification: a variable predicate is data,
% never an Implication, a wrapper, or a binder merely because it could fit one.
'source-rule?'(Type, Result) :-
    ( ingestion_rule(Type) -> Result = true ; Result = false ).

ingestion_rule(Type) :-
    nonvar(Type), Type = [Head|Args],
    ( Head == 'Implication', Args = [_,_]
    ; Head == 'ForAll', Args = [_,Body],
      nonvar(Body), Body = [BodyHead|_],
      ( BodyHead == 'Implication', Body = [_,_,_]
      ; BodyHead == 'WithPrior', Body = [_,_,Inner],
        nonvar(Inner), Inner = [InnerHead,_,_], InnerHead == 'Implication' )
    ; Head == 'WithPrior', Args = [_,Body],
      nonvar(Body), Body = [BodyHead,_,_], BodyHead == 'Implication'
    ), !.

% Binding is lexical to this occurrence. The same Prolog variable appearing
% outside a binder must still be found free there; never subtract a global
% union of all bound variables from the variables of the whole fact.
ingestion_closed(Bound, Term) :-
    ( var(Term) -> member(Variable, Bound), Term == Variable, !
    ; atomic(Term) -> true
    ; ingestion_rule(Term) -> true
    ; Term = [Head|Args],
      ( atom(Head), Args = [_,_],
        'bidirectional-implication-form?'(Head, true)
      -> true
      ; ( Head == 'ForAll' ; Head == 'Exists' ), Args = [Binder,Body]
      -> term_variables(Binder, Variables), append(Variables, Bound, Scope),
         ingestion_closed(Scope, Body)
      ; maplist(ingestion_closed(Bound), [Head|Args]) )
    ).


% Quantifiers in opaque predicate arguments are quoted data. Only logical
% connective children participate in the compiler's executable Exists syntax.
'source-exists?'(Type, Result) :-
    ( ingestion_exists(Type) -> Result = true ; Result = false ).

ingestion_exists(Type) :-
    nonvar(Type), Type = [Head|Args],
    ( Head == 'Exists'
    ; atom(Head), ( memberchk(Head, ['And','Or','Not','Implication'])
                  ; 'bidirectional-implication-form?'(Head, true) ),
      member(Child, Args), ingestion_exists(Child) ), !.

% A weighted query assumption (: Name Statement TV) is one input compileadd
% would store, held in its Assuming world with its own value: a closed
% ordinary fact with an STV; a negated fact or implication with an STV (the
% compiler stores it, as compileadd does, at its canonical key); or an
% implication, whose variables are its own, with an STV or a CTV. Anything
% else is rejected rather than read as a certain fact or a colon-headed
% predicate.
'weighted-assumption'(Annotation, [Statement, TV]) :-
    ( Annotation = [':', Name, Source, Stated], ground(Name), nonvar(Source), nonvar(Stated),
      tv_canon(Source, Stated, Value), weighted_assumption(Source, Value, Statement, TV)
    -> true
    ; annotation_error(Annotation) ).

annotation_error(Annotation) :-
    throw(error(domain_error(weighted_assumption, Annotation),
                context(query/3, 'unsupported weighted assumption'))).

weighted_assumption(Source, Value, Statement, TV) :-
    Source = [Head|Args], atom(Head),
    ( Head == 'Implication'
    -> assumption_rule(Source),
       ( assumption_stv(Value) ; Value = ['CTV',P,N], assumption_stv(P), assumption_stv(N) ),
       Statement = Source, TV = Value
    ; Head == 'Not'
    -> Args = [Inner], nonvar(Inner), assumption_stv(Value),
       weighted_assumption(Inner, Value, _, _), Statement = Source, TV = Value
    ; \+ memberchk(Head, [':','CPU','ForAll','Exists','WithPrior','Assuming']),
      'compound-connective?'(Head, false), 'source-computation-head?'(Head, false),
      'bidirectional-implication-form?'(Head, false), ingestion_closed([], Source),
      assumption_stv(Value), Statement = Source, TV = Value ).

% The assumed-rule compiler takes a plain antecedent and consequent: both
% sides given, neither a nested rule nor an existential conclusion.
assumption_rule(['Implication', Antecedent, Consequent]) :-
    nonvar(Antecedent), nonvar(Consequent),
    \+ ingestion_rule(Consequent), \+ ingestion_exists(Consequent).

assumption_stv(Value) :-
    nonvar(Value), Value = ['STV',S,C], number(S), number(C),
    S >= 0, S =< 1, C >= 0, C =< 1.

% An annotation is an input form, valid only as an Assuming fact or one of its
% And conjuncts, and Assuming only as the query's outermost statement: one
% world per query (#125). Walk statement positions, never predicate arguments,
% which are data, and reject either form anywhere else in a public query.
'check-query-annotations!'([':', _, Statement, _], true) :-
    (   nonvar(Statement), Statement = [Head|Args], Head == 'Assuming'
    ->  ( Args = [Facts, Goal] -> true
        ; throw(error(domain_error(assuming_arguments, Statement),
                      context(query/3, 'Assuming takes its facts and a goal'))) ),
        ( nonvar(Facts), Facts = ['And'|Conjuncts] -> true ; Conjuncts = [Facts] ),
        maplist(assumed_annotations, Conjuncts), query_annotations(Goal)
    ;   query_annotations(Statement) ).

query_annotations(Statement) :-
    ( var(Statement) -> true
    ; Statement = [Head|Args], atom(Head)
    -> ( Head == ':' -> annotation_error(Statement)
       ; Head == 'Assuming'
       -> throw(error(domain_error(nested_assuming, Statement),
                      context(query/3, 'Assuming is only the outermost query statement')))
       ; ( memberchk(Head, ['And','Or','Not','Implication','ForAll','Exists','WithPrior'])
         ; 'bidirectional-implication-form?'(Head, true) )
       -> maplist(query_annotations, Args)
       ; true )
    ; true ).

assumed_annotations(Fact) :-
    ( nonvar(Fact), Fact = [':', _, Statement, _] -> query_annotations(Statement)
    ; nonvar(Fact), Fact = ['Implication'|_], \+ assumption_rule(Fact)
    -> throw(error(domain_error(assumed_rule, Fact),
                   context(query/3, 'unsupported assumed implication')))
    ; query_annotations(Fact) ).

% A class membership (Member x P) is the unary statement (P x) (#96), and a
% class link (Inheritance A B) the implication (A $x) -> (B $x) between two
% unary predicates (step C): one statement in either form, with one key and
% one evidence identity. Every source statement (facts, rules, queries,
% base-rate patterns) is rewritten here, at every subterm: a statement quoted
% as a predicate argument is the same proposition, which a rule may conclude.
% Answers keep the written shape. A class is a symbol or a variable that names
% no reserved head: an expression class would make an expression-headed key,
% and a connective or computation class would make the statement that
% connective.
'member-canon'(Term, Canon) :-
    (   nonvar(Term), Term = [Head|Args]
    ->  (   Head == 'Member'
        ->  (   Args = [X, Class], canon_class(Class)
            ->  'member-canon'(X, CanonX), Canon = [Class, CanonX]
            ;   throw(error(domain_error(member_class, Term),
                            context(compileadd/2, 'a Member class must be a symbol naming no connective, computation or internal head, or a variable'))) )
        ;   Head == 'Inheritance'
        ->  (   Args = [Sub, Super], canon_class(Sub), canon_class(Super)
            ->  Canon = ['Implication', [Sub, X], [Super, X]]
            ;   throw(error(domain_error(inheritance_class, Term),
                            context(compileadd/2, 'Inheritance links two classes, each a symbol naming no connective, computation or internal head, or a variable'))) )
        ;   maplist('member-canon', Term, Canon) )
    ;   Canon = Term ).

canon_class(Class) :- var(Class) ; atom(Class), \+ reserved_head(Class).

% An answer of a written statement's canonical form, with each written
% Member and Inheritance restored. The answer's own terms are kept: its
% binders and variables are not the written ones. An open class never answers
% with a reserved head, such as an existential claim key.
'member-shape'(Written, Answer, Shaped) :-
    (   nonvar(Written), Written = [Head|Args], nonvar(Answer), Answer = [AnswerHead|AnswerArgs]
    ->  (   Head == 'Member', AnswerArgs = [X]
        ->  \+ reserved_head(AnswerHead), Args = [WrittenX, _],
            'member-shape'(WrittenX, X, ShapedX), Shaped = ['Member', ShapedX, AnswerHead]
        ;   Head == 'Inheritance'
        ->  AnswerHead == 'Implication', AnswerArgs = [[Sub, X], [Super, Y]], X == Y,
            \+ reserved_head(Sub), \+ reserved_head(Super), Shaped = ['Inheritance', Sub, Super]
        ;   same_length(Written, Answer)
        ->  maplist('member-shape', Written, Answer, Shaped)
        ;   Shaped = Answer )
    ;   Shaped = Answer ).

% Heads the chainer reads as syntax or keeps for itself: connectives,
% binders, computations and internal keys. No class may name one, and no
% unary fact under one is a class.
reserved_head(Head) :-
    atom(Head),
    (   memberchk(Head, ['Member','Inheritance','And','Or','Not','Implication','ForAll','Exists',
                         'WithPrior','Assuming',':','CPU','RuleTruth','ExistentialClaim','ExistsJudgment',
                         'QuantifiedRule','ExistentialAlternatives','ImplicationInstanceSample'])
    ;   'bidirectional-implication-form?'(Head, true)
    ;   'compound-connective?'(Head, true)
    ;   'source-computation-head?'(Head, true)
    ), !.

'reserved-head?'(Head, Result) :- ( reserved_head(Head) -> Result = true ; Result = false ).

% Which arguments of a source form are statements (s) and which data (d).
statement_mask(Head, Args, Mask) :-
    (   ( memberchk(Head, ['And','Or','Not','Implication'])
        ; 'bidirectional-implication-form?'(Head, true)
        ; 'compound-connective?'(Head, true) )
    ->  same_length(Args, Mask), maplist(=(s), Mask)
    ;   memberchk(Head-Mask, ['ForAll'-[d,s], 'Exists'-[d,s], 'WithPrior'-[s,s],
                             'Assuming'-[s,s], ':'-[d,s,d], 'ExistentialClaim'-[s],
                             'KnownExistential'-[d,s], 'ExistentialResidual'-[d,s],
                             'RuleTruth'-[s], 'MapDist'-[d,s,d,d,d], 'Map2Dist'-[d,s,d,s,d,d,d]])
    ->  same_length(Args, Mask)
    ;   memberchk(Head, ['FoldAll','FoldAllValue','FoldAllTruth','AverageDist'])
    ->  Args = [_|Rest], same_length(Rest, Data), maplist(=(d), Data), Mask = [s|Data]
    ).

% One arity per head (D4): every per-predicate table is keyed by head, so a
% head stated with two arities would share one declaration between two
% predicates. Checked before a source is compiled, recorded once it is stored.
:- dynamic source_head_arity/3.

'source-heads-free!'(KB, Statement, true) :-
    findall(Head-Arity, source_head(Statement, Head, Arity), Pairs),
    sort(Pairs, Heads),
    forall(member(Head-Arity, Heads),
           ( ( member(Head-Other, Heads), Other \== Arity
             ; source_head_arity(Head, KB, Other), Other \== Arity )
           -> throw(error(domain_error(predicate_arity, [Head, Arity, Other]),
                          context(compileadd/2, 'a predicate head takes one arity')))
           ;  true )).

'record-source-heads!'(KB, Statement, true) :-
    forall(source_head(Statement, Head, Arity),
           ( source_head_arity(Head, KB, Arity) -> true ; assertz(source_head_arity(Head, KB, Arity)) )).

% The predicate statements at a canonical source's statement positions: a
% symbol, or an atom whose head is no computation; a variable is none. A
% symbol statement is a head of arity 0.
source_atom(Statement, Atom) :-
    nonvar(Statement),
    (   atom(Statement) -> Atom = Statement
    ;   Statement = [H|Args], atom(H),
        (   statement_mask(H, Args, Mask)
        ->  nth1(I, Mask, s), nth1(I, Args, Arg), source_atom(Arg, Atom)
        ;   'source-computation-head?'(H, false), H \== 'CPU', Atom = Statement ) ).

source_head(Statement, Head, Arity) :-
    source_atom(Statement, Atom),
    ( atom(Atom) -> Head = Atom, Arity = 0 ; Atom = [Head|Args], length(Args, Arity) ).

