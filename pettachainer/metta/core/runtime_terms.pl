% Keep first occurrences and their variable sharing. Always release the trie.
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

