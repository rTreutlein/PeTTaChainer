% Core term encoding and indexed lookup keys. No store or policy calls.
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

% A link is recorded once, by a 60-bit digest of the link term (SHA-1 of the
% term up to variable renaming): a record stays one integer however large the
% link, and two different links share a digest with probability about
% n^2 / 2^61.
'link-digest'(Link, Digest) :-
    copy_term_nat(Link, Copy), variant_sha1(Copy, Hex),
    sub_atom(Hex, 0, 15, _, Prefix), atom_concat('0x', Prefix, Number), atom_number(Number, Digest).

% Declarations name a class itself (D5): after #96 and step C no statement has
% the head Member or Inheritance, so a declaration on one would silently apply
% to nothing.
'declared-head!'(Head, true) :-
    (   memberchk(Head, ['Member', 'Inheritance'])
    ->  throw(error(domain_error(predicate_head, Head),
                    context(declaration/2, 'Member and Inheritance are no predicates: declare each class as a head')))
    ;   true ).
