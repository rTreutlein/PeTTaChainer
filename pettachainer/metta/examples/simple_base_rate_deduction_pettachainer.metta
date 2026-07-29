!(import! &self ../petta_chainer)

; Minimal PeTTaChainer counterpart to simple_base_rate_deduction_libpln.metta.
; Run from pettachainer/metta with:
;   petta examples/simple_base_rate_deduction_pettachainer.metta
;
; Both cases use the same two inheritance links:
;   A -> B, B -> C
;
; The baseline supplies the true base rates A=0.5, B=0.6, C=0.7 with
; set-base-rate. The estimated case withholds all three values and gives
; PeTTaChainer observations instead: five positive A examples, six positive B
; examples, and seven positive C examples out of the same ten samples.

!(set-base-rate trueDeductionKb (Inheritance $x A_true) (STV 0.5 0.9))
!(set-base-rate trueDeductionKb (Inheritance $x B_true) (STV 0.6 0.9))
!(set-base-rate trueDeductionKb (Inheritance $x C_true) (STV 0.7 0.9))
!(compileadd trueDeductionKb (: trueAB (Inheritance A_true B_true) (STV 0.25 0.9)))
!(compileadd trueDeductionKb (: trueBC (Inheritance B_true C_true) (STV 0.5 0.9)))

(= (true-base-rate-result)
   (let (: $_prf (Inheritance A_true C_true) $tv)
      (query 30 trueDeductionKb (: $_prf (Inheritance A_true C_true) $tv))
      $tv))

!(true-base-rate-result)

!(test
   (true-base-rate-result)
   (STV 0.8749999999999999 0.9402804037609759))

!(compileadd estimatedDeductionKb (: estAB (Inheritance A_est B_est) (STV 0.25 0.9)))
!(compileadd estimatedDeductionKb (: estBC (Inheritance B_est C_est) (STV 0.5 0.9)))
!(set-universe-size estimatedDeductionKb 10.0)

!(compileadd estimatedDeductionKb (: aObs1 (Inheritance sample1 A_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs2 (Inheritance sample2 A_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs3 (Inheritance sample3 A_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs4 (Inheritance sample4 A_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs5 (Inheritance sample5 A_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs6 (Inheritance sample6 A_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs7 (Inheritance sample7 A_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs8 (Inheritance sample8 A_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs9 (Inheritance sample9 A_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: aObs10 (Inheritance sample10 A_est) (STV 0.0 1.0)))

!(compileadd estimatedDeductionKb (: bObs1 (Inheritance sample1 B_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs2 (Inheritance sample2 B_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs3 (Inheritance sample3 B_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs4 (Inheritance sample4 B_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs5 (Inheritance sample5 B_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs6 (Inheritance sample6 B_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs7 (Inheritance sample7 B_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs8 (Inheritance sample8 B_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs9 (Inheritance sample9 B_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: bObs10 (Inheritance sample10 B_est) (STV 0.0 1.0)))

!(compileadd estimatedDeductionKb (: cObs1 (Inheritance sample1 C_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs2 (Inheritance sample2 C_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs3 (Inheritance sample3 C_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs4 (Inheritance sample4 C_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs5 (Inheritance sample5 C_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs6 (Inheritance sample6 C_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs7 (Inheritance sample7 C_est) (STV 1.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs8 (Inheritance sample8 C_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs9 (Inheritance sample9 C_est) (STV 0.0 1.0)))
!(compileadd estimatedDeductionKb (: cObs10 (Inheritance sample10 C_est) (STV 0.0 1.0)))

(= (estimated-base-rate-result)
   (let (: $_prf (Inheritance A_est C_est) $tv)
      (query 120 estimatedDeductionKb (: $_prf (Inheritance A_est C_est) $tv))
      $tv))

!(estimated-base-rate-result)

(= (estimated-a-base-rate)
   (let $cached (cached-base-rate estimatedDeductionKb (Inheritance $x A_est))
      (if (== $cached ()) no-a-cache (car-atom $cached))))

(= (estimated-b-base-rate)
   (let $cached (cached-base-rate estimatedDeductionKb (Inheritance $x B_est))
      (if (== $cached ()) no-b-cache (car-atom $cached))))

(= (estimated-c-base-rate)
   (let $cached (cached-base-rate estimatedDeductionKb (Inheritance $x C_est))
      (if (== $cached ()) no-c-cache (car-atom $cached))))

!(estimated-a-base-rate)
!(estimated-b-base-rate)
!(estimated-c-base-rate)

!(test
   (estimated-base-rate-result)
   ((STV 0.8208439229200666 0.10108588167941372)
    (STV 0.8208353585996351 0.10107910528357877)))

!(test
   (estimated-a-base-rate)
   (STV 0.4999961923381537 0.100000810000081))

!(test
   (estimated-b-base-rate)
   (STV 0.5710968778963581 0.10900079388108652))

!(test
   (estimated-c-base-rate)
   (STV 0.6834812803311957 0.10900079388108652))
