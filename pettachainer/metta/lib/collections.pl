:- use_module(library(heaps)).

% The first of each group of variant terms, in order, keeping its variable
% sharing. Always release the trie.
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


% Sets of integers (key hashes) are SWI ordered sets, so union and membership
% are linear merges over short lists.
'hash-set'(Hashes, Set) :- sort(Hashes, Set).
'hash-union'(Left, Right, Set) :- ord_union(Left, Right, Set).
'hash-subset?'(Left, Right, Result) :- ( ord_subset(Left, Right) -> Result = true ; Result = false ).
'hash-intersection'(Left, Right, Both) :- ord_intersection(Left, Right, Both).

% PeTTa arrows have one result position. Package SWI's three relational
% get_from_heap/4 outputs into one positional product.
heap_pop(Heap, [Priority, Value, Rest]) :-
    get_from_heap(Heap, Priority, Value, Rest).

% Test before popping, so a caller can pop without collecting the result: a
% collected pop copies the whole remaining heap.
'heap-empty?'(Heap, Empty) :-
    (   empty_heap(Heap) -> Empty = true ; Empty = false ).
