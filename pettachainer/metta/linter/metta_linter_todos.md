# MeTTa Linter TODOs

- Detect local reimplementation of stdlib helpers when a standard function already exists.
  - Example: `lint-list-append` should be flagged because stdlib `append` already exists.

- Detect hand-written list walkers that should be expressed with `lib_roman` combinators.
  - Flag `...-list` helper families that are just recursive traversal wrappers.
  - Prefer `map-flat`, `map-nested`, `fold-flat`, or other existing `lib_roman` helpers when the semantics are the same.

- Add a linter rule for avoidable one-off helper definitions inside lint code itself.
  - This should catch helpers that survive only because the linter has not yet been normalized against the stdlib.

- Extend list-helper detection beyond the current simple flat-list recursion patterns.
  - Add `map-nested`-style detection for walkers that branch on `is-expr`.
  - Generalize the current rules to helpers with extra fixed arguments, not just single-list-argument helpers.

- Add `autofix-safe` support for canonical source rewrites.
  - Safe examples: singleton `cons`, singleton `superpose`.
  - Keep style/semantic cleanups like `nested-let -> let*` as suggest-only until proven safe across compiled behavior.
