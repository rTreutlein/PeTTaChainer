# PLN formulas

This vendored MeTTa library contains PLN truth-value formulas, distribution
helpers, and the weighted-subset-sum inverse. It has no PeTTaChainer runtime
dependencies, while the chainer core imports it as its formula layer.

The library boundary reflects the formulas' purity, not a frozen API or
implementation. In particular, `truth_values.metta` changed as recently as the
week before this extraction and should be expected to keep evolving with PLN
semantics.
