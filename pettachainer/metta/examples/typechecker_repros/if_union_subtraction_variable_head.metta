!(import! &self (library lib_builtin_types))

(: KB (Newtype Expression))
(: KBContext (Newtype (KB Expression Expression)))

(: CpuGoal Type)
(: CPU (-[det]-> Atom Expression Atom CpuGoal))
(: FactRow (Alias (Atom KBContext Atom Atom)))
(: WorkItem (Alias (| CpuGoal FactRow)))

;; The first literal CPU pattern subtracts CpuGoal in the else branch. The
;; remaining singleton member is FactRow, but its variable-headed pattern does
;; not receive the row's positional field types.
(: item-kbid (-[det]-> WorkItem KB))
(= (item-kbid $item)
   (if (= $item (CPU $_fun $_args $_result))
      (brand KB cpu)
      (if (= $item ($_type ($kbid $_ctx $_vars) $_proof $_tv))
         $kbid
         (brand KB missing))))
