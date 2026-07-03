To run metta code use the petta executable example: "petta test.metta"

To run most tests you should be in the pettachainer/metta directory. if you run petta form somewhere else the imports might break.
When writing metta code take care not to introduce unintended non determinism.
Example:
(= (f  a) a)
(= (f $var) b)

!(f a)
=>
(a b)

If you change something never leave any old code around for backwards compatibility.
Always delete all old code. If the old code was good we would't have needed the new one.

If you have to choose between 2 ways to do something always pick the one that is cleaner and better in the long term.
Don't take any shortcuts. Hard things are worth doing right. And the best solution is usually the simplest but getting there takes effort.

Write code in the cleaned-up style from the start instead of adding helpers and removing them later.
If a helper becomes unused or survives only because tests still call it, delete it and rewrite the tests.
Do not keep dead helpers around as test scaffolding.

Prefer fewer named functions.
Inline single-use wrappers, trivial aliases, and helpers that only rename one match, one constructor, or one expression.
Only introduce a helper when it materially improves readability, is reused enough to justify its existence, or marks a real semantic boundary.

Do not add defensive code when the underlying indexed match already fails cleanly.
If a missing match naturally becomes `()`, prefer that over extra `if` guards.
The best code is no code.

Prefer `let*` for sequential bindings instead of nested `let`.
Keep destructuring exact and simple.
Do not add extra staging variables unless they make the code easier to read.

Prefer `fold-flat` or `map-flat` over hand-written recursive list walkers when the semantics are the same.
Do not keep recursive helper functions whose only job is to iterate over a list once.

For state stores, design the representation for first-argument indexing in the generated Prolog.
Prefer dedicated spaces keyed by the real lookup key over tagged tuples in one mixed store.
Keep the external user-facing term shape separate from the internal runtime shape when that improves indexing and search performance.

Be careful around MeTTa reduction and compiler boundaries.
Some helpers should stay if inlining them changes specialization, leaves partial lets unreduced, or changes search semantics.
This is the main exception to the "prefer fewer functions" rule.
Do not keep a helper just because it feels tidy, but do keep it if direct inlining is observably worse in compiled behavior.

When simplifying code, rerun the relevant tests immediately.
If a cleanup changes behavior, revert it instead of rationalizing it.

The public API is documented in metta/API.md. Never remove or change the signature
of anything listed there during an internal cleanup, even if only a test calls it.
Everything not listed is internal and may be inlined or removed once it has no
caller; a reference from a unit test alone does not make a helper public — rewire
or drop the test with it. Always grep tests/ before removing a function so you know
what the change touches.
