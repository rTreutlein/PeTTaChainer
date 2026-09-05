:- use_module(library(unix)).

run_forked_tests :-
    getenv('PETTA_FORK_TEST_MANIFEST', Manifest),
    read_file_to_string(Manifest, FileList, []),
    split_string(FileList, "\n", "\n", FileStrings),
    maplist(atom_string, Files, FileStrings),
    getenv('PETTA_JOBS', JobsText),
    atom_number(JobsText, Jobs),
    length(Files, Total),
    run_forked_tests(Files, Jobs, [], 0, Failed),
    Passed is Total - Failed,
    format('~nSummary: ~d passed, ~d failed~n', [Passed, Failed]),
    halt(Failed).

run_forked_tests([], _, [], Failed, Failed) :- !.
run_forked_tests(Files, Jobs, Active, Failed0, Failed) :-
    Files = [File|Rest],
    length(Active, ActiveCount),
    ActiveCount < Jobs,
    !,
    fork(Pid),
    ( Pid == child
    -> run_test_child(File)
    ;  run_forked_tests(Rest, Jobs, [Pid-File|Active], Failed0, Failed)
    ).
run_forked_tests(Files, Jobs, Active, Failed0, Failed) :-
    wait(Pid, Status),
    selectchk(Pid-File, Active, Remaining),
    report_test_status(Pid, Status, File, Failed0, Failed1),
    run_forked_tests(Files, Jobs, Remaining, Failed1, Failed).

run_test_child(File) :-
    current_prolog_flag(pid, Pid),
    test_log_file(Pid, LogFile),
    open(LogFile, write, Log),
    set_prolog_IO(user_input, Log, Log),
    ( catch(load_metta_file(File, _), Error,
            ( print_message(error, Error), fail ))
    -> close(Log), halt(0)
    ;  close(Log), halt(1)
    ).

report_test_status(Pid, exited(0), File, Failed, Failed) :-
    test_log_file(Pid, LogFile),
    read_file_to_string(LogFile, Log, []),
    \+ sub_string(Log, _, _, _, 'backward-search-aborted'),
    !,
    format('PASS ~w~n', [File]).
report_test_status(Pid, Status, File, Failed0, Failed) :-
    Failed is Failed0 + 1,
    format('FAIL ~w (~w)~n', [File, Status]),
    test_log_file(Pid, LogFile),
    read_file_to_string(LogFile, Log, []),
    format('~s', [Log]).

test_log_file(Pid, LogFile) :-
    getenv('PETTA_FORK_LOG_DIR', LogDir),
    atom_concat(Pid, '.log', LogName),
    directory_file_path(LogDir, LogName, LogFile).
