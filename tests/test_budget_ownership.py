"""The step budget owns every unit of work a query does (#175, #176, #177).

Each case runs in a fresh process under the issues' 3.5 GB address-space cap
and a deadline, and reports each query's time and the resident memory it
added (the peak is reset after the KB is loaded).
"""
import json
import re
import resource
import subprocess
import sys
import unittest

CAP_BYTES = 3_500_000 * 1024
DEADLINE = 180

SCRIPT = r"""
import json, sys, time
import janus_swi as janus
from pettachainer import PeTTaChainer

def rss_kb(field):
    for line in open('/proc/self/status'):
        if line.startswith(field):
            return int(line.split()[1])

h = PeTTaChainer()
case, atoms, positive, definitions, queries = sys.argv[1], *map(json.loads, sys.argv[2:])
for head in positive:
    h.set_positive_only_predicate(head)
for definition in definitions:
    h.handler.process_metta_string(definition)
if case.startswith('plant'):
    sys.path.insert(0, 'tests')
    from test_deep_conditioning import plant
    plant(h, int(case[5:]))
h.add_atoms_no_check(atoms)
# Count the computations a named user function runs once the row allowance is closed.
janus.query_once("nb_setval(closed_calls, 0), wrap_predicate('cpu-call'(_D,_F,_A,_O), closed_count, _W, "
                 "((_F == 'budget-grow', 'search-id-value'(sk_row_budget,_L), _L =< 0 -> "
                 "nb_getval(closed_calls,_N), _M is _N+1, nb_setval(closed_calls,_M) ; true), call(_W)))")
for query, steps in queries:
    with open('/proc/self/clear_refs', 'w') as refs:
        refs.write('5')
    before = rss_kb('VmRSS')
    start = time.monotonic()
    janus.query_once("nb_setval(closed_calls, 0)")
    if isinstance(query, list):
        out = {'answers': [[a.tv for a in group] for group in h.query_many_refs(query, steps=steps)]}
    elif query.startswith('forward '):
        pattern = query[len('forward '):]
        seed = h.select_facts([pattern]) if pattern else []
        out = {'answers': sorted(h.forward_chain(seed, steps=steps))}
    else:
        out = h.query_many_with_status([query], steps, timeout_sec=0)
        out['answers'] = out['answers'][0]
    unpaid = janus.query_once("findall(_S, (('&sk_deferred'(_,_,_D) ; '&sk_deferred_joins'(_,_,_D)), "
                              "term_size(_D,_S)), _Sizes), sum_list(_Sizes, Words)")['Words']
    out.update(seconds=time.monotonic() - start, added_mb=(rss_kb('VmHWM') - before) / 1024, unpaid_words=unpaid,
               closed_calls=janus.query_once("nb_getval(closed_calls, N)")['N'])
    print(json.dumps(out), flush=True)
"""

# 175: "Bob is older than Lamine?" over a scale lexicon whose comparison rules
# complete one another's antecedents.
I175_TEXT = [
    "(: s1 (Most old sk_lamine_1 glazier) (STV 1.0 0.99))",
    "(: s1m (Member sk_lamine_1 glazier) (STV 1.0 0.99))",
    "(: b1 (Member sk_bob_1 glazier) (STV 1.0 0.99))",
    "(: t1 (TimesAs tall sk_bob_1 sk_lamine_1 0.5) (STV 1.0 0.99))",
]
MOST_BOUNDS = ("(: most_bounds (Implication (And (Most $s $x $c) (Member $y $c)) (Not (More $s $y $x)))"
               " (CTV (STV 1.0 0.99) (STV 0.0 0.0)))")
I175_BACKGROUND = [
    "(: pole_short_tall (ScaleOpposite short tall) (STV 1.0 0.99))",
    "(: dimension_brightness_bright (DimensionScale brightness bright) (STV 1.0 0.99))",
    "(: month_class (Implication (Month $t $m) (Member $t $m)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    "(: more_trans (Implication (And (More $s $x $y) (More $s $y $z)) (More $s $x $z)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    "(: ratio_more_lt (Implication (And (TimesAs $s $x $y $f) (Compute < ($f 1) -> true)) (More $s $y $x)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    "(: pole_more (Implication (And (ScaleOpposite $a $b) (More $a $x $y)) (More $b $y $x)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    "(: dimension_more (Implication (And (More $d $x $y) (DimensionScale $d $s)) (More $s $x $y)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    "(: most_exceeds (Implication (And (Most $s $x $c) (Member $y $c) (Compute != ($x $y) -> true)) (More $s $x $y)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    "(: rank_orders (Implication (And (Ordinal $a $m $s $c) (Ordinal $b $n $s $c) (Compute < ($m $n) -> true) (Compute != ($s $c) -> true)) (More $s $a $b)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    "(: most_rank_one (Implication (Most $s $x $c) (Ordinal $x 1 $s $c)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    MOST_BOUNDS,
]
I175_QUERY = "(: $prf (More old sk_bob_1 sk_lamine_1) $tv)"
I175_CONTROL = "(: (negated (by most_bounds (conjunction s1 b1))) (More old sk_bob_1 sk_lamine_1) "

# 176: an open Past query, where coreference inverts into ever larger
# witnesses and a conjunction rule's projections read them back.
I176_RULES = [
    "(: coref_member (Implication (And (Coref $m $a) (Member $m $k)) (Member $a $k)) (CTV (STV 1.0 0.99) (STV 0.0 0.0)))",
    "(: theme_entailed_past (Implication (And (Entails $m) (Theme $m $c) (Past $m) (Compute clause-event ($c) -> $o)) (And $c (Past $o))) (CTV (STV 1.0 0.9) (STV 0.0 0.0)))",
]
I176_FACTS = [
    '(: n1_name (Name sk_odile_1 "Odile") (STV 1.0 0.99))',
    "(: x1_member (Member sk_hut_1 hut) (STV 1.0 0.99))",
    "(: e1_member (Member sk_manage_1 manage) (STV 1.0 0.99))",
    "(: e1_agent (Agent sk_manage_1 sk_odile_1) (STV 1.0 0.99))",
    "(: e1_theme (Theme sk_manage_1 (And (Member sk_open_1 open) (Agent sk_open_1 sk_odile_1) (Patient sk_open_1 sk_hut_1))) (STV 1.0 0.99))",
    "(: e1_entails (Entails sk_manage_1) (STV 1.0 0.99))",
    "(: e1_past (Past sk_manage_1) (STV 1.0 0.99))",
]
I176_QUERY = "(: $prf (Past $e) $tv)"

# 177: one packed event unpacked into its class and its theme.
def i177_atoms(fixed=False, confidence="0.99"):
    source = "(Bought $e $who $what)" if fixed else "(Bought $e $k $who $what)"
    fact = "(Bought sk_buy_1 sk_bob_1 sk_icecream_1)" if fixed else "(Bought sk_buy_1 buy sk_bob_1 sk_icecream_1)"
    return [f"(: unpack_class (Implication {source} (Member $e {'buy' if fixed else '$k'})) (STV 1.0 0.99))",
            f"(: unpack_theme (Implication {source} (Theme $e $what)) (STV 1.0 0.99))",
            f"(: s1 {fact} (STV 1.0 {confidence}))"]

I177_CLASS = "(: $prf (Member sk_buy_1 buy) $tv)"
I177_THEME = "(: $prf (Theme sk_buy_1 sk_icecream_1) $tv)"
I177_BOTH = "(: $prf (And (Member sk_buy_1 buy) (Theme sk_buy_1 sk_icecream_1)) $tv)"

PLANT8 = ["(: $p (Degraded plant t6) $tv)", "(: $p (Degraded plant t8) $tv)"]


def capped():
    resource.setrlimit(resource.RLIMIT_AS, (CAP_BYTES, CAP_BYTES))


def run(case, atoms, queries, positive=(), definitions=(), steps=None):
    """Each query at 400 steps, the one query at each of `steps`, or (query, steps) pairs."""
    plan = ([list(q) if isinstance(q, tuple) else [q, 400] for q in queries] if steps is None
            else [[queries[0], n] for n in steps])
    done = subprocess.run(
        [sys.executable, "-c", SCRIPT, case, json.dumps(atoms), json.dumps(list(positive)),
         json.dumps(list(definitions)), json.dumps(plan)],
        capture_output=True, text=True, timeout=DEADLINE, preexec_fn=capped)
    if done.returncode:
        raise AssertionError(f"{case} failed:\n{done.stderr[-3000:]}")
    return [json.loads(line) for line in done.stdout.splitlines() if line.startswith("{")]


def without_kb(answers):
    return [re.sub(r"kb[0-9a-f]{32}", "kb", answer) for answer in answers]


def tv(answer):
    return [float(x) for x in answer.rsplit("(STV ", 1)[1].rstrip(")").split()]


class BudgetOwnershipTests(unittest.TestCase):
    def assert_bounded(self, result, seconds, added_mb):
        self.assertLess(result["seconds"], seconds, result["seconds"])
        self.assertLess(result["added_mb"], added_mb, result["added_mb"])

    def test_completion_replays_are_paid_for(self):
        # #175 case 1: the completions' replays under their pins are paid by
        # claims. The answer's value awaits a decision on generalised bridge
        # priors (#175); only that one returns, within bounds, is checked.
        [result] = run("i175", I175_TEXT + I175_BACKGROUND, [I175_QUERY])
        self.assertEqual(len(result["answers"]), 1, result["answers"])
        self.assertIn("(More old sk_bob_1 sk_lamine_1)", result["answers"][0])
        self.assert_bounded(result, 30, 1024)

    def test_comparison_controls_keep_their_value(self):
        # #175 cases 2 and 3: only most_bounds, and every rule with positive-only heads.
        heads = ("More", "Most", "TimesAs", "ScaleOpposite", "DimensionScale", "Month", "Ordinal", "glazier")
        for name, atoms, positive in (("only-bounds", I175_TEXT + [MOST_BOUNDS], ()),
                                      ("positive-only", I175_TEXT + I175_BACKGROUND, heads)):
            with self.subTest(name):
                [result] = run(name, atoms, [I175_QUERY], positive=positive)
                [answer] = result["answers"]
                self.assertTrue(answer.startswith(I175_CONTROL), answer)
                strength, confidence = tv(answer)
                self.assertEqual(strength, 0.0)
                self.assertAlmostEqual(confidence, 0.9690040722935537, delta=1e-12)

    def test_open_root_generated_rows_spend_the_allowance(self):
        # #176: the open query finishes and keeps the stored Past fact, with the
        # missing Compute function, a defined one, and without Compute.
        no_compute = [I176_RULES[0], I176_RULES[1].replace(" (Compute clause-event ($c) -> $o)", "")
                      .replace("(Past $o)", "(Past $m)")]
        for name, rules, definitions in (("undefined", I176_RULES, ()),
                                         ("defined", I176_RULES, ("(= (clause-event $c) sk_open_1)",)),
                                         ("no-compute", no_compute, ())):
            with self.subTest(name):
                [result] = run(name, rules + I176_FACTS, [I176_QUERY], definitions=definitions)
                self.assertIn("(: e1_past (Past sk_manage_1) (STV 1.0 0.99))", result["answers"])
                self.assert_bounded(result, 15, 1024)

    def test_conjunction_conditioning_gets_its_turn(self):
        # #177 case 1, cold and after its two conjuncts were asked alone: the
        # conjunction is conditioned on the shared fact, as case 2 is.
        for name, queries in (("cold", [I177_BOTH]), ("after", [I177_CLASS, I177_THEME, I177_BOTH])):
            with self.subTest(name):
                results = run(name, i177_atoms(), queries)
                answers = results[-1]["answers"]
                self.assertEqual(len(answers), 1, answers)
                self.assertTrue(answers[0].startswith("(: (conditioned s1 "), answers[0])
                strength, confidence = tv(answers[0])
                self.assertEqual(strength, 1.0)
                self.assertAlmostEqual(confidence, 0.9739695489836424, delta=1e-12)
                for result in results:
                    self.assertLess(result["seconds"], 10, result["seconds"])

    def test_conjunction_controls_keep_their_value(self):
        [fixed] = run("fixed", i177_atoms(fixed=True), [I177_BOTH])
        self.assertEqual(len(fixed["answers"]), 1)
        self.assertTrue(fixed["answers"][0].startswith("(: (conditioned s1 "))
        self.assertAlmostEqual(tv(fixed["answers"][0])[1], 0.9739695489836424, delta=1e-12)
        [certain] = run("certain", i177_atoms(confidence="1.0"), [I177_BOTH])
        [answer] = certain["answers"]
        self.assertTrue(answer.startswith("(: (conjunction (by unpack_class s1) (by unpack_theme s1)) "), answer)
        self.assertEqual(tv(answer)[0], 1.0)
        self.assertAlmostEqual(tv(answer)[1], 0.9801977747248122, delta=1e-12)

    def test_an_unaffordable_row_waits_unpaid_and_is_built_later(self):
        # Rows whose stored size (each over 10,000 words) the allowance cannot
        # pay are refused whole, and what waits for them keeps none of that
        # payload, only the join to extend again; a later query with enough
        # budget builds and answers them all.
        facts = [f"(: p{i} (P (v{i} " + " ".join(["x"] * 10000) + ")) (STV 1 0.9))" for i in range(4)]
        rule = "(: (no_inverse r) (Implication (P $x) (Q $x)) (STV 1 0.9))"
        short, again, enough = run("payload", [rule] + facts, ["(: $p (Q $x) $tv)"], steps=(1, 1, 200))
        for waiting in (short, again):
            self.assertEqual(waiting["answers"], [])
            self.assertLess(waiting["unpaid_words"], 2000)
        self.assertEqual(len(enough["answers"]), 4)
        self.assertEqual(enough["unpaid_words"], 0)

    def test_applications_without_a_join_keep_no_unpaid_payload(self):
        # Eight rules whose only premise computes a 4,096-leaf term complete
        # without a fact join. At one step none can be paid; each waits as its
        # rule alone, not its row, and a later query builds them.
        grow = "(= (budget-grow $v) (if (== $v 0) x (let $b (budget-grow (- $v 1)) (t $b $b))))"
        rules = [f"(: (no_inverse r{i}) (Implication (Compute budget-grow (12) -> $x) (Q $x)) (STV 1 0.9))"
                 for i in range(8)]
        short, enough = run("compute", rules, ["(: $p (Q $x) $tv)"], definitions=(grow,), steps=(1, 200))
        self.assertEqual(short["answers"], [])
        self.assertLess(short["unpaid_words"], 1000)
        # No user computation runs once the allowance is closed, prefilter included.
        self.assertEqual(short["closed_calls"], 0)
        self.assertEqual(len(enough["answers"]), 1)
        # All eight applications, each 0.9 confident (nine observations), are in the answer.
        self.assertAlmostEqual(tv(enough["answers"][0])[1], 72 / 73, delta=1e-12)
        self.assertEqual(enough["unpaid_words"], 0)

    def test_a_waiting_join_keeps_no_bound_payload(self):
        # The join reads a large P first and waits on Tag: what waits for the
        # refused rows keeps no copy of the P terms already bound into it.
        facts = [f"(: p{i} (P (v{i} " + " ".join(["x"] * 10000) + ")) (STV 1 0.9))" for i in range(4)]
        atoms = ["(: (no_inverse r) (Implication (And (P $x) (Tag $y)) (Q $x $y)) (STV 1 0.9))",
                 "(: t0 (Tag a) (STV 1 0.9))", "(: t1 (Tag b) (STV 1 0.9))"] + facts
        short, again, enough = run("waiter", atoms, ["(: $p (Q $x $y) $tv)"], steps=(1, 1, 400))
        for waiting in (short, again):
            self.assertEqual(waiting["answers"], [])
            self.assertLess(waiting["unpaid_words"], 2000)
        self.assertEqual(len(enough["answers"]), 8)
        self.assertEqual(enough["unpaid_words"], 0)

    def test_a_refused_forward_application_continues_in_the_next_run(self):
        # A seeded one-step run refuses the large row; an empty larger run
        # continues from the carried agenda and stores what a cold run stores,
        # and a further run adds nothing.
        atoms = ["(: (no_inverse r) (Implication (P $x) (Q $x)) (STV 1 0.9))",
                 "(: p (P (" + " ".join(["x"] * 10000) + ")) (STV 1 0.9))"]
        short, resumed, idle = run("forward", atoms, [("forward (P $x)", 1), ("forward ", 200), ("forward ", 200)])
        [cold] = run("forward-cold", atoms, [("forward (P $x)", 200)])
        self.assertEqual(short["answers"], [])
        self.assertLess(short["unpaid_words"], 2000)
        self.assertEqual(without_kb(resumed["answers"]), without_kb(cold["answers"]))
        self.assertEqual(len(cold["answers"]), 1)
        self.assertEqual(idle["answers"], [])
        self.assertEqual(resumed["unpaid_words"], 0)

    def test_ground_root_applications_spend_the_allowance(self):
        # One rule over 1,000 facts concludes the ground root: its rows are not
        # free scaffold, so one step builds what one step pays for, quickly,
        # and more budget adds evidence.
        atoms = ["(: (no_inverse r) (Implication (P $x) (Q a)) (STV 1 0.9))"] + [
            f"(: p{i} (P a{i}) (STV 1 0.9))" for i in range(1000)]
        small, large = (run(f"ground{steps}", atoms, ["(: $p (Q a) $tv)"], steps=(steps,))[0] for steps in (1, 3))
        self.assertLess(small["seconds"], 5, small["seconds"])
        self.assertGreater(tv(large["answers"][0])[1], tv(small["answers"][0])[1])

    def test_interrupted_replays_stay_owed_and_resume(self):
        # #175 at a budget its replays outrun: the query reports it ran out, keeps
        # its direct answer, and larger and repeated queries keep answering.
        statuses = run("i175-retry", I175_TEXT + I175_BACKGROUND, [I175_QUERY], steps=(25, 400, 400))
        self.assertEqual(statuses[0]["status"], "ran-out")
        for result in statuses:
            self.assertEqual(len(result["answers"]), 1, result)
            self.assertIn("(More old sk_bob_1 sk_lamine_1)", result["answers"][0])

    def test_branch_rebuild_replays_settle_once_paid(self):
        # The eight-period plant owes replays inside branch rebuilds, which have
        # no reading row: the first query answers coarsely, its requests stay
        # unsettled, the next query at the same budget pays them, and the one
        # after answers as it did.
        results = [r["answers"] for r in run("plant8", [], [PLANT8], steps=(3000, 3000, 3000))]
        for result in results:
            self.assertEqual([len(group) for group in result], [1, 1])
        self.assertNotEqual(results[0], results[1])
        self.assertEqual(results[1], results[2])

    def test_a_large_row_cannot_step_over_the_claims_share(self):
        # A depth-0 target waits with estimated cost 6 while the allowance is
        # 12 and the root claims' share 10: a depth-3 row costing 12 would
        # step from above the share to nothing in one payment. It must leave
        # the target its 3 units, as a row of cost one must once inside it.
        import janus_swi as janus
        from pettachainer import PeTTaChainer
        PeTTaChainer()
        result = janus.query_once("""
          _Root=['sk-key',['Root',a],[fairKb,'MAIN','Nil']],
          length(_Parts,1466),maplist(=(x),_Parts),_Type=[deep|_Parts],
          _Key=['sk-key',_Type,[fairKb,'MAIN','Nil']],
          'index-hash'(_Root,_RH), 'index-hash'(_Key,_KH),
          setup_call_cleanup(
            ( assertz('&sk_keys'(_RH,_Root)), assertz('&sk_needed'(_RH,_Root,0)),
              assertz('&sk_needed'(_KH,_Key,3)), assertz('&sk_given_pending'(_RH,-1,6)),
              'change-state!'(sk_forward_run,0,_), 'change-state!'(sk_root_claim_cap,10,_) ),
            ( _Item=['sk-row-item',1,_KH,_Key,2,['sk-row',ident,concl,[],1]],
              'change-state!'(sk_eval_budget,12,_), 'term-cost'(_Type,12,Cost),
              'sk-claims-held'(_Item,Cost,HeldAcross),
              'change-state!'(sk_eval_budget,30,_), 'sk-claims-held'(_Item,Cost,HeldAbove),
              'change-state!'(sk_eval_budget,10,_), 'sk-claims-held'(_Item,1,HeldWithin) ),
            ( retract('&sk_keys'(_RH,_Root)), retract('&sk_needed'(_RH,_Root,0)),
              retract('&sk_needed'(_KH,_Key,3)), retract('&sk_given_pending'(_RH,-1,6)) ))
        """)
        self.assertEqual(result["Cost"], 12)
        self.assertEqual((result["HeldAcross"], result["HeldAbove"], result["HeldWithin"]), (3, 0, 3))

    def test_colliding_waiters_keep_their_own_continuations(self):
        # Two stored waiters of one owner and rule whose variant hashes collide
        # (found by storing waiters until a hash bucket holds two): each
        # deferred join names its own waiter, both resume once each, and
        # retiring one neither redirects the other's handle nor is held by it.
        import janus_swi as janus
        from pettachainer import PeTTaChainer
        PeTTaChainer()
        result = janus.query_once("""
          _C=[['Out',_X],[collideKb,'MAIN','Nil'],_,_], _P=[['Input',_X],[collideKb,'MAIN','Nil'],_,_],
          assertz(ccls_index(_C,9999300,[_P])),
          _Owner=[['Out',_],[collideKb,'MAIN','Nil'],_,_],
          once(( between(1,60000,_I),
                 _N=[['Input',_I],[collideKb,'MAIN','Nil'],_,_], _O=[['Out',_I],[collideKb,'MAIN','Nil'],_,_],
                 'sk-node-hash'(_N,_H), 'sk-store-wait!'(_I,_H,_N,['sk-partial',_Owner,9999300,_O,[],[_N],[]],_),
                 sk_wait_ref(_H,_N,['sk-partial',_Owner,9999300,_O,[],[_N],[]],_R2),
                 clause(sk_wait_payload(_,_S2,_T2,_B2),true,_R2), variant_hash([_S2,_T2|_B2],_Hash),
                 sk_wait_key(_Hash,_R1), _R1 \== _R2,
                 clause(sk_wait_payload(_,[_,[collideKb|_]|_],_,_),true,_R1) )),
          clause(sk_wait_payload(_H1,_N1,_T1,_B1),true,_R1), sk_wait_template(_,_,_T1,_W1,_B1),
          clause(sk_wait_payload(_H2,_N2,_,_B2b),true,_R2), sk_wait_template(_,_,_T2,_W2,_B2b),
          _N1=[['Input',First],_|_], _N2=[['Input',Second],_|_],
          'sk-wait-handle'(_W1,Handle1), 'sk-wait-handle'(_W2,Handle2),
          'sk-node-hash'(_Owner,_OH), 'sk-mark-expanded!'(_OH,_Owner,_),
          'sk-defer-join!'(_W1,_), 'sk-defer-join!'(_W2,_),
          aggregate_all(count,'&sk_deferred_joins'(_OH,_,_),Deferred),
          nb_setval(collide_reads,[]),
          wrap_predicate('sk-read-answers!'(_RW,_RP,_RO),collide_read,_Read,
             (_RP=[['Input',_V]|_], nb_getval(collide_reads,_L), nb_setval(collide_reads,[_V|_L]), call(_Read))),
          'change-state!'(sk_row_budget,100,_), 'sk-resume!'(_OH,_Owner,_),
          nb_getval(collide_reads,Reads0), msort(Reads0,Reads),
          aggregate_all(count,'&sk_deferred_joins'(_OH,_,_),Left),
          'sk-defer-join!'(_W2,_),
          ( sk_wait_id_of(_R1,_Id1), '&sk_deferred_joins'(_,_,['sk-join',_,_,_Id1]) -> FirstHeld=true ; FirstHeld=false ),
          sk_retire_wait_ref(_R1),
          'sk-waiter-at'(Handle1,After1), length(After1,Gone),
          'sk-waiter-at'(Handle2,[_After2]), _After2=['sk-partial',_,_,[[_,SecondStill]|_]|_]
        """)
        first, second = result["First"], result["Second"]
        self.assertNotEqual(first, second)
        self.assertNotEqual(result["Handle1"], result["Handle2"])
        self.assertEqual(result["Deferred"], 2)
        self.assertEqual(result["Reads"], sorted([first, second]))
        self.assertEqual(result["Left"], 0)
        self.assertEqual(result["FirstHeld"], "false")
        self.assertEqual(result["Gone"], 0)
        self.assertEqual(result["SecondStill"], second)

    def test_colliding_deferred_joins_of_two_rules_both_resume(self):
        # Two waiters of one open owner under two rules whose deferred-join
        # records hash alike (found by storing waiters, alternating the rule,
        # until two records' index hashes meet): both records are kept, a
        # repeated deferral adds none, and resuming reads each waiter once.
        import janus_swi as janus
        from pettachainer import PeTTaChainer
        PeTTaChainer()
        janus.query_once("dynamic(two_rule_hash/2)")
        result = janus.query_once("""
          _C=[['Out',_X],[twoRuleKb,'MAIN','Nil'],_,_], _P=[['Input',_X],[twoRuleKb,'MAIN','Nil'],_,_],
          assertz(ccls_index(_C,9999500,[_P])), assertz(ccls_index(_C,9999501,[_P])),
          _Owner=[['Out',_],[twoRuleKb,'MAIN','Nil'],_,_],
          once(( between(1,400000,_I), _Rule is 9999500 + (_I mod 2),
                 _N=[['Input',_I],[twoRuleKb,'MAIN','Nil'],_,_], _O=[['Out',_I],[twoRuleKb,'MAIN','Nil'],_,_],
                 _W=['sk-partial',_Owner,_Rule,_O,[],[_N],[]],
                 'sk-node-hash'(_N,_H), 'sk-store-wait!'(_I,_H,_N,_W,_),
                 sk_wait_ref(_H,_N,_W,_R2), 'sk-wait-handle'(_W,_Id),
                 'index-hash'(['sk-join',_Owner,_Rule,_Id],_Hash),
                 ( two_rule_hash(_Hash,_R1) -> true ; assertz(two_rule_hash(_Hash,_R2)), fail ) )),
          clause(sk_wait_payload(_,_N1,_T1,_B1),true,_R1), sk_wait_template(_,_,_T1,_W1,_B1),
          clause(sk_wait_payload(_,_N2,_T2,_B2),true,_R2), sk_wait_template(_,_,_T2,_W2,_B2),
          _N1=[['Input',First],_|_], _N2=[['Input',Second],_|_], _W1=[_,_,Rule1|_], _W2=[_,_,Rule2|_],
          'sk-node-hash'(_Owner,_OH), 'sk-mark-expanded!'(_OH,_Owner,_),
          'sk-defer-join!'(_W1,_), 'sk-defer-join!'(_W2,_), 'sk-defer-join!'(_W1,_),
          aggregate_all(count,'&sk_deferred_joins'(_OH,_,_),Deferred),
          nb_setval(two_rule_reads,[]),
          wrap_predicate('sk-read-answers!'(_RW,_RP,_RO),two_rule_read,_Read,
             (_RP=[['Input',_V]|_], nb_getval(two_rule_reads,_L), nb_setval(two_rule_reads,[_V|_L]), call(_Read))),
          'change-state!'(sk_row_budget,100,_), 'sk-resume!'(_OH,_Owner,_),
          nb_getval(two_rule_reads,Reads0), msort(Reads0,Reads),
          aggregate_all(count,'&sk_deferred_joins'(_OH,_,_),Left)
        """)
        self.assertNotEqual(result["Rule1"], result["Rule2"])
        self.assertEqual(result["Deferred"], 2)
        self.assertEqual(result["Reads"], sorted([result["First"], result["Second"]]))
        self.assertEqual(result["Left"], 0)


if __name__ == "__main__":
    unittest.main()
