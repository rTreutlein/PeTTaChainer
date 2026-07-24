; Run from pettachainer/metta so this same file can benchmark another checkout:
;   sh /path/to/PeTTa/run.sh /absolute/path/to/typecheck_import_probe.metta
!(import! &self petta_chainer)
!(println! TYPECHECK_IMPORT_READY)
