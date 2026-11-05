


(: revision-merge-tv (-[det]-> TV TV TV))
(= (revision-merge-tv $tv1 $tv2)
   (case $tv1
      (((STV $m1 $c1)
          (case $tv2
             (((STV $m2 $c2) (merge-stv-fields $m1 $c1 $m2 $c2))
              ;; A plain proof of a conditional is its positive branch; the
              ;; conditional proof supplies the negative branch.
              ((CTV (STV $pm2 $pc2) $neg2) (CTV (merge-stv-fields $m1 $c1 $pm2 $pc2) $neg2))
              ($_other-tv $tv1))))
       ;; Two conditional proofs revise branch by branch.
       ((CTV (STV $pm1 $pc1) (STV $nm1 $nc1))
          (case $tv2
             (((CTV (STV $pm2 $pc2) (STV $nm2 $nc2))
                 (CTV (merge-stv-fields $pm1 $pc1 $pm2 $pc2)
                    (merge-stv-fields $nm1 $nc1 $nm2 $nc2)))
              ((STV $m2 $c2) (CTV (merge-stv-fields $pm1 $pc1 $m2 $c2) (STV $nm1 $nc1)))
              ($_other-tv $tv1))))
       ($_other $tv1))))

;; Points have no finite count. A point revised with finite evidence stays as
;; it is, the finite view dropped, so a merge of points holds points only; each
;; weighs alike, and any order of revising them gives their mean.
(: revision-views (-[det]-> Proof Number))
(= (revision-views $proof)
   (case $proof (((merge/revision $left $right) (+ (revision-views (brand Proof $left)) (revision-views (brand Proof $right)))) ($_view 1))))

;; A point's strength, -1 for any other value.
(: point-strength (-[det]-> TV Number))
(= (point-strength $tv) (case $tv (((STV $s $c) (if (>= $c 1.0) $s -1.0)) ($_other -1.0))))

;; The more confident proof is printed first; the value does not depend on it.
(= (RevisionMergeProof ($type $kb $prf-a $tv-a) ($type-b $kb-b $prf-b $tv-b))
   (let* (($a (assemble-runtime-fact $type $kb $prf-a $tv-a)) ($b (assemble-runtime-fact $type-b $kb-b $prf-b $tv-b))
          ($sa (point-strength $tv-a)) ($sb (point-strength $tv-b)))
      (if (if (>= $sa 0.0) (>= $sb 0.0) false)
         (let* (($na (revision-views $prf-a)) ($nb (revision-views $prf-b)))
            (assemble-runtime-fact $type $kb (brand Proof (merge/revision $prf-a $prf-b))
               (STV (/ (+ (* $sa $na) (* $sb $nb)) (+ $na $nb)) 1.0)))
         (if (>= $sa 0.0) $a
            (if (>= $sb 0.0) $b
               (if (>= (term-confidence $a) (term-confidence $b))
                  (assemble-runtime-fact $type $kb (brand Proof (merge/revision $prf-a $prf-b)) (revision-merge-tv $tv-a $tv-b))
                  (assemble-runtime-fact $type $kb (brand Proof (merge/revision $prf-b $prf-a)) (revision-merge-tv $tv-b $tv-a))))))))
