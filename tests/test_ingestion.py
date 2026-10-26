"""The source ingestion boundary rejects free facts and oversized statements."""
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer


class TestIngestion(unittest.TestCase):
    def setUp(self):
        self.h = PeTTaChainer()

    def test_free_fact_variables_reject_before_compiler_side_effects(self):
        for statement in ('$statement', '($predicate a b)', '($predicate a)',
                          '(Pair $x $x)', '(P $y)', '(Not (Pair $x $x))',
                          '(And (P a) (Q $x))',
                          '(ClaimContent $finding (Implication (P $x) (Q $x)))',
                          '(Pair $x (Implication (P $x) (Q $x)))',
                          '(Pair (Implication (P $x) (Q $x)) $x)',
                          '(ClaimContent f (ForAll ($x) (Pair $x $y)))',
                          '(ClaimContent f (Exists ($x) (Pair $x $y)))',
                          '(ClaimContent f (ForAll ($x) ($head $x)))'):
            atom = f'(: rejected {statement} (STV 1 1))'
            for add in (self.h.add_atom,
                        lambda a: self.h.add_atoms_no_check([a]),
                        lambda a: self.h._call('compileadd', [f'{self.h.kb} {a}'])):
                with self.subTest(statement=statement, add=add), self.assertRaisesRegex(
                        janus.PrologError, 'fact.*free.variables'):
                    add(atom)
            # A variable head must never create an a -> b rule, nor a fact.
            rows = janus.query_once(
                "aggregate_all(count,'&kb'(_, [Kb,'MAIN','Nil'], rejected, _),Facts),"
                "aggregate_all(count,(rules('runtime-rule-row',_,[_,[Kb|_],_Prf,_],_),"
                "sub_term(_P,_Prf),_P==rejected),Rules)",
                {'Kb': self.h.kb})
            self.assertEqual(rows['Facts'], 0)
            self.assertEqual(rows['Rules'], 0)
            self.assertNotIn(atom, self.h._added_atoms)

    def test_lexical_binders_in_quoted_content_allow_only_their_own_scope(self):
        statements = [
            '(ClaimContent finding (Implication (Member $a Event) (Occurred $a)))',
            '(AccordingTo source (NotificationContent notification '
            '(Implication (And (Member $app App) (Requires $app MacOS 13)) '
            '(Can (DropSupport $app IntelMac)))))',
            '(ClaimContent f (ForAll ($x) (Pair $x $x)))',
            '(ClaimContent f (Exists ($x) (Pair $x $x)))',
            '(ClaimContent f (ForAll ($x) (Exists ($y) (Pair $x $y))))',
            '(ClaimContent f (BiImplication (P $x) (Q $x)))',
            '(ClaimContent f (WithPrior (Prior $x) (Implication (P $x) (Q $x))))',
            '(Pair (ForAll ($x) (P $x)) (Exists ($x) (Q $x)))',
            '(ClaimContent f (Implication ($predicate $x) (Q $x)))',
        ]
        for i, statement in enumerate(statements):
            with self.subTest(statement=statement):
                name = f'bound{i}'
                additions = self.h.add_atom(f'(: {name} {statement} (STV 1 1))')
                self.assertTrue(additions)
                answers = self.h.query(f'(: $proof {statement} $tv)', steps=0, timeout_sec=0)
                self.assertEqual(len(answers), 1)
                self.assertIn(name, answers[0])
        self.assertEqual(self.h.query('(: $proof (Occurred anything) $tv)',
                                     steps=0, timeout_sec=0), [])

    def test_ke_reference_quoted_rule_is_stored_and_answers_unchanged(self):
        # Copied from KE reference_translations.json case 5, statements[3].
        statement = ('(ClaimContent AnnouncementReactionFinding '
                     '(Implication (And (Member $announcement EarningsAnnouncement) '
                     '(FromFirm $announcement $firm) (LocatedInCounty $firm $county) '
                     '(Member $county HigherCentralityCounty)) '
                     '(And (StrongerImmediatePriceReaction $announcement) '
                     '(StrongerImmediateVolatilityReaction $announcement) '
                     '(StrongerImmediateTradingVolumeReaction $announcement))))')
        self.h.add_atom(f'(: src_ref_3 {statement} (STV 1.0 0.9))')
        answers = self.h.query(f'(: $proof {statement} $tv)', steps=0, timeout_sec=0)
        self.assertEqual(len(answers), 1)
        self.assertIn('src_ref_3', answers[0])
        self.assertTrue(answers[0].endswith('(STV 1.0 0.9))'))

    def test_variable_predicate_queries_keep_all_matching_predicates(self):
        self.h.add_atoms_no_check([
            '(: f (Friend a b) (STV 1 1))',
            '(: e (Enemy a b) (STV 1 1))',
            '(: unary (Present a) (STV 1 1))',
        ])
        for steps in (0, 20, 40):
            binary = self.h.query_many_refs(['(: $proof ($predicate a b) $tv)'], steps=steps)[0]
            self.assertEqual({tuple(a.statement) for a in binary},
                             {('Friend', 'a', 'b'), ('Enemy', 'a', 'b')})
            wildcard = self.h.query_many_refs(['(: $proof ($p $x $y) $tv)'], steps=steps)[0]
            self.assertEqual({tuple(a.statement) for a in wildcard},
                             {('Friend', 'a', 'b'), ('Enemy', 'a', 'b')})
            unary = self.h.query_many_refs(['(: $proof ($predicate a) $tv)'], steps=steps)[0]
            self.assertEqual([a.statement for a in unary], [['Present', 'a']])

    def test_dispatch_helpers_preserve_unknown_statement_heads(self):
        # These paths consume source rules, open premises, keys or recursive
        # expressions. No syntax inspection may instantiate a predicate head.
        cases = {
            'lower': "'lower'([Kb,'MAIN','Nil'],[_Head,a,b,c],_Out),var(_Head)",
            'source-compute-goals': "'source-compute-goals'([[_Head,a,b,c]],_Out),var(_Head)",
            'canonical-addition': "'canonical-addition'([Kb,'MAIN','Nil'],[],[by,r,cpu],[_Head,a],['STV',1.0,1.0],_Out),var(_Head)",
            'base-rate-fold': "'base-rate-fold'(Kb,[_Head,_X,concept],_TV,_Out),var(_Head)",
            'default-query-assumption-tv': "'default-query-assumption-tv'([_Head,a,b],_TV,_Out),var(_Head),_Out==['STV',1.0,1.0]",
            'query-context-assumed-implication-rules': "'query-context-assumed-implication-rules'(Kb,ctx,[],proof,[_Head,a,b],['STV',1.0,1.0],_Out),var(_Head),_Out==[]",
            'internalize-proof-structure-any': "'internalize-proof-structure-any'([_Head,a,b,c,d],_Out),var(_Head)",
            'public-query-type': "'public-query-type'([_Head,a,b],_Out),var(_Head)",
            'pattern-shape': "'pattern-shape'([_Head,['P',a],['Q',b]],_Out),var(_Head)",
            'sk-fact-premise-type': "'sk-fact-premise-type'([[_Head,a],[Kb,'MAIN','Nil'],proof,['STV',1.0,1.0]],[],_Out),var(_Head),_Out=[[_Head,a]]",
            'sk-shared-candidate': "'sk-shared-candidate'([],['sk-key',[_Head,a],[Kb,'MAIN','Nil']],_Out),var(_Head)",
            'forward-maintain-member-aggregates!': "'forward-maintain-member-aggregates!'(forward_add,[[_Head,a,b],[Kb,'MAIN','Nil'],proof,['STV',1.0,1.0]],_Out),var(_Head)",
            'sk-row-exclusions': "_Key=['sk-key',[_Head,a,b,c,d],[Kb,'MAIN','Nil']],'index-hash'(_Key,_Hash),'sk-row-exclusions'(_Hash,_Key,proof,_Out),var(_Head)",
        }
        for label, query in cases.items():
            with self.subTest(site=label):
                self.assertTrue(janus.query_once(query, {'Kb': self.h.kb})['truth'])

    def test_native_rule_truth_and_assumption_dispatch_requires_actual_heads(self):
        settling = "['CPU','SettlesFormula',[['STV',1.0,1.0],['STV',1.0,1.0]],_Res]"
        # No stored premise exists. An unknown unary predicate cannot be
        # skipped as if it were the compiler's RuleTruth premise.
        unknown = (r"\+ dormancy_settles([[[_Head,a],[Kb,'MAIN','Nil'],audit_missing,_TV],"
                   + settling + "]),var(_Head)")
        known = ("dormancy_settles([[['RuleTruth',a],[Kb,'MAIN','Nil'],audit_missing,_TV],"
                 + settling + "])")
        for query in (unknown, known):
            with self.subTest(query=query):
                self.assertTrue(janus.query_once(query, {'Kb': self.h.kb})['truth'])
        for head, expected in (("_Head", "_Out==[]"),
                               ("'Implication'", "_Out=[['CPU','ContextRule'|_]]")):
            # Query assumptions are internal facts and may have open heads.
            # A rule marker may be appended only to an actual implication.
            query = (
                "atom_concat(Kb,'_audit',_C),'context-create!'([Kb,_C,'Nil'],_),"
                "_Token=[ctx,proof,_C],_TV=['STV',1,1],"
                "_Concl=[['Target'],[Kb,'MAIN','Nil'],[by,r,_Token],_TV],"
                "setup_call_cleanup(assertz('&kb'([" + head + ",a,b],[Kb,_C,'Nil'],_Token,_TV),_Ref),"
                "('context-rule-premises'(_Concl,[],_Out)," + expected + "),erase(_Ref))")
            with self.subTest(head=head):
                self.assertTrue(janus.query_once(query, {'Kb': self.h.kb})['truth'])

    def test_variable_heads_in_rule_outputs_and_nested_query_arguments(self):
        self.h.add_atoms_no_check([
            '(: unary_label (UnaryLabel Present a) (STV 1 1))',
            '(: binary_label (BinaryLabel Friend a b) (STV 1 1))',
            '(: unary_rule (Implication (UnaryLabel $predicate $x) ($predicate $x)) '
            '(CTV (STV 1 1) (STV 0 1)))',
            '(: binary_rule (Implication (BinaryLabel $predicate $x $y) ($predicate $x $y)) '
            '(CTV (STV 1 1) (STV 0 1)))',
            '(: ternary (Rel3 a b c) (STV 1 1))',
            '(: ternary_rule (Implication ($predicate $x $y $z) (Seen3 $predicate $x $y $z)) '
            '(CTV (STV 1 1) (STV 0 1)))',
            '(: quaternary (Rel4 a b c d) (STV 1 1))',
            '(: quaternary_rule (Implication ($predicate $w $x $y $z) (Seen4 $predicate $w $x $y $z)) '
            '(CTV (STV 1 1) (STV 0 1)))',
            '(: nested (Related (P a) (Q b)) (STV 1 1))',
        ])
        unary, binary, ternary, quaternary, nested = self.h.query_many_refs([
            '(: $proof (Present a) $tv)',
            '(: $proof (Friend a b) $tv)',
            '(: $proof (Seen3 Rel3 a b c) $tv)',
            '(: $proof (Seen4 Rel4 a b c d) $tv)',
            '(: $proof ($predicate (P a) (Q b)) $tv)',
        ], steps=60)
        self.assertEqual([a.statement for a in unary], [['Present', 'a']])
        self.assertEqual([a.statement for a in binary], [['Friend', 'a', 'b']])
        self.assertEqual([a.statement for a in ternary], [['Seen3', 'Rel3', 'a', 'b', 'c']])
        self.assertEqual([a.statement for a in quaternary], [['Seen4', 'Rel4', 'a', 'b', 'c', 'd']])
        self.assertEqual([a.statement for a in nested], [['Related', ['P', 'a'], ['Q', 'b']]])

    def test_rules_remain_schematic_including_parameterized_and_computed_tvs(self):
        # One arity per head (#96 D4): the two-argument rules use P2 and Q2.
        for rule in ('(Implication ($predicate $x) (Observed $x))',
                     '(ForAll ($cohort) (Implication (P2 $cohort $x) (Q2 $cohort $x)))',
                     '(WithPrior (Prior $x) (Implication (P $x) (Q $x)))',
                     '(ForAll ($c) (WithPrior (Prior2 $c $x) '
                     '(Implication (P2 $c $x) (Q2 $c $x))))',
                     '(Implication (Exists ($x) (P $x)) (Q0))'):
            with self.subTest(rule=rule):
                self.assertTrue(self.h.add_atom(f'(: r {rule} (STV 1 1))'))
        self.assertTrue(self.h.add_atom(
            '(: computed (Implication (And (P $x) (Compute id (1) -> $p)) '
            '(Result $x)) (CTV (STV $p 1) (STV $p 1)))'))

    def test_default_size_limit_and_configurable_utf8_boundary(self):
        too_large = '(: oversized (Payload ' + 'x' * 65536 + ') (STV 1 1))'
        for add in (self.h.add_atom, lambda a: self.h.add_atoms_no_check([a])):
            with self.assertRaisesRegex(janus.PrologError, 'stored_term_bytes.*65536'):
                add(too_large)
        # Exact canonical annotation sizes: single spaces, integer STV fields.
        atom = '(: boundary (Payload "é\\\"\\\\") (STV 1 1))'
        size = len(atom.encode('utf-8'))
        self.h.set_max_term_bytes(size - 1)
        with self.assertRaisesRegex(janus.PrologError, 'max-term-bytes'):
            self.h.add_atom(atom)
        self.h.set_max_term_bytes(size)
        self.assertTrue(self.h.add_atom(atom))
        # Settings belong to a KB, and a rule is capped just like a fact.
        other = PeTTaChainer()
        self.assertTrue(other.add_atom(atom))
        with self.assertRaisesRegex(janus.PrologError, 'stored_term_bytes'):
            self.h.add_atom('(: large_rule (Implication (P $x) (Payload '
                            + 'x' * size + ' $x)) (STV 1 1))')
        self.h.set_max_term_bytes(len(too_large))
        self.assertTrue(self.h.add_atom(too_large))
        for limit in (0, -1, True, 1.5, '65536'):
            with self.subTest(limit=limit), self.assertRaises(ValueError):
                self.h.set_max_term_bytes(limit)

    def test_batch_rejection_journals_only_successful_prefix(self):
        accepted = '(: accepted (P a) (STV 1 1))'
        rejected = '(: rejected (P $x) (STV 1 1))'
        after = '(: after (P b) (STV 1 1))'
        with self.assertRaisesRegex(janus.PrologError, 'fact.*free.variables'):
            self.h.add_atoms_no_check([accepted, rejected, after])
        self.assertEqual(self.h._added_atoms, [accepted])
        for timeout in (0, 20):
            answers = self.h.query('(: $proof (P $x) $tv)', steps=0, timeout_sec=timeout)
            self.assertEqual(answers, ['(: accepted (P a) (STV 1 1))'])

    def test_proof_name_restated_with_another_value_rejects(self):
        # A name, context and statement are one observation's identity (#113).
        for name, statement in (('fact', '(P a)'), ('rule', '(Implication (P $x) (Q $x))')):
            with self.subTest(statement=statement):
                stored = f'(: {name} {statement} (STV 0.6 0.5))'
                rows = lambda: janus.query_once(
                    "aggregate_all(count,'&kb'(_, _, Name, _),N)", {'Name': name})['N']
                self.h.add_atom(stored)
                count = rows()
                self.h.add_atom(stored)
                with self.assertRaisesRegex(janus.PrologError, 'restate proof'):
                    self.h.add_atom(f'(: {name} {statement} (STV 1.0 1.0))')
                self.assertEqual(rows(), count)
        # The same value is a restatement however it is written.
        for stored, restated in (('(P b) (STV 1 1)', '(P b) (STV 1.0 1.0)'),
                                 ('(P c) (STV 0.2 0.9)', '(Not (P c)) (STV 0.8 0.9)')):
            with self.subTest(restated=restated):
                self.h.add_atom(f'(: same {stored})')
                self.h.add_atom(f'(: same {restated})')

    def test_malformed_asserted_negation_rejects_before_publication(self):
        for statement in ('(Not)', '(Not a b)', '(Not (Not a b))'):
            atom = f'(: malformed {statement} (STV 0.8 0.9))'
            for add in (self.h.add_atom,
                        lambda a: self.h.add_atoms_no_check([a]),
                        lambda a: self.h._call('compileadd', [f'{self.h.kb} {a}'])):
                with self.subTest(statement=statement, add=add), self.assertRaisesRegex(
                        janus.PrologError, 'negation.*one.*argument'):
                    add(atom)
            self.assertNotIn(atom, self.h._added_atoms)
            self.assertEqual(janus.query_once(
                "aggregate_all(count,'&kb'(_, [Kb,'MAIN','Nil'], malformed, _),N)",
                {'Kb': self.h.kb})['N'], 0)

    def test_negated_statement_takes_only_an_stv(self):
        # A negation is stored at its statement's key with the strength
        # complemented; no other value has a complement (#142).
        for value in ('(CTV (STV 0.8 0.9) (STV 0.2 0.9))', '(PointMass 1.0)'):
            with self.subTest(value=value), self.assertRaisesRegex(
                    janus.PrologError, 'negated statement takes an STV'):
                self.h.add_atom(f'(: notP (Not (P a)) {value})')

    def test_variable_head_query_order_and_population_refinement(self):
        # A variable-headed and a concrete rule give the same value, cold or
        # warm and in either query order: independent KBs, then reversed.
        for head in ('variable', 'concrete'):
            rule = ('(Implication (And (Symmetric $r) ($r $x $y)) ($r $y $x))'
                    if head == 'variable' else
                    '(Implication (And (Symmetric Friend) (Friend $x $y)) (Friend $y $x))')
            for goal in ('(Friend alice bob)', '(Friend alice $x)'):
                with self.subTest(head=head, goal=goal):
                    h = PeTTaChainer()
                    h.add_atoms_no_check([
                        f'(: symmetric {rule} (STV 0.9 0.9))',
                        '(: tag (Symmetric Friend) (STV 0.9 0.9))',
                        '(: edge (Friend bob alice) (STV 0.9 0.9))',
                    ])
                    other = '(Friend alice $x)' if goal == '(Friend alice bob)' else '(Friend alice bob)'
                    # The negative branch reads the antecedent's composed prior
                    # while its joint fold has no evidence (#142), so a cold
                    # query already gives the converged value for both heads.
                    for query, (strength, confidence) in ((goal, (0.8642193246799066, 0.02243916988834716)),
                                                         (other, (0.8642193246799066, 0.02243916988834716)),
                                                         (goal, (0.8642193246799066, 0.02243916988834716))):
                        answer = h.query_many_refs([f'(: $p {query} $tv)'], steps=100)[0]
                        self.assertEqual([a.statement for a in answer], [['Friend', 'alice', 'bob']])
                        self.assertAlmostEqual(answer[0].tv[1], strength)
                        self.assertAlmostEqual(answer[0].tv[2], confidence)

    def test_size_limit_replays_before_timed_worker_loads_large_knowledge(self):
        atom = '(: large (Payload ' + 'x' * 65536 + ') (STV 1 1))'
        self.h.set_max_term_bytes(len(atom))
        self.h.add_atom(atom)
        self.h.add_atom('(: marker (Marker) (STV 1 1))')
        # Lowering the future-add limit cannot invalidate accepted knowledge.
        self.h.set_max_term_bytes(128)
        self.assertEqual(self.h.query('(: $proof (Marker) $tv)',
                                     steps=0, timeout_sec=20),
                         ['(: marker (Marker) (STV 1 1))'])


if __name__ == '__main__':
    unittest.main()
