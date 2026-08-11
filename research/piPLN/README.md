# piPLN Paper Translation in MeTTa

This folder translates the main formulas from `../../piPLN_riposte_draft_v6.pdf`
into runnable MeTTa.

The main file is:

- `paper_translation.metta`
- `chart_selection_prototype.metta`

It is written as commented code:

- comments paraphrase the paper section by section
- MeTTa definitions replace the math formulas
- `!(test ...)` forms give explicit runnable examples

Run it from the repository root:

```bash
petta research/piPLN/paper_translation.metta
petta research/piPLN/chart_selection_prototype.metta
```

Covered topics:

- persistent context-indexed evidence
- p-bits as positive and negative evidence
- evidence-count quantale
- projection to PLN STVs
- beta-posterior projection
- Bayesian likelihood multiplication as count addition
- bounded p-bit propagation quantale
- evidence order versus truth order
- CD logic quantale
- local event quantale and why probability valuation is local/lax
- product control quantale carrying assumptions, evidence, weakness, cost, and provenance
- bird/penguin local-chart example
- distributional truth values in PeTTaChainer

`chart_selection_prototype.metta` is a smaller companion that focuses only on
runtime derivation of `TaskContext`: it shows candidate contexts, subtype-based
applicability, explicit specificity via `TypeDepth`, adequacy checks, selection,
chart construction, and query projection.

This is not a full piPLN implementation. It is an executable reading guide where
the paper's formulas are represented as small MeTTa functions and tests.
