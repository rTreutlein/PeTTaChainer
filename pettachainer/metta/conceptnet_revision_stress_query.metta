;; ConceptNet execution stress benchmark.
;;
;; In addition to the full exported ConceptNet rule base, this workload adds
;; several independent proofs for both sides of the target conjunction. The
;; backward chainer must explore competing implication paths, reject missing
;; premise paths, revise compatible evidence, and form the final conjunction.
;; Compile/import time remains outside the measured interval.
;; Run through benchmarks/run_conceptnet_revision_stress.sh: the runner stages
;; the external ConceptNet export and enables PeTTaChainer's strict-det arrow
;; semantics.
!(import! &self petta_chainer)
!(import! &self (library lib_import))
!(static-import! &self .conceptnet_export/rules_dump)

(: current-time (-> Number))

!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: max_dog (Dog max) (STV 1.0 1.0)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: ann_dog (Dog ann) (STV 1.0 1.0)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: i_have_max (Have (i max)) (STV 1.0 1.0)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: i_have_ann (Have (i ann)) (STV 1.0 1.0)))

;; Six additional, independent paths to Pet(max).
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_signal_1 (PetSignal1 max) (STV 1.0 0.90)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_signal_2 (PetSignal2 max) (STV 1.0 0.85)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_signal_3 (PetSignal3 max) (STV 1.0 0.80)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_signal_4 (PetSignal4 max) (STV 1.0 0.75)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_signal_5 (PetSignal5 max) (STV 1.0 0.70)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_signal_6 (PetSignal6 max) (STV 1.0 0.65)))

!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_path_1
      (Implication (Premises (PetSignal1 $x)) (Conclusions (Pet $x)))
      (CTV (STV 0.90 0.90) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_path_2
      (Implication (Premises (PetSignal2 $x)) (Conclusions (Pet $x)))
      (CTV (STV 0.85 0.90) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_path_3
      (Implication (Premises (PetSignal3 $x)) (Conclusions (Pet $x)))
      (CTV (STV 0.80 0.90) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_path_4
      (Implication (Premises (PetSignal4 $x)) (Conclusions (Pet $x)))
      (CTV (STV 0.75 0.90) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_path_5
      (Implication (Premises (PetSignal5 $x)) (Conclusions (Pet $x)))
      (CTV (STV 0.70 0.90) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: pet_path_6
      (Implication (Premises (PetSignal6 $x)) (Conclusions (Pet $x)))
      (CTV (STV 0.65 0.90) (STV 0.0 1.0))))

;; Four independent paths to Own(i,max).
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: own_signal_1 (OwnSignal1 max) (STV 1.0 0.90)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: own_signal_2 (OwnSignal2 max) (STV 1.0 0.80)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: own_signal_3 (OwnSignal3 max) (STV 1.0 0.70)))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: own_signal_4 (OwnSignal4 max) (STV 1.0 0.60)))

!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: own_path_1
      (Implication (Premises (OwnSignal1 $x)) (Conclusions (Own (i $x))))
      (CTV (STV 0.90 0.90) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: own_path_2
      (Implication (Premises (OwnSignal2 $x)) (Conclusions (Own (i $x))))
      (CTV (STV 0.80 0.90) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: own_path_3
      (Implication (Premises (OwnSignal3 $x)) (Conclusions (Own (i $x))))
      (CTV (STV 0.70 0.90) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: own_path_4
      (Implication (Premises (OwnSignal4 $x)) (Conclusions (Own (i $x))))
      (CTV (STV 0.60 0.90) (STV 0.0 1.0))))

;; Competing paths whose premises are deliberately absent. They force search
;; expansion but cannot contribute evidence to the result.
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: missing_pet_1 (Implication (Premises (MissingPet1 $x)) (Conclusions (Pet $x))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: missing_pet_2 (Implication (Premises (MissingPet2 $x)) (Conclusions (Pet $x))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: missing_pet_3 (Implication (Premises (MissingPet3 $x)) (Conclusions (Pet $x))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: missing_pet_4 (Implication (Premises (MissingPet4 $x)) (Conclusions (Pet $x))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: missing_own_1 (Implication (Premises (MissingOwn1 $x)) (Conclusions (Own (i $x)))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: missing_own_2 (Implication (Premises (MissingOwn2 $x)) (Conclusions (Own (i $x)))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: missing_own_3 (Implication (Premises (MissingOwn3 $x)) (Conclusions (Own (i $x)))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))
!(compileadd kb5b10000f8f9f4f0dbd120f99aa0f43ce
   (: missing_own_4 (Implication (Premises (MissingOwn4 $x)) (Conclusions (Own (i $x)))) (CTV (STV 1.0 0.9) (STV 0.0 1.0))))

!(let*
   (($start (current-time))
    ($results
       (collapse
          (query 100 kb5b10000f8f9f4f0dbd120f99aa0f43ce
             (: $_proof (And (Own (i max)) (Pet max)) $_tv))))
    ($finish (current-time)))
   (println!
      (CONCEPTNET_OWN_PET_RESULT_COUNT
         (length $results)
         RESULTS
         $results
         SECONDS
         (- $finish $start))))
