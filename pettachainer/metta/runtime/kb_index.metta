;; The indexes that find &kb facts by statement, read by modules loaded before
;; the knowledge store that writes them.

;; SWI indexes &kb by a statement's head only, so a lookup by head and
;; arguments walked every fact with that head, across the whole history. Each
;; fact is therefore also stored in &kb_prefix under the hash of every ground
;; prefix of its statement, including nested antecedent heads for implications
;; (kb-fact-prefix-hashes), and a fact whose statement
;; has variables in &kb_open under the hash of exactly its longest one
;; (kb-fact-open-hash), so a lookup reads only the open facts that share
;; one of its own prefixes (see kb-facts). The rows follow &kb's: added with the
;; same backend, removed with the fact.
(: &kb_prefix (SpaceOf (Number Statement KBContext Proof TV)))
!(bind! &kb_prefix (new-space))
(: &kb_open (SpaceOf (Number Statement KBContext Proof TV)))
!(bind! &kb_open (new-space))

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
