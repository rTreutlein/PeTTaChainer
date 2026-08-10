!(import! &self ../petta_chainer)

;; Compare three refinement schedulers on the same incident-response problem.
;; Run from pettachainer/metta with:
;;   petta examples/refinement_base_rate_policies.metta
;;
;; An existing incident assessment is immediately usable. Three independent
;; rules could improve it:
;;
;;   1. a theoretically decisive but historically rare packet signature;
;;   2. an almost-certain-on-paper sensor alert whose 0.99 rate is based on
;;      very weak evidence;
;;   3. a slightly weaker telemetry correlation with a well-supported 0.75
;;      population rate and an actual fact for this incident.
;;
;; The first two premises deliberately have no proof for incident42. Their
;; preloaded cache entries stand in for rates learned from historical incidents;
;; they are estimates, not asserted facts. The useful rate is generalized
;; across incidents, exercising option 2's pattern lookup.

!(compileadd incidentPolicyKb
   (: existingAssessment
      (ServiceAtRisk incident42)
      (STV 1.0 0.7)))
!(compileadd incidentPolicyKb
   (: correlatedTelemetry
      (CorrelatedTelemetry incident42)
      (STV 1.0 1.0)))

!(compileadd incidentPolicyKb
   (: rareSignatureAssessment
      (Implication
         (RarePacketSignature incident42)
         (ServiceAtRisk incident42))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))
!(compileadd incidentPolicyKb
   (: weakSensorAssessment
      (Implication
         (WeaklySampledSensor incident42)
         (ServiceAtRisk incident42))
      (CTV (STV 1.0 0.99) (STV 0.0 1.0))))
!(compileadd incidentPolicyKb
   (: telemetryAssessment
      (Implication
         (CorrelatedTelemetry incident42)
         (ServiceAtRisk incident42))
      (CTV (STV 1.0 0.95) (STV 0.0 1.0))))

!(set-base-rate incidentPolicyKb
   (RarePacketSignature incident42)
   (STV 0.05 0.9))
!(set-base-rate incidentPolicyKb
   (WeaklySampledSensor incident42)
   (STV 0.99 0.01))
!(set-base-rate incidentPolicyKb
   (CorrelatedTelemetry $incident)
   (STV 0.75 0.9))

;; At three expansions, the optimistic baseline spends its budget checking the
;; two locally most confident dead ends. Raw exact-key rates reject the rare
;; first branch and reach the useful proof. The smoothed/generalized policy has
;; already reached it with two expansions.
(= (incident-policy-run $mode $steps)
   (let* (($_mode (set-refinement-prior-mode $mode))
          ($result
             (query $steps incidentPolicyKb
                (: $proof (ServiceAtRisk incident42) $tv))))
      (policy $mode $steps $result)))

!(incident-policy-run optimistic 2)
!(incident-policy-run optimistic 3)
!(incident-policy-run direct-base-rate 2)
!(incident-policy-run direct-base-rate 3)
!(incident-policy-run smoothed-base-rate 2)
!(incident-policy-run smoothed-base-rate 3)

!(test
   (incident-policy-run optimistic 3)
   (policy optimistic 3
      (: existingAssessment
         (ServiceAtRisk incident42)
         (STV 1.0 0.7))))

!(test
   (incident-policy-run direct-base-rate 3)
   (policy direct-base-rate 3
      (: (merge/revision
            (by telemetryAssessment correlatedTelemetry)
            existingAssessment)
         (ServiceAtRisk incident42)
         (STV 1.0 0.9551515146764331))))

!(test
   (incident-policy-run smoothed-base-rate 2)
   (policy smoothed-base-rate 2
      (: (merge/revision
            (by telemetryAssessment correlatedTelemetry)
            existingAssessment)
         (ServiceAtRisk incident42)
         (STV 1.0 0.9551515146764331))))
