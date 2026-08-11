!(import! &self (library lib_builtin_types))

(: KB (Newtype Expression))
(: KBContext (Newtype (KB Expression Expression)))
(: Proof (Newtype Expression))
(: Statement (Newtype Expression))
(: TV (Alias Atom))

(: Goal Type)
(: : (-[det]-> KBContext Proof Statement TV Goal))

;; Both parameters are typed, but their field types are lost when the case
;; scrutinee is constructed from them as a positional pair.
(: nested-kbid (-[det]-> (List Goal) Goal KB))
(= (nested-kbid $premises $conclusion)
   (case ($premises $conclusion) (
      ((((: ($kbid $_ctx $_vars) $_proof $_type $_tv))
        (: ($kbid $_ctx2 $_vars2) $_proof2 $_type2 $_tv2))
         $kbid))))
