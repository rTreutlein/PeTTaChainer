:- multifile prolog:show_profile_hook/1.

prolog:show_profile_hook(_Options) :-
    current_predicate(profile_no_show/0),
    profile_no_show,
    !.
