!(import! &self ../../pettachainer/metta/petta_chainer)

;; A class link (Bird -> Flier inferred from their members) is the instance
;; fold of the implication between the two classes. It must merge to one
;; result.

!(compileadd inheritanceQueryKb (: i1 (Member a Bird) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i2 (Member a Flier) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i3 (Member b Bird) (STV 1.0 0.9)))
!(compileadd inheritanceQueryKb (: i4 (Member b Flier) (STV 1.0 0.9)))

(= (inheritance-query-result-tv (: $_proof $_type $tv)) $tv)

!(test (length (collapse (query 80 inheritanceQueryKb
   (: $prf (Inheritance Bird Flier) $tv)))) 1)
!(test (map-flat inheritance-query-result-tv
      (collapse (query 80 inheritanceQueryKb
         (: $prf (Inheritance Bird Flier) $tv))))
   ((STV 1.0 0.0020209076619844817)))
