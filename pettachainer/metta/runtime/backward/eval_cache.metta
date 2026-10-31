
(: sk-cache-summary-reference!
   (-[semidet]-> Number SkeletonKey Number (List SkeletonGiven) (List Number) SkeletonFilter SkeletonValue Atom))
(= (sk-cache-summary-reference! $hash $key $rhash $given $exclude $filter $value)
   (collapse (once (match &sk_row
      ($hash $stored $rhash (sk-row $_id $_concl $premises $_seq))
      (if (=alpha $stored $key)
         (let $volatile (fold-flat
            (|-> ($seen $premise)
               (if $seen true
                  (case $premise (
                     ((CPU rule-likelihood-read $_likelihood-args $_likelihood-res) true)
                     ((CPU $_cpu-fun $_cpu-args $_cpu-res) false)
                     (($premise-type $_premise-scope $_premise-proof $_premise-tv)
                        (head-is? $premise-type RuleTruth))))))
            false $premises)
            (if $volatile ()
               (context-add! &sk_summary_reference ($hash $key $rhash $given $exclude $filter $value))))
         (empty))))))
