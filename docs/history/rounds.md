# Round reports

Each delegated round handed back a root `<ROUND>_REPORT.md`. The reports stay
in history; read one with `git show <commit>:<ROUND>_REPORT.md` (the commit is
the report's final version). Live design lives in `docs/metta/`.

| Round | Commit | Date | Outcome |
| --- | --- | --- | --- |
| ABSTRACTION | 9102bd1c | 2026-10-29 | Extracted generic collection operations and one shared MeTTa syntax module; -536 tokens. |
| BOUNDED | dbf0bbbb | 2026-10-29 | Compiler list walkers replaced by shared collection operations, declarations moved to `datatype`, specialization keeps the full normalized rule. |
| CLEANUP | 2ad70bdf | 2026-10-29 | Evaluator contract and deletion inventory (`docs/metta/cleanup_inventory.md`); three helpers removed. |
| E3 | a6783416 | 2026-10-29 | Event-node dependence modelled through shared conditional parents in `event_graph.pl`. |
| MERGE1 | 39c1af64 | 2026-10-29 | Partial: separate raw-STV source namespace removed; the one-lowering goal was not reached. |
| MERGE1B | f1ca759f | 2026-10-29 | Implication judgment reads unified and the positive namespace deleted; master's 0.99 open-proof discount kept. |
| MERGE2 | d1ee51a7 | 2026-10-29 | Stopped, documentation only: compound-output audit in `docs/metta/node_outputs.md`. |
| SCC | 80ea5628 | 2026-10-29 | Evaluator split into merge, fold and sampling units with typed reader capabilities to shrink the call cycle. |
| SIMPLIFY_FORWARD | c2f342a7 | 2026-10-29 | Forward base-rate tally made direct; the generic forward sampling framework removed. |
| BOILERPLATE2 | 2b6c42a8 | 2026-10-30 | 86 type groups converted to `datatype`; native entry points declared in one table (`core/natives.metta`). |
| COMPLETION_RECIPE | 3c87d737 | 2026-10-30 | Antecedent-completion recipe stored once per rule instead of on executable inputs; peak RSS back to baseline. |
| POSTERIOR1 | 575420f4 | 2026-10-30 | Checkpoint only: fixture/oracle audit and prior/variance fixes ahead of posterior route deletion. |
| ROUND_METRICS | 4443fe99 | 2026-10-30 | `scripts/round_metrics.py` logs per-landing metrics from `land.sh`. |
| STORE_DECL | c39d127c | 2026-10-30 | One store schema generates all store declarations, bindings and overlay policies. |
| STRUCT1 | 48bdacf5 | 2026-10-30 | Vocabulary, logic configuration, rule policy and rate plans moved out of the compiler. |
| STRUCT2 | a9cd7e1b | 2026-10-30 | Source catalog separated from executable inference applications. |
| STRUCT3 | 3d72b4c6 | 2026-10-30 | Proof semantics recorded as immutable records at construction. |
| STRUCT4A | 84496c3e | 2026-10-30 | One owner for value publication and eviction. |
| STRUCT4B | fbdfe26c | 2026-10-30 | One owner for exposed KB copies. |
| CONFVAR | c3ee6d01 | 2026-10-31 | Round 1 stopped (first-order variance not conservative); round 2 landed the closed-form confidence bound. Measurements in `experiments/confvar/` at that commit. |
| STRUCT5 | ca236838 | 2026-10-31 | Statistical ledger owns the contribution lifecycle. |
| STRUCT6 | 40d329fd | 2026-10-31 | One execution owner for query scopes and allowances. |
| STRUCT7 | 23d62195 | 2026-10-31 | Application discovery separated; owner-to-evaluator cycles broken. |
| STRUCT8 | 13622cf3 | 2026-10-31 | Store ownership completed; reciprocal subsystem pairs 22 -> 5. |
| STRUCT9 | c1a4bb99 | 2026-10-31 | Raw stores layered below readers and installation policy; largest store SCC split. |
| STRUCT10 | 4f639adf | 2026-10-31 | Generic terms and configuration moved out of stores; two-way subsystem pairs 5 -> 2. |
| FIX154 | 6fd4fc88 | 2026-11-01 | Compound settling preserves reader bindings (#154, #151). |
