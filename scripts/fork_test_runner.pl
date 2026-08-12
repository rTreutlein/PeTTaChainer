:- use_module(library(unix)).

run_forked_tests :-
    getenv('PETTA_FORK_TEST_FILES', FileList),
    atomic_list_concat(Files, ':', FileList),
    getenv('PETTA_JOBS', JobsText),
    atom_number(JobsText, Jobs),
    run_forked_tests(Files, Jobs, [], 0, Failed),
    ( Failed =:= 0
    -> true
    ;  throw(error(forked_tests_failed(Failed), _))
    ).

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
    report_test_status(Status, File, Failed0, Failed1),
    run_forked_tests(Files, Jobs, Remaining, Failed1, Failed).

run_test_child(File) :-
    getenv('PETTA_FORK_LOG_DIR', LogDir),
    file_base_name(File, BaseName),
    directory_file_path(LogDir, BaseName, LogFile),
    open(LogFile, write, Log),
    set_prolog_IO(user_input, Log, Log),
    ( catch(load_metta_file(File, _), Error,
            ( print_message(error, Error), fail ))
    -> close(Log), halt(0)
    ;  close(Log), halt(1)
    ).

report_test_status(exited(0), File, Failed, Failed) :-
    !,
    format('PASS ~w~n', [File]).
report_test_status(Status, File, Failed0, Failed) :-
    Failed is Failed0 + 1,
    format('FAIL ~w (~w)~n', [File, Status]),
    getenv('PETTA_FORK_LOG_DIR', LogDir),
    file_base_name(File, BaseName),
    directory_file_path(LogDir, BaseName, LogFile),
    read_file_to_string(LogFile, Log, []),
    format('~s', [Log]).
