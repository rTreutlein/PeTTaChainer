# Example test policy

`../test.sh` runs every example listed in `supported.txt` after the unit tests.
These files are stable executable documentation: they must contain assertions,
finish in a reasonable time, and pass on every change.

The remaining examples are deliberately outside the default suite:

- `experimental_*.metta` and `*_prototype.metta` explore representations that
  are not part of the supported regression contract.
- `robot.metta` and `simple_base_rate_deduction_libpln.metta` take roughly one
  and two minutes respectively on the current runtime, so they belong in an
  eventual slow/extended suite.
- `flyingraven.metta` currently exposes unresolved interaction between direct
  negated evidence and higher-order positive inheritance evidence.
- `simple_base_rate_deduction_pettachainer.metta` currently exposes unresolved
  estimated-base-rate behavior after canonical inheritance merging.

Add a new example to `supported.txt` once it is deterministic, self-testing,
and fast enough for the default suite. Do not add scratch files such as
`tmp.metta`.
