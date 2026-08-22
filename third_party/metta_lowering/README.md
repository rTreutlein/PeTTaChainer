# MeTTa lowering

This vendored MeTTa library contains the generic MeTTa-to-Prolog source
lowering and runtime encoding used by PeTTaChainer. The PeTTaChainer core
combines it with the PLN rule definitions in `rules.metta`.

Query lowering remains in the core because it currently depends on
PeTTaChainer's inheritance-specific rule compilation. The compiler assembly
therefore remains beside `rules.metta` as well.
