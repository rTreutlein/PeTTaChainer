!(import! &self ../../pettachainer/metta/petta_chainer)

;; An existing incident assessment remains usable while higher-confidence
;; rules are explored. Historical base rates describe statement probabilities;
;; they do not determine whether this incident has a proof. In particular,
;; missing premises do not become provable because their cached rates are high.
;; Telemetry supplies the only additional proof in this fixture.

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

;; The telemetry proof refines the incumbent regardless of the cached
;; population rates. Its premise is a stored fact, which reaches the waiting
;; rule without an expansion, so even a tight budget finds it.
!(test
   (query 2 incidentPolicyKb (: $proof (ServiceAtRisk incident42) $tv))
   (:
      (factored-revision
         (by telemetryAssessment correlatedTelemetry)
         (prior (STV 1.0 0.95))
         (((reported with cpu (prior (STV 0.5 0.0))) existingAssessment)))
      (ServiceAtRisk incident42)
      (STV 1.0 0.7)))

!(test
   (query 20 incidentPolicyKb (: $proof (ServiceAtRisk incident42) $tv))
   (:
      (factored-revision
         (by telemetryAssessment correlatedTelemetry)
         (prior (STV 1.0 0.95))
         (((reported with cpu (prior (STV 0.5 0.0))) existingAssessment)))
      (ServiceAtRisk incident42)
      (STV 1.0 0.7)))
