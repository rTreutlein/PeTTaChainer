!(import! &self (library lib_builtin_types))

(: Proof (Newtype Expression))

(: Goal Type)
(: CPU (-[det]-> Atom Expression Atom Goal))
(: FactRow (Alias (Atom Atom Atom Atom)))
(: WorkItem (Alias (| Goal FactRow)))

;; Contextual branch construction works for closed data, but the fallthrough
;; value retains WorkItem and conflicts with the surrounding Proof brand even
;; though Proof's representation is the fully open Expression type.
(: proof-from-item (-[det]-> WorkItem Proof))
(= (proof-from-item $item)
   (brand Proof
      (case $item (
         ((CPU $_fun $_args $_result) cpu)
         ($_other $item)))))
