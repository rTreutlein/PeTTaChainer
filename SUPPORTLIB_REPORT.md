# Support-library extraction (branch `supportlib`)

## Commits

- `8a8e7b4a` Replace `terms-unifiable?` by the `=?` builtin.
- `1bab3c23` `scripts/core_count.py` reports `pettachainer/metta/lib/` apart from the core.
- `602b4960` Move chainer-independent natives into `lib/`; `inference-clock` replaced by `current-time`.
- `46fe66f2` Layer inventory (`docs/metta/layers.md`) updated for the moved names.

## Builtin duplicates replaced

| Removed | Builtin | Evaluation difference and how it was checked |
|---|---|---|
| `terms-unifiable?` (execution.pl) | `=?` (src/metta.pl:64, `\+ \+ A=B`) | The native had `Atom` parameters, so its arguments were never evaluated. `=?` is eager. Passed as is, `($want-proof $want-tv)` compiled to a runtime `reduce([G,H],D1)`, because the head is a variable. Written as `(data $want-proof $want-tv)` it compiles to `D1=[G,H]`, the same construction as before. The right side, `((assuming $proof) $tv)`, stays data either way. Checked in the dumped Prolog clause. |
| `inference-clock` (runtime_state.pl) | `current-time` (`get_time/1`) | The builtin has no type, and strict mode rejected its open result flowing into `inference-add! Number`. `lib/natives.metta` declares `(: current-time (-[det]-> Number))`. The compiled call is identical. |

The whole compiled program was dumped with `petta` (non-silent) before and after, and every clause was diffed. Apart from the `=?` site above and the `execution-finally` → `finally` rename, the clauses are identical.

## Moved to `lib/`

- `lib/natives.pl`: `declare-natives!`, `declare-forward!` (was `execution-declare!`), `finally` (was `execution-finally`), and the host bridge `metta_call` / `metta_call_text` / `metta_call_terms` / `metta_data`.
- `lib/collections.pl`: `alpha_unique_keys`, `hash-set` / `hash-union` / `hash-subset?` / `hash-intersection`, `heap_pop`, `heap-empty?`.
- `lib/numeric.pl`: `beta_kl`, `digamma`.
- `lib/natives.metta`: the signatures of all of these, the `declare-natives!` type, the SWI heap imports and types (moved out of `bootstrap.metta` and `core/types.metta`), and the builtin result types for `sort-atom` and `current-time`.
- Deleted because they became empty: `prolog/execution.pl`, `core/runtime_terms.pl`.

## Tokens (`scripts/core_count.py`, o200k)

| | core | lib | total |
|---|---|---|---|
| before (d5ec9bfa) | 324,436 | 620 | 342,741 |
| after | 322,472 | 2,543 | 342,700 |

Core is down 1,964 tokens and the total is down 41.

## Gates

- `verify.sh` (capped `--slots 16`): all six gates PASS, with 4,554 Python query rows and 0 aborts.
- `compare.sh master --full`: PASS, accuracy identical in all 22 cases, no flags. Fuzz wall time went from 53 s to 65 s. That change was not flagged, and the compiled code is identical.
- `compare.sh anchor --canary`: PASS. 0 blocking flags; all 9 behind-anchor deltas are on master too.

## Duplicates left in off-limits files (for later)

- `hash-set` is the builtin `sort/1` (SWI `sort/2`). Its callers are in `runtime/evaluator/*`.
- `stored-number` (core/runtime_terms.metta) is lib_roman's `checked-number` (`the Number`). Its callers are in `runtime/evaluator/values.metta`.
- `prolog/event_values.pl`: `safe_log`, `log_add`, `log_sum` and `exp_diff` are generic log-space arithmetic that belongs in `lib/numeric.pl`. `bit_of` is `nth0/3` under another name and could be inlined.
- `chainer-first-or` and `chainer-acyclic-term?` are generic, but their `chainer-` names are used from the evaluator. They should be renamed and moved together.

## Not replaced (near-duplicates that differ)

- `alpha_unique_keys` vs `alpha-unique-atom`. PeTTa keys its set by `term_hash` of a numbervar'd copy, so two distinct terms that collide in the hash lose one of them. Ours uses a trie, which is exact variant semantics.
- `stored-list-member?` (`==`) vs `is-member` / `is-alpha-member`, which unify.
- `append-flat` vs `append`. `append` has no list type and is nondet unless arg0 is proven a proper list.

## Upstreaming candidates for PeTTa

- **`finally`**: a try/finally over `setup_call_cleanup`. Today the only way to run cleanup on success, failure, exceptions and cuts without `reduce/2` swallowing the error is a custom native. Every long-running MeTTa program that holds global state (a chainer's scope, a temp KB) needs it.
- **`declare-natives!` / `declare-forward!`**: PeTTa has `import_prolog_function` and separate type declarations, but no single table form that registers a native's name, arity and typed signature in one place and keeps load-cache ownership. Forward declarations of MeTTa functions defined in later modules (arity registration) are a general need of mutually recursive multi-file programs.
- **A variant-exact `alpha-unique-atom`**: replace the `term_hash` assoc with a trie, as `alpha_unique_keys` does. The current builtin is unsound under hash collisions.
- **Result types for `current-time` (Number) and `sort-atom` (`(List $a)`)** in builtin_registry. Without them, strict programs must redeclare these signatures themselves.
- **Host bridge (`metta_call`)**: a Python-to-MeTTa call that passes data arguments without compiling a runnable, and returns results as text or janus terms. This belongs next to PeTTa's own Python API.
