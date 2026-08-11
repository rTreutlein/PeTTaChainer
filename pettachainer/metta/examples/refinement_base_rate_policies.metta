!(import! &self ../petta_chainer)

;; Exercise cache-guided proof scheduling on an incident-response problem.
;; Run from pettachainer/metta with:
;;   petta examples/refinement_base_rate_policies.metta
;;
;; An existing incident assessment is immediately usable. Four independent
;; rules could improve it:
;;
;;   1. a theoretically decisive but historically rare packet signature;
;;   2. an almost-certain-on-paper sensor alert whose 0.99 rate is based on
;;      very weak evidence;
;;   3. a completely unknown novel indicator;
;;   4. a slightly weaker telemetry correlation with a well-supported 0.75
;;      population rate and an actual fact for this incident.
;;
;; The first three premises deliberately have no proof for incident42. The
;; preloaded cache entries stand in for rates learned from historical incidents;
;; they are estimates, not asserted facts. The useful rate is generalized
;; across incidents, exercising generalized pattern lookup.

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
!(compileadd incidentPolicyKb
   (: novelIndicatorAssessment
      (Implication
         (UnseenNovelIndicator incident42)
         (ServiceAtRisk incident42))
      (CTV (STV 1.0 1.0) (STV 0.0 1.0))))

!(set-base-rate incidentPolicyKb
   (RarePacketSignature incident42)
   (STV 0.05 0.9))
!(set-base-rate incidentPolicyKb
   (WeaklySampledSensor incident42)
   (STV 0.99 0.01))
!(set-base-rate incidentPolicyKb
   (CorrelatedTelemetry $incident)
   (STV 0.75 0.9))

;; The resulting factors are 0.675 for telemetry, 0.5 for the unknown
;; indicator, 0.045 for the rare signature, and 0.0099 for the weak sensor.
;; The useful proof therefore improves the incumbent on the second expansion.
(= (incident-policy-run $steps)
   (let $result
      (query $steps incidentPolicyKb
         (: $proof (ServiceAtRisk incident42) $tv))
      (policy base-rate-guided $steps $result)))

!(incident-policy-run 2)
!(incident-policy-run 3)

!(test
   (incident-policy-run 2)
   (policy base-rate-guided 2
      (: (merge/revision
            (by telemetryAssessment correlatedTelemetry)
            existingAssessment)
         (ServiceAtRisk incident42)
         (STV 1.0 0.9551515146764331))))
