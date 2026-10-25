!(import! &self ../../pettachainer/metta/petta_chainer)

;; A forward join starts from a taken key only where its premise, as the join
;; reads it, reads that key (#142). A compound root's producer reads an
;; implication part with an STV, which is the implication's judgment. An
;; Assuming context seeds its assumed rule at the rule's plain key and starts
;; forward joins from that seed; the producer must not take the seed, or the
;; assumed rule would give its own judgment a value (#127).
!(compileadd seedStartKb (: hb (AlwaysPlayedTennis Bob) (STV 0.9 0.8)))
!(test (collapse (query 2000 seedStartKb (: $p
   (Assuming (: bridge (Implication (AlwaysPlayedTennis Bob) (PlayingTennisNow Bob)) (STV 0.12 0.2))
      (And (Implication (AlwaysPlayedTennis Bob) (PlayingTennisNow Bob)) (PlayingTennisNow Bob))) $tv)))
   ())
;; The assumed rule still applies as a rule of its query's world.
!(test (let (: $_proof $_type $tv) (query 2000 seedStartKb (: $p
   (Assuming (: bridge (Implication (AlwaysPlayedTennis Bob) (PlayingTennisNow Bob)) (STV 0.12 0.2))
      (PlayingTennisNow Bob)) $tv)) $tv)
   (STV 0.15799999999999997 0.052471596029189604))
