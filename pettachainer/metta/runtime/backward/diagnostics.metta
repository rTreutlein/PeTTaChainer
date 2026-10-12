;; Read-only observations of the skeleton the last query left, for
;; query_diagnostics.py. They read child links, waiting joins, stored facts,
;; cached merged values and the pending-work index; they never evaluate,
;; expand or start anything.

(: DiagnosticSearch Type)
;; roots, roots with search work left, deliveries still queued, steps left
(: search (-[det]-> (List SkPattern) Number Number Number DiagnosticSearch))
(: DiagnosticRoute Type)
;; rule, premise node, conclusion, conclusion proof, statements still to
;; prove, evidence of the premise keys already bound
(: continuation (-[det]-> Number SkPattern Statement Proof (List Statement) (List Evidence) DiagnosticRoute))
(: candidate (-[det]-> Number SkPattern Statement Proof (List Statement) (List Evidence) DiagnosticRoute))
(: DiagnosticNode Type)
;; expanded, work left, answers with a value, children, routes
(: node (-[det]-> Bool Bool Number (List SkPattern) (List DiagnosticRoute) DiagnosticNode))

;; Whether the search still has work at or below a node: it is unexpanded, or
;; the pending-work index holds work below it. A root never reached has no
;; entry in the index yet.
(: diagnostic-work? (-[det]-> Number SkPattern Bool))
(= (diagnostic-work? $hash $node)
   (if (sk-pending? $hash $node) true (if (sk-expanded? $hash $node) false (sk-root? $node))))

(: query-diagnostic-search (-[det]-> DiagnosticSearch))
(= (query-diagnostic-search)
   (search
      (collapse (match &sk_roots ($_rhash $root) $root))
      (length (collapse (match &sk_roots ($hash $pending) (if (diagnostic-work? $hash $pending) true (empty)))))
      (match-count &sk_answer_queue $_delivery)
      (max 0 (search-id-value sk_budget))))

;; The statements among a join's premises, by a fold over the list, which keeps
;; the variables they share; a collapse would rename them apart.
(: diagnostic-statement-step (-[det]-> SkPattern (List Statement) (List Statement)))
(= (diagnostic-statement-step $premise $statements)
   (case $premise (
      ((CPU $_fun $_args $_res) $statements)
      (($type $_kbctx $_proof $_tv) (cons $type $statements)))))

;; A node's routes are the joins waiting on its children, each child read
;; through its own hash. An expanded node no answer supports also lists every
;; rule concluding it, dormant and pruned rules included, as candidates: one
;; per statement premise, with all its statements still to prove.
(: query-diagnostic-node (-[det]-> SkPattern DiagnosticNode))
(= (query-diagnostic-node $node)
   (let* (($hash (sk-node-hash $node))
          ($expanded (sk-expanded? $hash $node))
          ($children (sk-children $hash $node))
          ($answers (sk-answers $node))
          ($supported
             (length (collapse
                (let $key (superpose $answers)
                   (let $khash (index-hash $key)
                      (if (== (collapse (once (match &sk_merged (sk-merged $khash $mkey $_deps (sk-val $_fact $_ev $_vdeps))
                                (if (=alpha $mkey $key) true (empty)))))
                             ())
                         (case $key (
                            ((sk-key $ktype $kkbctx)
                               (if (== (sk-leaf-facts $ktype $kkbctx sk-any-filter) ()) (empty) true))))
                         true))))))
          ($continuations
             (collapse
                (let (sk-node-at $chash $child) (superpose $children)
                   (match &sk_wait ($chash $stored (sk-partial $owner $rule ($ctype $_cctx $cproof $_ctv) $_done $remaining $keys))
                      (if (if (=alpha $owner $node) (=alpha $stored $child) false)
                         (continuation $rule $stored $ctype $cproof (foldr-flat diagnostic-statement-step () $remaining)
                            (collapse
                               (let* (((sk-key $btype $bkbctx) (superpose $keys))
                                      ($facts (sk-leaf-facts $btype $bkbctx sk-any-filter))
                                      ($fact (superpose $facts))
                                      ($entries (evidence-entries (leaf-evidence-for-result $fact))))
                                  (superpose $entries))))
                         (empty))))))
          ($candidates
             (collapse
                (if (if $expanded (== $supported 0) false)
                   (case (copy_term $node) (
                      ((CPU $_fun $_args $_res) (empty))
                      (($type $kbctx $proof $tv)
                         (let (sk-match $mrule $premises ($mtype $_mkbctx $mproof $_mtv))
                            (sk-rule-match (assemble-stored-runtime-fact $type $kbctx $proof $tv))
                            (let $premise (superpose $premises)
                               (case $premise (
                                  ((CPU $_pfun $_pargs $_pres) (empty))
                                  ($_open (candidate $mrule $premise $mtype $mproof (foldr-flat diagnostic-statement-step () $premises) ())))))))))
                   (empty)))))
      (node $expanded (diagnostic-work? $hash $node) $supported (collapse (let (sk-node-at $_h $linked) (superpose $children) $linked))
         (append-flat $continuations $candidates))))
