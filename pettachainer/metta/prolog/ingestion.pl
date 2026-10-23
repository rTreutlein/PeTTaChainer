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
    Statement = [':', _, Type, _],
    ingestion_negation(Type),
    ( ingestion_closed([], Type) -> true
    ; throw(error(domain_error(fact_without_free_variables, Type),
                  context(compileadd/2, 'fact contains free variables'))) ).

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

% Asserted negations are unwrapped by compile_. Validate the entire leading
% chain before compilation: exact destructuring would silently fail on Not/0
% or Not/2, and an outer Not must not hide an invalid inner negation.
ingestion_negation(Type) :-
    ( nonvar(Type), Type = [Head|Args], Head == 'Not'
    -> ( Args = [Inner] -> ingestion_negation(Inner)
       ; throw(error(domain_error(unary_negation, Type),
                     context(compileadd/2, 'negation requires exactly one argument'))) )
    ; true ).

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
    ( Annotation = [':', Name, Source, Value], ground(Name), nonvar(Source), nonvar(Value),
      weighted_assumption(Source, Value, Statement, TV)
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
    ; \+ memberchk(Head, [':','CPU','ForAll','Exists','WithPrior','Assuming','Inheritance']),
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
