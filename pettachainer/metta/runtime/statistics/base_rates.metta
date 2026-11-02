;; Shared base-rate cache reads.
;; Base-rate cache operations are shared by forward chaining and the compiled
;; query runtime, so they must be available before either consumer is loaded.

;; A KB may read each computed base rate as a Beta estimate: its n
;; observations plus k pseudo-observations of complete ignorance at 0.5, so a
;; rate over few observations is uncertain in its strength as well as its
;; confidence. The confidence n/(n+k) is unchanged, and n is recovered from it.
;; Opt-in per KB, set before adding knowledge; user base rates are kept as set.
(: set-base-rate-smoothing (-[det]-> KB Bool Bool))
(= (set-base-rate-smoothing $kb $enabled)
   (let* (($_old (remove-data-rows! &base_rate_smoothing (quote ($kb $_stored))))
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
