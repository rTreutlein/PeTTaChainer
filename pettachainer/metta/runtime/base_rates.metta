;; Shared base-rate caches and finalizers.
;; Base-rate cache operations are shared by forward chaining and the compiled
;; query runtime, so they must be available before either consumer is loaded.
(: base-rate-finish? (-[det]-> $finish Bool))
(= (base-rate-finish? $finish) (== $finish base-rate))

;; A KB may read each computed base rate as a Beta estimate: its n
;; observations plus k pseudo-observations of complete ignorance at 0.5, so a
;; rate over few observations is uncertain in its strength as well as its
;; confidence. The confidence n/(n+k) is unchanged, and n is recovered from it.
;; Opt-in per KB, set before adding knowledge; user base rates are kept as set.
(: set-base-rate-smoothing (-[det]-> KB Bool Bool))
(= (set-base-rate-smoothing $kb $enabled)
   (let* (($_old
             (collapse (match &base_rate_smoothing ($kb $stored)
                (remove-atom &base_rate_smoothing ($kb $stored)))))
          ($_new (add-atom &base_rate_smoothing ($kb $enabled))))
      $enabled))

(: smoothed-base-rate-tv (-[det]-> KB Atom Atom))
(= (smoothed-base-rate-tv $kb $tv)
   (case $tv (
      ((STV $s $c)
         (if (not (space-row-present? &base_rate_smoothing (quote ($kb true)))) $tv
            (let* (($n (confidence-to-count $c)) ($k (evidence-confidence-k)))
               (STV (/ (+ (* $s $n) (* 0.5 $k)) (+ $n $k)) $c))))
      ($_other $tv))))

(datatype BaseRateAggregateKey (base-rate-aggregate-key-value KB Statement $mode))
(datatype NoBaseRateAggregateKey no-base-rate-aggregate-key)

(: base-rate-aggregate-key (-[det]-> $arguments (| BaseRateAggregateKey NoBaseRateAggregateKey)))
(= (base-rate-aggregate-key $args)
   (case $args (
      (($kbid $pattern $_extractor $_init $_fun $finish $_tv-mode)
         (if (base-rate-finish? $finish)
            (base-rate-aggregate-key-value (brand KB $kbid) (brand Statement $pattern) $finish)
            no-base-rate-aggregate-key))
      ($_other no-base-rate-aggregate-key))))

;; Cache rows lead with a hash of the knowledge base and pattern, so a lookup
;; reads only that pattern's entries; the alpha comparison rejects collisions.
(: base-rate-cache-hash (-[det]-> KB Statement Number))
(= (base-rate-cache-hash $kbid $pattern) (index-hash (quote ($kbid $pattern))))

(: base-rate-cache-entries (-[det]-> KB Statement (List BaseRateEntry)))
(= (base-rate-cache-entries $kbid $pattern)
   (let $hash (base-rate-cache-hash $kbid $pattern)
      (collapse
         (match &ctx_base_rate_cache ($hash (base-rate $kbid $stored $tv $source $mode))
            (if (=alpha $stored $pattern) (base-rate $kbid $stored $tv $source $mode) (empty))))))

;; Binding the hash in a let around this match makes the checker lose the
;; entries' determinism at foreach-flat callers, so it is passed in.
(: base-rate-cache-mode-rows (-[det]-> Number KB Statement $mode (List BaseRateEntry)))
(= (base-rate-cache-mode-rows $hash $kbid $pattern $mode)
   (collapse
      (match &ctx_base_rate_cache ($hash (base-rate $kbid $stored $tv $source $emode))
         (if (and (=alpha $stored $pattern) (or (== $emode any) (== $emode $mode)))
            (base-rate $kbid $stored $tv $source $emode)
            (empty)))))

(: base-rate-cache-entries-for-mode (-[det]-> KB Statement $mode (List BaseRateEntry)))
(= (base-rate-cache-entries-for-mode $kbid $pattern $mode)
   (base-rate-cache-mode-rows (base-rate-cache-hash $kbid $pattern) $kbid $pattern $mode))

(: base-rate-entry-tv (-[det]-> BaseRateEntry TV))
(= (base-rate-entry-tv (base-rate $_kbid $_stored $tv $_source $_mode)) $tv)

(: base-rate-entry-user? (-[det]-> BaseRateEntry Bool))
(= (base-rate-entry-user? (base-rate $_kbid $_stored $_tv $source $_mode)) (== $source user))

(: cached-base-rate (-[nondet]-> KB Statement (List TV)))
(= (cached-base-rate $kbid $pattern)
   (case (base-rate-cache-entries $kbid (brand Statement (member-canon $pattern))) (
      (() ())
      ((cons $entry $_rest) (cons (base-rate-entry-tv $entry) ())))))

;; The keys reading a pattern's cache entries through a fold, in any mode,
;; recompute when one changes.
(: base-rate-readers-changed! (-[det]-> KB Statement (List $none)))
(= (base-rate-readers-changed! $kbid $pattern)
   (let* (($hash (base-rate-cache-hash $kbid $pattern))
          ($_dirty (collapse (match &ctx_sk_rate_readers ($hash $key) (sk-dirty! $key)))))
      ()))
