:- multifile prolog:show_profile_hook/1.

% Suppress SWI's automatic GUI/text profile display when the caller sets
% user:profile_no_show/0 around profile/2.
prolog:show_profile_hook(_Options) :-
    current_predicate(user:profile_no_show/0),
    catch(user:profile_no_show, _, fail),
    !.
