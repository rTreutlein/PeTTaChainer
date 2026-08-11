;; Internal compiler assembly. Each imported module owns one compilation phase;
;; only bootstrap imports this file.
!(import! &self source_lowering)
!(import! &self rules)
!(import! &self runtime_encoding)
!(import! &self query_lowering)
