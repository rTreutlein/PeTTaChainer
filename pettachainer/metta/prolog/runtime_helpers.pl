% Event-node semantics and numerical contracts: docs/metta/event_node_contract.md.
:- use_module(library(heaps)).
:- use_module(library(assoc)).
:- use_module(library(nb_set)).
:- use_module(library(yall)).
:- dynamic support_identity/3, support_identity_owner/1.
:- ensure_loaded(context_overlay).
:- ensure_loaded(ingestion).
:- ensure_loaded(sorts).
:- use_module(event_node).
:- ensure_loaded(event_graph).

:- ensure_loaded(event_adapters).

% Rank claims by depth, cost and age, then their pending enumeration sequence.
% Never compare the payload: its hashes include the process's random KB id.
'sk-order-claims'(Claims, Sorted) :-
    findall([Depth,Cost,Age,Sequence]-Claim,
        ( nth0(Sequence,Claims,Claim), Claim=['sk-claim',Depth,Cost,Age,_] ), Pairs),
    keysort(Pairs, Ranked), pairs_values(Ranked, Sorted).

% Membership is evaluation-local and unordered. The pending journal still
% preserves first-arrival order; MAIN and every assumption own distinct tries.
'sk-force-causes!'(Key, Row, Causes, []) :-
    ( context_active(C) -> true ; C=main ),
    ( sk_forced_seen(C,Trie) -> true
    ; trie_new(Trie), assertz(sk_forced_seen(C,Trie)) ),
    forall(member(Cause,Causes),
        ( trie_insert(Trie,forced(Key,Row,Cause))
        -> 'context-add!'('&sk_forced',[Key,Row,Cause],true)
        ; true )).

'sk-force-reset!'([]) :-
    retractall(event_graph_memo(_, _, _)),
    retractall(event_graph_scope(_, _, _, _)),
    retractall(event_graph_plan(_, _, _, _, _)),
    ( context_active(C) -> true ; C=main ),
    forall(retract(sk_forced_seen(C,Trie)),trie_destroy(Trie)).

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

% PeTTa arrows have one result position. Package SWI's three relational
% get_from_heap/4 outputs into one positional product.
heap_pop(Heap, [Priority, Value, Rest]) :-
    get_from_heap(Heap, Priority, Value, Rest).

% Test before popping, so a caller can pop without collecting the result: a
% collected pop copies the whole remaining heap.
'heap-empty?'(Heap, Empty) :-
    (   empty_heap(Heap) -> Empty = true ; Empty = false ).

% A statically imported rule dump stores its rule ids without advancing the
% live counter, so the counter's next id may already be taken: a new live rule
% then takes the id past every stored live one. Temp ids start at 10^9.
'fresh-rule-id'(Next, Id) :-
    (   catch(rules('runtime-rule-row', Next, _, _), error(existence_error(procedure, _), _), fail)
    ->  aggregate_all(max(I), (rules('runtime-rule-row', I, _, _), I < 1000000000), Max),
        Id is Max + 1
    ;   Id = Next
    ).

% Whether a rule's hazard may have changed since the last evaluation: a head
% gained or lost a stage position (prolog/sorts.pl), or a KB's rule-change
% hazard was set. The evaluation then brings every standing instance tally to
% its rule's hazard (sk-rehazard-tallies!).
:- dynamic hazards_changed/0.
'hazards-changed!'(true) :- ( hazards_changed -> true ; assertz(hazards_changed) ).
'take-hazards-changed'(Result) :- ( retract(hazards_changed) -> Result = true ; Result = false ).

% A term with the constant arguments of its atoms replaced by variables, one
% per constant, so the samples of one link share one pattern; heads and
% numbers stay.
'generalize-constants'(Term, General) :-
    generalize_constants(Term, General, [], _).

generalize_constants(Term, Term, Seen, Seen) :- var(Term), !.
generalize_constants([Head|Args], [Head|GArgs], Seen0, Seen) :- atom(Head), !,
    foldl(generalize_argument, Args, GArgs, Seen0, Seen).
generalize_constants(Terms, General, Seen0, Seen) :- is_list(Terms), !,
    foldl(generalize_constants, Terms, General, Seen0, Seen).
generalize_constants(Term, Term, Seen, Seen).

generalize_argument(Arg, General, Seen0, Seen) :-
    (   atom(Arg)
    ->  ( memberchk(Arg-Var, Seen0) -> General = Var, Seen = Seen0 ; Seen = [Arg-General|Seen0] )
    ;   generalize_constants(Arg, General, Seen0, Seen) ).

% Hash a lookup column with every variable replaced by one marker, so a row
% keeps an integer SWI can JIT-index; =alpha on the stored key still decides.
'index-hash'(Term, Hash) :-
    (   ground(Term)
    ->  term_hash(Term, Hash)
    ;   % Hash markers must not run attributes on copied typed variables.
        % The original term keeps its constraints for actual matching.
        copy_term_nat(Term, Copy),
        term_variables(Copy, CopyVariables),
        maplist(=('goal-key-hash-variable'), CopyVariables),
        term_hash(Copy, Hash)
    ).

% A list-shaped statement is JIT-indexed by its head only, so &kb rows are also
% stored under the hash of each statement prefix: the head with its first one,
% two, ... arguments, up to the first argument that is not ground. Longest
% prefix first.
'statement-prefix-hashes'(Statement, Hashes) :-
    (   nonvar(Statement), Statement = [Head|Args], atomic(Head)
    ->  prefix_hashes(Args, [Head], [], Hashes)
    ;   Hashes = []
    ).

prefix_hashes([Arg|Args], Reversed, Hashes0, Hashes) :-
    ground(Arg), !,
    Prefix = [Arg|Reversed],
    reverse(Prefix, Statement),
    term_hash(Statement, Hash),
    prefix_hashes(Args, Prefix, [Hash|Hashes0], Hashes).
prefix_hashes(_, _, Hashes, Hashes).

% Each successive head on the antecedent's first-child path is a more
% selective prefix. Stop at a variable: every unifying ground query includes
% the prefixes of its open templates, including Not's nested predicate.
implication_antecedent_prefixes(Term, Path, Hashes0, Hashes) :-
    (   nonvar(Term), Term = [Head|Args], atomic(Head)
    ->  Next = [Head|Path],
        term_hash(['implication-antecedent-prefix'|Next], Hash),
        (   Args = [First|_]
        ->  implication_antecedent_prefixes(First, Next, [Hash|Hashes0], Hashes)
        ;   Hashes = [Hash|Hashes0]
        )
    ;   Hashes = Hashes0
    ).

% A statement with variables is stored under the hash of exactly its longest
% ground prefix: the head's when it has none, 0 when its head is not an atom.
% A pattern with a ground prefix finds the entries whose longest prefix is at
% least as long as its own through its longest prefix in the prefix index, and
% the others under its shorter prefixes, its head and 0: a bounded number of
% indexed lookups however many entries share its head.
% Fact indexes also retain the nested antecedent's head path. Skeleton node
% indexes keep their existing prefix and scheduling semantics.
'kb-fact-prefix-hashes'(Statement, Hashes) :-
    'statement-prefix-hashes'(Statement, Prefixes),
    (   nonvar(Statement), Statement = [Head|Args], Head == 'Implication',
        nonvar(Args), Args = [Antecedent|_]
    ->  implication_antecedent_prefixes(Antecedent, [], [], Nested),
        append(Prefixes, Nested, Hashes)
    ;   Hashes = Prefixes
    ).

'statement-open-hash'(Statement, Hash) :-
    statement_index_hashes('statement-prefix-hashes', Statement, [Hash|_]).

'statement-open-probes'(Statement, Hashes) :-
    statement_index_hashes('statement-prefix-hashes', Statement, [_|Hashes]).

'kb-fact-open-hash'(Statement, Hash) :-
    statement_index_hashes('kb-fact-prefix-hashes', Statement, [Hash|_]).

'kb-fact-open-probes'(Statement, Hashes) :-
    statement_index_hashes('kb-fact-prefix-hashes', Statement, [_|Hashes]).

statement_index_hashes(PrefixFunction, Statement, Hashes) :-
    (   nonvar(Statement), Statement = [Head|_], atomic(Head)
    ->  call(PrefixFunction, Statement, Prefixes),
        term_hash(Head, HeadHash),
        append(Prefixes, [HeadHash, 0], Hashes)
    ;   Hashes = [0]
    ).

% Outer arguments cannot be filled with a binder's private slots.
'existential-outer-values?'(Values, Valid) :-
    ( sub_term(Term, Values), is_list(Term), Term = [Head, _], Head == 'exists-slot'
    -> Valid = false ; Valid = true ).

% A final tie uses alpha-normalized statement keys, not allocation/proof ids.
'existential-key-before?'(A, B, Before) :-
    copy_term(A, CA), numbervars(CA, 0, _),
    copy_term(B, CB), numbervars(CB, 0, _),
    ( CA @< CB -> Before = true ; Before = false ).

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

% What applying a refined rule can add, from its truth: its confidence, and
% for a CTV how far the consequent's probability moves with the antecedent
% (docs/metta/hypothesis_rules.md). An STV does not say, so it counts fully.
% Never 0: a rule that adds nothing is still reached with budget to spare.
'rule-truth-factor'(Tv, Factor) :-
    (   Tv = ['CTV', ['STV', S1, C1], ['STV', S0, _]], number(S1), number(C1), number(S0)
    ->  Raw is C1 * abs(S1 - S0)
    ;   Tv = ['STV', _, C], number(C) -> Raw = C
    ;   Raw = 1.0 ),
    Factor is max(Raw, 0.01).

% A link is recorded once, by a 60-bit digest of the link term (SHA-1 of the
% term up to variable renaming): a record stays one integer however large the
% link, and two different links share a digest with probability about
% n^2 / 2^61.
'link-digest'(Link, Digest) :-
    copy_term_nat(Link, Copy), variant_sha1(Copy, Hex),
    sub_atom(Hex, 0, 15, _, Prefix), atom_concat('0x', Prefix, Number), atom_number(Number, Digest).

:- ensure_loaded(proof_store).

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
    (   dormancy_row(rules('runtime-rule-row', Id, [Type, Ctx, Proof|_], Premises)),
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
        ;   \+ dormancy_row(rules('runtime-rule-row', _, [Type, Ctx|_], _)) -> true
        ;   dormancy_note_head(Type),
            Depth1 is Depth - 1,
            dormancy_row(rules('runtime-rule-row', _, [Type, Ctx, Proof|_], Premises)),
            (   memberchk(['CPU', 'SettlesFormula'|_], Premises) -> \+ \+ dormancy_settles(Premises)
            ;   forall(( member([PType, PCtx, _, _], Premises), PType \== 'CPU' ),
                       dormancy_premise_supported(Proof, PType, PCtx, Forbidden, [Type-Ctx|Path], Depth1)) ) ) ).

dormancy_premise_supported(Proof, Type, Ctx, Forbidden, Path, Depth) :-
    (   Type-Ctx \== Forbidden, Proof = [['antecedent-completion'|_]|_], \+ dormancy_derived(Type, Ctx) -> true
    ;   dormancy_supported(Type, Ctx, Forbidden, Path, Depth) ).

dormancy_derived(Type, Ctx) :-
    (   dormancy_complete(Type, Ctx) -> true
    ;   \+ \+ ( dormancy_row(rules('runtime-rule-row', _, [Type, Ctx, Proof|_], _)),
                 ( Proof = [by|_] ; Proof = [negated, [by|_]] ) ) ).

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
% confusing hash collisions. Destroy query-local storage even on an exception.
alpha_unique_keys(Keys, Unique) :-
    setup_call_cleanup(trie_new(Seen), alpha_unique_keys(Keys, Seen, Unique),
                       trie_destroy(Seen)).

alpha_unique_keys([], _, []).
alpha_unique_keys([Key|Keys], Seen, Unique) :-
    copy_term_nat(Key, Plain),
    (   trie_insert(Seen, Plain)
    ->  Unique = [Key|Rest]
    ;   Unique = Rest
    ),
    alpha_unique_keys(Keys, Seen, Rest).

% An answer is redundant when another answer with the same proof has a
% strictly more general statement, or a variant statement earlier in the list:
% of answers that instantiate each other, the first stays. Only identical
% ground proofs are compared; nonground proofs cannot be identical after the
% independent copies used for subsumption. The local index shares the inputs;
% findall retains order and copies each survivor just as MeTTa's collapse does,
% isolating variables between returned answers.
prune_answer_instances([], []) :- !.
prune_answer_instances([Answer], [Kept]) :- !, copy_term(Answer, Kept).
prune_answer_instances(Answers, Kept) :-
    numbered_answers(Answers, 1, Numbered),
    empty_assoc(Empty),
    reverse(Numbered, Reversed),
    foldl(index_answer_proof, Reversed, Empty-Empty, Index),
    findall(Answer, (member(Position-Answer, Numbered),
                     \+ answer_instance(Index, Position, Answer)), Kept).

numbered_answers([], _, []).
numbered_answers([Answer|Answers], Position, [Position-Answer|Numbered]) :-
    Next is Position + 1,
    numbered_answers(Answers, Next, Numbered).

index_answer_proof(Position-Answer, Before-Memo, After-NextMemo) :-
    (   nonvar(Answer), Answer = [_, _, Proof, _],
        proof_identity_hash(Proof, Memo, NextMemo, Hash)
    ->  (get_assoc(Hash, Before, Previous) -> true ; Previous = []),
        put_assoc(Hash, Before, [Position-Answer|Previous], After)
    ;   After = Before, NextMemo = Memo
    ).

% Hash the semantic proof DAG once per reference, without expanding it. An
% open leaf has no identity hash and passes through; collisions are checked
% by the same nonbinding proof comparison used by merging.
proof_identity_hash(Proof, Memo, NextMemo, Hash) :-
    (   proof_ref_id(Proof, Id)
    ->  (   get_assoc(Id, Memo, Hash) -> NextMemo = Memo
        ;   user:'&proof'(Id, Stored, _, _),
            (   opaque_proof_step(Stored)
            ->  term_hash(opaque(Id), Hash), ExpandedMemo = Memo
            ;   proof_identity_hash(Stored, Memo, ExpandedMemo, Hash) ),
            put_assoc(Id, ExpandedMemo, Hash, NextMemo) )
    ;   nonvar(Proof), Proof = [Head|Tail]
    ->  proof_identity_hash(Head, Memo, HeadMemo, HeadHash),
        proof_identity_hash(Tail, HeadMemo, NextMemo, TailHash),
        term_hash(node(HeadHash, TailHash), Hash)
    ;   ground(Proof), term_hash(leaf(Proof), Hash), NextMemo = Memo
    ).

answer_instance(Index-Memo, Position, Answer) :-
    nonvar(Answer), Answer = [_, _, Proof, _],
    proof_identity_hash(Proof, Memo, _, Hash),
    get_assoc(Hash, Index, Candidates),
    member(Other-General, Candidates),
    Other \== Position,
    '=alpha'(Answer, General, false),
    copy_term(Answer, [SpecificType, _, _, _]),
    copy_term(General, [GeneralType, _, GeneralProof, _]),
    subsumes_term(GeneralType, SpecificType),
    (   Other < Position
    ->  true
    ;   \+ subsumes_term(SpecificType, GeneralType)
    ),
    empty_nb_set(Seen), same_proof_terms(Proof, GeneralProof, Seen),
    !.

% What building a skeleton row or node of a term costs, in rows of the row
% allowance or steps of the budget: one, and one more for each 400 words of the
% term, about what storing, hashing and comparing that much of a term takes
% beyond a row's fixed cost (ONA reasoningbench_num: a row of a 9,000-word
% statement took 25 ms, one of a few words about 1 ms).
'term-cost'(Term, Cost) :- term_size(Term, Size), Cost is 1 + Size // 400.

% Whether node Specific is an instance of node General whose statement binds
% one of General's variables to a compound term: the term a recursive rule
% grows, as (Num (succ $x)) grows from (Num $x), and not a mere specialization
% such as (Reward op1 $t) of (Reward $op $t). Tested on attribute-free copies,
% so typed variables run no constraints.
'grows-from?'(General, Specific, Result) :-
    copy_term_nat(General, G),
    copy_term_nat(Specific, S),
    (   subsumes_term(G, S), G = [GT|_], S = [ST|_], term_size(ST, SS), term_size(GT, GS), SS > GS
    ->  Result = true ; Result = false ).

% Links the key a join read to the premise the join bound (sk-read-step):
% each variable of General, at a position where Instance, an instance of it,
% still has a variable, is unified with that variable, unless the join bound
% two variables of General to one of Instance. Where the join bound Instance
% further, General keeps its own variable, so the row reads the key that
% answered it, and evaluation still binds Instance's open variables through it.
'link-open-variables'(General, Instance, true) :-
    (   ground(General)
    ->  true
    ;   open_variable_pairs(General, Instance, Pairs, []),
        include(one_to_one(Pairs), Pairs, Linked),
        maplist(link_pair, Linked)
    ).

open_variable_pairs(General, Instance, Pairs, Tail) :-
    (   var(General)
    ->  (   var(Instance) -> Pairs = [General-Instance|Tail] ; Pairs = Tail )
    ;   compound(General), compound(Instance)
    ->  General =.. [_|GeneralArgs],
        Instance =.. [_|InstanceArgs],
        foldl(open_variable_pairs, GeneralArgs, InstanceArgs, Pairs, Tail)
    ;   Pairs = Tail
    ).

one_to_one(Pairs, General-Instance) :-
    \+ ( member(G-I, Pairs),
          ( G == General, I \== Instance ; I == Instance, G \== General ) ).

link_pair(Variable-Variable).

'rule-lookup-needs-occurs-check'(Term, Result) :-
    term_variables(Term, Variables),
    term_singletons(Term, Singletons),
    (   same_length(Variables, Singletons)
    ->  Result = false
    ;   Result = true
    ).

'ccls-index-occurs-matches'(LookupTemplate, Matches) :-
    current_prolog_flag(occurs_check, Previous),
    setup_call_cleanup(
        set_prolog_flag(occurs_check, true),
        (   current_predicate(ccls_index/3)
        ->  findall(
                [Matched, RuleId, Args],
                ( copy_term(LookupTemplate, Matched),
                  ccls_index(Matched, RuleId, Args)
                ),
                Matches)
        ;   Matches = []
        ),
        set_prolog_flag(occurs_check, Previous)).

% Deterministic bounded particle condensation. The strongest particles become
% anchors; each overflow particle is absorbed by the compatible anchor with
% the least Ward loss. This retains modes with meaningful mass, merges nearby
% numeric samples by weighted centroid, and costs O(support * budget).
particle_merge_resample(Pairs, Budget, Result) :-
    integer(Budget),
    Budget > 0,
    indexed_particle_pairs(Pairs, 0, Ranked),
    keysort(Ranked, Sorted),
    length(Sorted, Length), Taken is min(Budget, Length),
    length(Strongest, Taken), append(Strongest, Overflow, Sorted), pairs_values(Strongest, Anchors0),
    sort(1, @<, Anchors0, Anchors),
    absorb_overflow_particles(Overflow, Anchors, Merged),
    sort(1, @<, Merged, Ordered),
    maplist([component(_, Value, Weight), [Value, Weight]]>>true, Ordered, Result).

indexed_particle_pairs([], _, []).
indexed_particle_pairs([[Value, Weight]|Rest], Index,
        [key(NegativeWeight, Index)-component(Index, Value, Weight)|Ranked]) :-
    NegativeWeight is -Weight,
    NextIndex is Index + 1,
    indexed_particle_pairs(Rest, NextIndex, Ranked).

absorb_overflow_particles([], Anchors, Anchors).
absorb_overflow_particles([_-Particle|Rest], Anchors0, Anchors) :-
    closest_particle_anchor(Anchors0, Particle, none, Best),
    Best = best(_, AnchorIndex, Value, Weight),
    replace_particle_anchor(Anchors0, AnchorIndex, Value, Weight, Anchors1),
    absorb_overflow_particles(Rest, Anchors1, Anchors).

closest_particle_anchor([], _, Best, Best).
closest_particle_anchor(
        [component(AnchorIndex, Anchor, AnchorWeight)|Rest],
        component(_, Value, Weight), Best0, Best) :-
    (   particle_merge_term(
            Anchor, AnchorWeight, Value, Weight, Mean, DistanceSquared)
    ->  MergedWeight is AnchorWeight + Weight,
        Cost is AnchorWeight * Weight / MergedWeight * DistanceSquared,
        (   Best0 = best(BestCost, _, _, _), \+ Cost < BestCost
        ->  Best1 = Best0
        ;   Best1 = best(Cost, AnchorIndex, Mean, MergedWeight) )
    ;   Best1 = Best0
    ),
    closest_particle_anchor(
        Rest, component(_, Value, Weight), Best1, Best).

replace_particle_anchor(
        [component(Index, _, _)|Rest], Index, Value, Weight,
        [component(Index, Value, Weight)|Rest]) :- !.
replace_particle_anchor([Anchor|Rest], Index, Value, Weight,
        [Anchor|Updated]) :-
    replace_particle_anchor(Rest, Index, Value, Weight, Updated).

particle_merge_term(Left, _, Right, _, Left, 0.0) :-
    Left == Right,
    !.
particle_merge_term(Left, LeftWeight, Right, RightWeight, Mean, DistanceSquared) :-
    number(Left),
    number(Right),
    !,
    Mean is (LeftWeight * Left + RightWeight * Right) /
        (LeftWeight + RightWeight),
    Delta is Left - Right,
    DistanceSquared is Delta * Delta.
particle_merge_term(Left, LeftWeight, Right, RightWeight, Mean, DistanceSquared) :-
    compound(Left),
    compound(Right),
    compound_name_arguments(Left, Functor, LeftArgs),
    compound_name_arguments(Right, Functor, RightArgs),
    particle_merge_args(
        LeftArgs, LeftWeight, RightArgs, RightWeight,
        MeanArgs, DistanceSquared),
    compound_name_arguments(Mean, Functor, MeanArgs).

particle_merge_args([], _, [], _, [], 0.0).
particle_merge_args(
        [Left|LeftRest], LeftWeight, [Right|RightRest], RightWeight,
        [Mean|MeanRest], DistanceSquared) :-
    particle_merge_term(
        Left, LeftWeight, Right, RightWeight, Mean, HeadDistanceSquared),
    particle_merge_args(
        LeftRest, LeftWeight, RightRest, RightWeight,
        MeanRest, RestDistanceSquared),
    DistanceSquared is HeadDistanceSquared + RestDistanceSquared.

% A counter's value (change-state!), 0 before it is set.
'search-id-value'(Key, Value) :- ( nb_current(Key, Stored) -> Value = Stored ; Value = 0 ).

% The ordinary readers being computed, innermost first. The stack is a
% backtrackable global: a reader pushes a copy of its identity, restores the
% stack it found when it is done, and failure or an exception restores it by
% backtracking. Neither copies the stack.
'sk-push-reader!'(Reader, Readers) :-
    ( nb_current(sk_reading, Stored) -> Readers = Stored ; Readers = [] ),
    copy_term(Reader, Copy),
    b_setval(sk_reading, [Copy|Readers]).
'sk-restore-readers!'(Readers, true) :- b_setval(sk_reading, Readers).
% Each active reader, outermost first.
'sk-active-reader'(Reader) :-
    nb_current(sk_reading, Readers), reverse(Readers, Outermost), member(Reader, Outermost).

% Inference time, process-wide, in seconds: activation, search and evaluation
% of backward queries, and forward runs. A caller splits the wall time of its
% calls into inference and overhead with it; it costs two clock reads a call.
'inference-clock'(Time) :- get_time(Time).
'inference-add!'(Start, true) :-
    get_time(Now),
    flag(pettachainer_inference_seconds, Seconds, Seconds + Now - Start).
inference_seconds(Seconds) :- flag(pettachainer_inference_seconds, Seconds, Seconds).

% Optional query counters sit on backward-search hot paths. Keep their disabled
% check and enabled scalar updates native so diagnostics do not distort normal
% query performance with thousands of MeTTa state or space operations.
query_metrics_enabled(Enabled) :-
    ( nb_current(pettachainer_query_metrics_enabled, Stored) -> Enabled = Stored ; Enabled = false ).
query_metrics_set_enabled(Enabled, Enabled) :- nb_setval(pettachainer_query_metrics_enabled, Enabled).
query_metric_value(Key, Value) :- atom_concat(pettachainer_query_metric_, Key, G), 'search-id-value'(G, Value).
query_metric_set(Key, Value, Value) :-
    ( query_metrics_enabled(true) -> atom_concat(pettachainer_query_metric_, Key, G), nb_setval(G, Value) ; true ).
query_metric_increment(Key, Result) :-
    (   query_metrics_enabled(true)
    ->  query_metric_value(Key, Old), Result is Old + 1,
        atom_concat(pettachainer_query_metric_, Key, G), nb_setval(G, Result)
    ;   Result = 0
    ).

:- ensure_loaded(instance_regimes).

% Python's call of a chainer function (pettachainer.py): Fn applied to the
% arguments each MeTTa source in Sources reads as, every result collected in
% order, as a runnable `!(Fn Args)` returns them. Arguments that are data,
% which a runnable passes as they are, are passed without compiling one; any
% other argument, such as a nested call or a lambda a runnable evaluates
% first, is compiled as a runnable. As text, a result is printed as MeTTa
% prints it; as terms, an expression arrives through janus as a list and a
% symbol or string as a str, and since janus passes no unbound variable each
% is named as MeTTa prints it.
metta_call(Fn, Sources, Results) :-
    atom_string(Name, Fn),
    foldl(metta_call_source(Name), Sources, Results, []).
metta_call_source(Name, Source, Results, Rest) :-
    format(string(Expression), "(~s)", [Source]),
    sread(Expression, Args),
    (   maplist(metta_data, Args)
    ->  append(Args, [Result], CallArgs),
        Goal =.. [Name|CallArgs],
        findall(Result, Goal, Results, Rest)
    ;   format(string(Code), "!(~w ~s)", [Name, Source]),
        process_metta_string(Code, Own),
        append(Own, Rest, Results)
    ).
% What a runnable passes unevaluated: a variable, a number, symbol or string,
% or an expression of such terms whose head names no function, special form
% or translator rule.
metta_data(Term) :- var(Term), !.
metta_data(Term) :- atomic(Term), !.
metta_data([Head|Args]) :-
    (   atom(Head)
    ->  \+ fun(Head), \+ translator_rule(Head), \+ special_builtin_form(Head, Args, _)
    ;   metta_data(Head)
    ),
    maplist(metta_data, Args).
metta_call_text(Fn, Sources, Texts) :-
    metta_call(Fn, Sources, Results),
    maplist(swrite, Results, Texts).
metta_call_terms(Fn, Sources, Results) :-
    metta_call(Fn, Sources, Results),
    term_variables(Results, Variables),
    foldl([Variable, N0, N]>>(format(atom(Variable), '$_~d', [N0]), N is N0 + 1),
          Variables, 0, _).

:- ensure_loaded(hypothesis_candidates).

:- ensure_loaded(search_index).

% A producer must cover the entire query, without specializing either term.
'term-covers?'(General, Specific, Result) :-
    ( subsumes_term(General, Specific) -> Result = true ; Result = false ).

% Disconnected parts range over a Cartesian product. A separate joint rate
% would contradict that model; reject it rather than silently ignoring it.
'validate-base-rate!'(Pattern, Parts, TV, true) :-
    ( 'member-canon'(Pattern, Canonical), rate_class_link(Canonical)
    -> throw(error(domain_error(base_rate_class_link, Pattern),
                   context('set-base-rate'/3, 'a class link is a rule, no population: rate a class membership as (Member $x Class)')))
    ; true ),
    ( 'canon'(Pattern, [_, true]), \+ (nonvar(TV), TV = ['STV'|_])
    -> throw(error(domain_error(negated_base_rate_value, TV),
                   context('set-base-rate'/3, 'a negated statement takes an STV')))
    ; true ),
    ( Parts = [_,_|_]
    -> throw(error(domain_error(disconnected_base_rate, Pattern),
                   context('set-base-rate'/3, 'set a rate for each connected part')))
    ; true ).

% A canonical rate pattern stating a class link, (Inheritance A B) in any of
% its spellings, with either class a name or a variable, at its top or under a
% connective.
rate_class_link(Pattern) :-
    nonvar(Pattern), Pattern = [Head|Args],
    (   Head == 'Implication'
    ->  Args = [[Sub, X], [Super, Y]], var(X), X == Y,
        forall(member(Class, [Sub, Super]), ( var(Class) ; atom(Class) ))
    ;   memberchk(Head, ['And', 'Or', 'Not']), member(Arg, Args), rate_class_link(Arg) ), !.
