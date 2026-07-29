benchmark_query([quote, Expression],
                [Results, CpuSeconds, Inferences]) :-
    statistics(cputime, CpuStart),
    statistics(inferences, InferencesStart),
    findall(Result, reduce(Expression, Result), Results),
    statistics(inferences, InferencesFinish),
    statistics(cputime, CpuFinish),
    CpuSeconds is CpuFinish - CpuStart,
    Inferences is InferencesFinish - InferencesStart.
