% Measurement-only wrapper, loaded after the runtime library. No answer changes.
:- use_module(library(prolog_wrap)).
:- use_module(library(http/json)).
:- dynamic seen/1.

:- wrap_predicate(event_node:event_node_moments(Vars, Terms, Goals, Answers), confvar,
                  Wrapped,
                  ( call(Wrapped),
                    Node = node(Vars, Terms, Goals, Answers),
                    ( seen(Node) -> true
                    ; assertz(seen(Node)),
                      getenv('CONFVAR_CAPTURE', Prefix), current_prolog_flag(pid, Pid),
                      format(atom(Path), '~w.~d.jsonl', [Prefix, Pid]),
                      ( getenv('CONFVAR_CASE', Case) -> true ; Case = benchmark ),
                      term_string(Node, Text, [quoted(true)]),
                      setup_call_cleanup(open(Path, append, Out),
                        (json_write_dict(Out, _{case:Case, node:Text}, [width(0)]), nl(Out)),
                        close(Out)) ) )).
