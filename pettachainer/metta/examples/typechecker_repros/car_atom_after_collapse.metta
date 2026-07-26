!(import! &self (library lib_spaces))

!(bind! &config (new-space))

(: Choice Type)
(: default-choice Choice)

(: ChoiceRow Type)
(: choice-row (-> Choice ChoiceRow))

(: selected-choice (-> Choice))
(= (selected-choice)
   (let $matches
      (collapse
         (match &config (choice-row $choice) $choice))
      (if (== $matches ())
         default-choice
         (car-atom $matches))))
