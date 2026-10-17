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
