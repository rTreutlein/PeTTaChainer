!(import! &self ../../../repos/PLN/lib_pln.metta)

; Minimal libPLN base-rate deduction example.
; Run from pettachainer/metta with:
;   petta examples/simple_base_rate_deduction_libpln.metta
;
; Both results ask libPLN for the target inheritance via PLN.Query. The proof
; should be one application of libPLN's syllogistic deduction rule:
;   A -> B, B -> C |- A -> C
;
; The baseline is told the true base rates A=0.5, B=0.6, C=0.7. The unknown
; case uses libPLN's fixed uniform prior A=B=C=1/N=1/3 instead.
; The final case gives libPLN sample-level A/C observations and asks whether
; its induction rule can derive A -> C through a different proof path. Its
; fixed node prior is 1/12: A_sample, C_sample, and sample1..sample10.

(= (STV A_true) (stv 0.5 0.9))
(= (STV B_true) (stv 0.6 0.9))
(= (STV C_true) (stv 0.7 0.9))

(= (true-kb)
   ((Sentence ((Inheritance A_true B_true) (stv 0.25 0.9)) (trueAB))
    (Sentence ((Inheritance B_true C_true) (stv 0.5 0.9)) (trueBC))))

(= (true-base-rate-result)
   (PLN.Query (true-kb) (Inheritance A_true C_true) 20 20 100))

!(true-base-rate-result)

!(test
   (true-base-rate-result)
   ((stv 0.8749999999999999 0.9) (trueAB trueBC)))


(= (STV A_prior) (stv (/ 1.0 3.0) 0.9))
(= (STV B_prior) (stv (/ 1.0 3.0) 0.9))
(= (STV C_prior) (stv (/ 1.0 3.0) 0.9))

(= (uniform-prior-kb)
   ((Sentence ((Inheritance A_prior B_prior) (stv 0.25 0.9)) (priorAB))
    (Sentence ((Inheritance B_prior C_prior) (stv 0.5 0.9)) (priorBC))))

(= (uniform-prior-result)
   (PLN.Query (uniform-prior-kb) (Inheritance A_prior C_prior) 20 20 100))

!(uniform-prior-result)

!(test
   (uniform-prior-result)
   ((stv 0.3125 0.9) (priorAB priorBC)))


(= (SampleInductionPrior) (stv (/ 1.0 12.0) 0.9))
(= (STV A_sample) (SampleInductionPrior))
(= (STV C_sample) (SampleInductionPrior))
(= (STV sample1) (SampleInductionPrior))
(= (STV sample2) (SampleInductionPrior))
(= (STV sample3) (SampleInductionPrior))
(= (STV sample4) (SampleInductionPrior))
(= (STV sample5) (SampleInductionPrior))
(= (STV sample6) (SampleInductionPrior))
(= (STV sample7) (SampleInductionPrior))
(= (STV sample8) (SampleInductionPrior))
(= (STV sample9) (SampleInductionPrior))
(= (STV sample10) (SampleInductionPrior))

(= (sample-induction-kb)
   ((Sentence ((Inheritance sample1 A_sample) (stv 1.0 1.0)) (sample1A))
    (Sentence ((Inheritance sample2 A_sample) (stv 1.0 1.0)) (sample2A))
    (Sentence ((Inheritance sample3 A_sample) (stv 1.0 1.0)) (sample3A))
    (Sentence ((Inheritance sample4 A_sample) (stv 1.0 1.0)) (sample4A))
    (Sentence ((Inheritance sample5 A_sample) (stv 1.0 1.0)) (sample5A))
    (Sentence ((Inheritance sample6 A_sample) (stv 0.0 1.0)) (sample6NotA))
    (Sentence ((Inheritance sample7 A_sample) (stv 0.0 1.0)) (sample7NotA))
    (Sentence ((Inheritance sample8 A_sample) (stv 0.0 1.0)) (sample8NotA))
    (Sentence ((Inheritance sample9 A_sample) (stv 0.0 1.0)) (sample9NotA))
    (Sentence ((Inheritance sample10 A_sample) (stv 0.0 1.0)) (sample10NotA))

    (Sentence ((Inheritance sample1 C_sample) (stv 1.0 1.0)) (sample1C))
    (Sentence ((Inheritance sample2 C_sample) (stv 1.0 1.0)) (sample2C))
    (Sentence ((Inheritance sample3 C_sample) (stv 1.0 1.0)) (sample3C))
    (Sentence ((Inheritance sample4 C_sample) (stv 1.0 1.0)) (sample4C))
    (Sentence ((Inheritance sample5 C_sample) (stv 1.0 1.0)) (sample5C))
    (Sentence ((Inheritance sample6 C_sample) (stv 1.0 1.0)) (sample6C))
    (Sentence ((Inheritance sample7 C_sample) (stv 1.0 1.0)) (sample7C))
    (Sentence ((Inheritance sample8 C_sample) (stv 0.0 1.0)) (sample8NotC))
    (Sentence ((Inheritance sample9 C_sample) (stv 0.0 1.0)) (sample9NotC))
    (Sentence ((Inheritance sample10 C_sample) (stv 0.0 1.0)) (sample10NotC))))

(= (sample-induction-result)
   (PLN.Query (sample-induction-kb) (Inheritance A_sample C_sample) 300 200 1000))

!(sample-induction-result)

!(test
   (sample-induction-result)
   ((stv 0.08332764155453862 0.54)
    (sample6C sample6NotA sample8NotA sample8NotC sample9NotA sample9NotC)))

; Longer induction search note:
; Changing the sample induction query above from 300 steps to:
;   (PLN.Query (sample-induction-kb) (Inheritance A_sample C_sample) 3000 2000 1000)
; starts aggregating the evidence, but only after a much larger search. The
; observed result was:
;   ((stv 0.6363636363636365 0.8544303797468354)
;    (sample10NotA sample10NotC sample1A sample1C sample2A sample2C sample3A
;     sample3C sample9NotA sample9NotC))
