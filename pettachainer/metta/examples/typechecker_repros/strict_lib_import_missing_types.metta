;; PeTTa's own lib_import.metta must be loadable by a strict program.
;; At 45b1b81 this fails before the caller can use static-import! because
;; import_prolog_functions_from_file/2 has no declared or inferable type.
!(import! &self (library lib_import))

!(assertEqual true true)
