;; The indexes that find &kb facts by statement, read by modules loaded before
;; the knowledge store that writes them.

;; The stored facts that unify with a statement pattern: through the longest
;; ground prefix of the pattern when it has one, otherwise through &kb.
(: kb-facts (-[det]-> Statement KBContext (List (Statement KBContext Proof TV))))
(= (kb-facts $type $kbctx)
   (case (kb-fact-prefix-hashes $type) (
      (() (collapse (match &kb ($type $kbctx $proof $tv) (data $type $kbctx $proof $tv))))
      ((cons $hash $_shorter)
         (let $shorter (kb-fact-open-probes $type)
            (append-flat
               (collapse (match &kb_prefix ($hash $type $kbctx $proof $tv) (data $type $kbctx $proof $tv)))
               (collapse (let $open (superpose $shorter)
                  (match &kb_open ($open $type $kbctx $proof $tv) (data $type $kbctx $proof $tv))))))))))

;; Whether a fact is stored, read through its own index row: a ground fact's
;; longest prefix is its open hash too.
(: kb-fact-present? (-[det]-> (Statement KBContext Proof TV) Bool))
(= (kb-fact-present? ($type $kbctx $proof $tv))
   (let $hash (kb-fact-open-hash $type)
      (if (== (extract-vars $type) ())
         (if (== (kb-fact-prefix-hashes $type) ())
            (space-row-present? &kb ($type $kbctx $proof $tv))
            (space-row-present? &kb_prefix ($hash $type $kbctx $proof $tv)))
         (space-row-present? &kb_open ($hash $type $kbctx $proof $tv)))))
