!(import! &self petta_chainer)

;; Higher-order inheritance (Bird -> Flier inferred from their instances) is
;; compiled against the same private evidence relation as ordinary inheritance
;; rules. The public boundary must still emit exactly one canonical result.

!(compileadd inheritanceQueryKb (: i1 (Inheritance a Bird) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i2 (Inheritance a Flier) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i3 (Inheritance b Bird) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i4 (Inheritance b Flier) (STV 1.0 0.9)))

(= (inheritance-query-result-shape $result)
   (case $result (
      ((: (inheritance-query (total-implication $_pos $_neg))
            (Inheritance Bird Flier) $_tv)
         canonical)
      ($_other noncanonical))))

(= (inheritance-query-result-tv (: $_proof $_type $tv)) $tv)

!(test (length (collapse (query 80 inheritanceQueryKb
   (: $prf (Inheritance Bird Flier) $tv)))) 1)
!(test (map-flat inheritance-query-result-shape
      (collapse (query 80 inheritanceQueryKb
         (: $prf (Inheritance Bird Flier) $tv))))
   (canonical))
!(test (map-flat inheritance-query-result-tv
      (collapse (query 80 inheritanceQueryKb
         (: $prf (Inheritance Bird Flier) $tv))))
   ((STV 0.9999999166665949 0.0012502032753877429)))
