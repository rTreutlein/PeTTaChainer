"""Issues #63/#65: world co-premises join; assumptions remain necessary.

The 18 capability scenarios mirror the KE handover without importing its app.
Each case starts a fresh KB and repeats the query in the same live runtime.
"""
import unittest
from pettachainer import PeTTaChainer


# P(identity) with the report (STV 1 .9) at k 800: m = 7201/7202 on the
# all-true world of three uniform parts, 1 - m on the other seven.
IDENTITY = 7201 / 7208
IDENTITY_CASES = {'derived_ground_bridge', 'derived_existential_bridge',
                  'existential_identity_control', 'explicit_conditional'}


def entry(name, atom):
    return {'name': 'src_' + name, 'source_id': name, 'atom': f'(: src_{name} {atom} (STV 1 0.9))'}


def scenarios():
    identity = entry('event', '(And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit))')
    rule = entry('rule', '(Implication (Member $e StockSplit) (Not (Dilutes $e)))')
    query = '(Exists ($e) (And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Implication (Implemented $e) (Not (Dilutes $e)))))'
    ground = query.removeprefix('(Exists ($e) ')[:-1].replace('$e', 'Split1')
    explicit = entry('conditional', '(Implication (Implemented Split1) (Not (Dilutes Split1)))')
    bridge = entry('bridge', '(Implication (And (Member $e StockSplit) (Implemented $e)) (Not (Dilutes $e)))')
    split_fact = entry('split', '(Member Split1 StockSplit)')
    simple_bridge = entry('simple_bridge', '(Implication (And (StockSplit $e) (Implemented $e)) (Not (Dilutes $e)))')
    conditional = '(Implication (Implemented Split1) (Not (Dilutes Split1)))'
    cases = [
        ('positive_consequent_control', [entry('split', '(StockSplit Split1)'), entry('bridge', '(Implication (And (StockSplit $e) (Implemented $e)) (PreservesOwnership $e))')], '(Implication (Implemented Split1) (PreservesOwnership Split1))', True),
        ('direct_modus_ponens_control', [split_fact, rule], '(Not (Dilutes Split1))', True),
        ('standalone_member_bridge', [split_fact, bridge], conditional, True),
        ('unary_bridge', [entry('split', '(StockSplit Split1)'), simple_bridge], conditional, True),
        ('ground_bridge_rule', [split_fact, entry('bridge', '(Implication (And (Member Split1 StockSplit) (Implemented Split1)) (Not (Dilutes Split1)))')], conditional, True),
        # #68: condition the join on its shared compound observation.
        ('derived_ground_bridge', [identity, bridge], ground, True),
        ('derived_existential_bridge', [identity, bridge], query, True),
        # Oct 16 agreement with the KE owner: no assumption-dependent proof,
        # so this standalone conditional must have no answer (tracker #65).
        ('conditional_only_control', [identity, rule], '(Implication (Implemented Split1) (Not (Dilutes Split1)))', False),
        # These wrappers contain the same unsupported conditional. Adding
        # identity conjuncts or an existential witness cannot supply its
        # missing assumption dependency; keep the original KE fixtures.
        ('ground_control', [identity, rule], ground, False),
        ('existential_identity_control', [identity], '(Exists ($e) (And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit)))', True),
        ('existential_conditional', [identity, rule], query, False),
        ('explicit_conditional', [identity, explicit], query, True),
        ('missing_rule', [identity], query, False),
        ('missing_event', [rule], query, False),
        ('wrong_date', [identity, rule], query.replace('Date20200730', 'Date20210730'), False),
        ('mismatched_witness', [identity, entry('other', '(Implication (Implemented Split2) (Not (Dilutes Split2)))')], query, False),
        ('unaccepted_source', [identity, entry('gated', '(Implication (AcceptSource Report1) (Implication (Member $e StockSplit) (Not (Dilutes $e))))')], query, False),
        ('implementation_not_asserted', [identity, explicit], '(Implemented Split1)', False),
    ]
    return cases


class TestConditionalWorldFacts(unittest.TestCase):
    def test_ke_capability_scenarios_fresh_and_warm(self):
        for name, entries, expression, expected in scenarios():
            h = PeTTaChainer()
            h.add_atoms_no_check([entry['atom'] for entry in entries])
            runs = [h.query_many_refs([f'(: $p {expression} $tv)'], steps=300)[0]
                    for _ in range(2)]
            for repeat, rows in enumerate(runs):
                with self.subTest(case=name, repeat=repeat):
                    self.assertEqual(bool(rows), expected, rows)
                    for row in rows:
                        self.assertEqual(row.tv[0], 'STV')
                        if name in IDENTITY_CASES:
                            # The event report is a likelihood on its three
                            # uniform parts: the whole query reads the
                            # identity's posterior, at the conservative
                            # variance bound of an observed compound (c 0).
                            self.assertAlmostEqual(row.tv[1], IDENTITY, delta=1e-10)
                            self.assertGreaterEqual(row.tv[2], 0.0)
                        else:
                            self.assertAlmostEqual(row.tv[1], 1.0)
                            self.assertGreater(row.tv[2], 0.0)
                        self.assertLessEqual(row.tv[2], 0.9)
                        if name == 'positive_consequent_control':
                            self.assertAlmostEqual(row.tv[2], 0.8709372443124922)
                        if name in {'derived_existential_bridge', 'existential_conditional'}:
                            self.assertEqual(row.statement[0], 'Exists')
                            witness = row.statement[1][0]
                            self.assertEqual(row.statement[2], ['And',
                                ['AnnouncedBy', witness, 'Apple'],
                                ['AnnouncedOn', witness, 'Date20200730'],
                                ['Member', witness, 'StockSplit'],
                                ['Implication', ['Implemented', witness], ['Not', ['Dilutes', witness]]],
                            ])
                        proof = h.expand_proof(row.proof)
                        if name in {'positive_consequent_control', 'standalone_member_bridge',
                                    'unary_bridge', 'ground_bridge_rule', 'derived_ground_bridge',
                                    'derived_existential_bridge'}:
                            self.assertIn('conditional-implication', proof)
                            self.assertIn('(ctx proof ', proof)
                            self.assertIn('src_bridge' if name != 'unary_bridge' else 'src_simple_bridge', proof)
                            self.assertIn('src_event' if name.startswith('derived_') else 'src_split', proof)
                    # All scenarios leave implementation and source acceptance unknown.
                    self.assertEqual(h.query_many_refs([
                        '(: $p (Implemented Split1) $tv)',
                        '(: $p (AcceptSource Report1) $tv)',
                    ], steps=300), [[], []])
                    if name == 'positive_consequent_control':
                        self.assertEqual(h.query_many_refs([
                            '(: $p (PreservesOwnership Split1) $tv)',
                        ], steps=300), [[]])
                    if name in {'standalone_member_bridge', 'unary_bridge', 'ground_bridge_rule',
                                'derived_ground_bridge', 'derived_existential_bridge'}:
                        self.assertEqual(h.query_many_refs([
                            '(: $p (Not (Dilutes Split1)) $tv)',
                        ], steps=300), [[]])

    def test_assumption_free_chain_has_no_conditional_proof(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: c1 (C x) (STV 1 0.9))',
            '(: r1 (Implication (C $v) (B $v)) (STV 0.8 0.9))',
        ])
        for repeat in range(2):
            with self.subTest(repeat=repeat):
                self.assertEqual(h.query_many_refs([
                    '(: $p (Implication (A x) (B x)) $tv)',
                ], steps=300)[0], [])
        self.assertEqual(h.query_many_refs(['(: $p (A x) $tv)'], steps=300), [[]])

    def test_empirical_conditional_survives_without_a_hypothetical_path(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a1 (A x) (STV 1 0.9))',
            '(: b1 (B x) (STV 0.7 0.9))',
            '(: c1 (C x) (STV 1 0.9))',
            '(: (no_inverse r1) (Implication (C $v) (B $v)) (STV 0.8 0.9))',
        ])
        for repeat in range(2):
            with self.subTest(repeat=repeat):
                rows = h.query_many_refs([
                    '(: $p (Implication (A x) (B x)) $tv)',
                ], steps=300)[0]
                self.assertEqual(len(rows), 1, rows)
                self.assertEqual(h.expand_proof(rows[0].proof), '(implication-instance-fold cpu)')
                self.assertGreater(rows[0].tv[2], 0)

    def test_weak_assumption_path_excludes_strong_world_alternative(self):
        expected = None
        for world in (None, 0.9, 1.0):
            h = PeTTaChainer()
            h.add_atoms_no_check([
                '(: (no_inverse a_to_c) (Implication (A $v) (C $v)) (STV 0.8 0.05))',
                '(: (no_inverse c_to_b) (Implication (C $v) (B $v)) (STV 0.8 0.9))',
            ] + ([f'(: c1 (C x) (STV 1 {world}))'] if world is not None else []))
            for repeat in range(2):
                with self.subTest(world=world, repeat=repeat):
                    rows = h.query_many_refs([
                        '(: $p (Implication (A x) (B x)) $tv)',
                    ], steps=300)[0]
                    self.assertEqual(len(rows), 1, rows)
                    self.assertLess(rows[0].tv[2], 0.15)
                    if expected is None:
                        expected = rows[0].tv
                    self.assertAlmostEqual(rows[0].tv[1], expected[1])
                    self.assertAlmostEqual(rows[0].tv[2], expected[2])
                    proof = h.expand_proof(rows[0].proof)
                    for token in ('conditional-implication', 'a_to_c', 'c_to_b', '(ctx proof '):
                        self.assertIn(token, proof)
                    self.assertNotIn('c1', proof)
            self.assertEqual(h.query_many_refs(['(: $p (A x) $tv)'], steps=300), [[]])

    def test_conjunction_projection_cannot_launder_world_support(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: c1 (C x) (STV 1 0.9))',
            '(: (no_inverse c_to_b) (Implication (C $v) (B $v)) (STV 0.8 0.9))',
            # Build (And C A) from its parts, then project C. The projected
            # value depends on C itself and cannot support the C read by B.
            '(: (no_inverse join) (Implication (And (C $v) (A $v)) (And (C $v) (A $v))) (STV 1 1))',
        ])
        for repeat in range(2):
            with self.subTest(repeat=repeat):
                self.assertEqual(h.query_many_refs([
                    '(: $p (Implication (A x) (B x)) $tv)',
                ], steps=300)[0], [])
        self.assertEqual(h.query_many_refs(['(: $p (A x) $tv)'], steps=300), [[]])

    def test_world_facts_are_only_premises_in_assumption_dependent_chain(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: fixed (Recorded R) (STV 0.7 0.8))',
            '(: (no_inverse first) (Implication (And (Gate X) (Recorded R)) (Ready X)) (STV 1 0.9))',
            '(: (no_inverse second) (Implication (Ready X) (Outcome X)) (STV 1 0.9))',
        ])
        for _ in range(2):
            rows = h.query_many_refs([
                '(: $p (Implication (Gate X) (Recorded R)) $tv)',
                '(: $p (Implication (Gate X) (Outcome X)) $tv)',
            ], steps=300)
            self.assertEqual(rows[0], [])
            self.assertEqual(len(rows[1]), 1, rows)
            proof = h.expand_proof(rows[1][0].proof)
            for token in ('first', 'second', 'fixed', '(ctx proof '):
                self.assertIn(token, proof)
        self.assertEqual(h.query_many_refs([
            '(: $p (Gate X) $tv)', '(: $p (Ready X) $tv)', '(: $p (Outcome X) $tv)',
        ], steps=300), [[], [], []])

    def test_assumed_key_overrides_main_but_other_bindings_remain_visible(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: contradicted (Gate X) (STV 0 1))',
            '(: other (Gate Y) (STV 1 0.8))',
            '(: (no_inverse own) (Implication (Gate X) (Own X)) (STV 1 0.9))',
            '(: (no_inverse pair) (Implication (And (Gate X) (Gate $y)) (Pair X $y)) (STV 1 0.9))',
        ])
        for _ in range(2):
            rows = h.query_many_refs([
                '(: $p (Implication (Gate X) (Own X)) $tv)',
                '(: $p (Implication (Gate X) (Pair X Y)) $tv)',
            ], steps=300)
            self.assertAlmostEqual(rows[0][0].tv[1], 1)
            self.assertAlmostEqual(rows[1][0].tv[1], 1)
            self.assertNotIn('contradicted', h.expand_proof(rows[0][0].proof))
            self.assertIn('other', h.expand_proof(rows[1][0].proof))
        self.assertEqual(h.query_many_refs(['(: $p (Gate X) $tv)'], steps=300)[0][0].tv,
                         ['STV', 0, 1])

    def test_hypothetical_individual_cannot_be_bound_by_world_observation(self):
        for compound in (False, True):
            h = PeTTaChainer()
            fact = '(And (StockSplit Split1) (Recorded R))' if compound else '(StockSplit Split1)'
            h.add_atoms_no_check([
                f'(: world {fact} (STV 1 0.9))',
                '(: (no_inverse bridge) (Implication (And (StockSplit $e) (Implemented $e)) (PreservesOwnership $e)) (STV 1 0.9))',
            ])
            for _ in range(2):
                # This asks for a general individual, not the event witness of Exists.
                self.assertEqual(h.query_many_refs([
                    '(: $p (Implication (Implemented $e) (PreservesOwnership $e)) $tv)',
                ], steps=300)[0], [])

    def test_materialized_main_consequence_does_not_override_assumption(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: world_gate (Gate X) (STV 1 0.9))',
            '(: (no_inverse rule) (Implication (Gate X) (Effect X)) (CTV (STV 0.9 0.9) (STV 0.2 0.9)))',
        ])
        self.assertTrue(h.query_many_materialization(['(: $p (Effect X) $tv)'], steps=300)[0])
        for _ in range(2):
            rows = h.query_many_refs([
                '(: $p (Implication (Not (Gate X)) (Effect X)) $tv)',
            ], steps=300)[0]
            self.assertEqual(len(rows), 1, rows)
            self.assertAlmostEqual(rows[0].tv[1], 0.2)
            self.assertNotIn('world_gate', h.expand_proof(rows[0].proof))
        self.assertEqual(h.query_many_refs(['(: $p (Gate X) $tv)'], steps=300)[0][0].tv,
                         ['STV', 1, 0.9])

    def test_contra_world_consequent_never_revises_the_conditional(self):
        for negative in (False, True):
            for compound in (False, True):
                for world_strength in (0.1, 0.9):
                    with self.subTest(negative=negative, compound=compound, world=world_strength):
                        h = PeTTaChainer()
                        consequent = '(Not (Dilutes Split1))' if negative else '(PreservesOwnership Split1)'
                        rule_consequent = '(Not (Dilutes $e))' if negative else '(PreservesOwnership $e)'
                        observed = f'(And {consequent} (Recorded R))' if compound else consequent
                        h.add_atoms_no_check([
                            '(: src_split (StockSplit Split1) (STV 1 0.9))',
                            f'(: src_bridge (Implication (And (StockSplit $e) (Implemented $e)) {rule_consequent}) (STV 1 0.9))',
                            '(: world_implementation (Implemented Split1) (STV 0 1))',
                            f'(: world_consequence {observed} (STV {world_strength} 0.9))',
                        ])
                        for _ in range(2):
                            rows = h.query_many_refs([
                                f'(: $p (Implication (Implemented Split1) {consequent}) $tv)',
                            ], steps=300)[0]
                            self.assertEqual(len(rows), 1, rows)
                            self.assertAlmostEqual(rows[0].tv[1], 1.0)
                            proof = h.expand_proof(rows[0].proof)
                            for token in ('src_split', 'src_bridge', '(ctx proof '):
                                self.assertIn(token, proof)
                            self.assertNotIn('world_consequence', proof)
                            self.assertNotIn('world_implementation', proof)
                        self.assertEqual(h._call('collapse', [
                            f'(match &kb ($_type ((judgment-consequent {h.kb}) $_ctx $_vars) $_proof $_tv) leaked)',
                        ]), ['()'])
                        self.assertEqual(h.query_many_refs([
                            '(: $p (Implemented Split1) $tv)',
                        ], steps=300)[0][0].tv, ['STV', 0, 1])


if __name__ == '__main__':
    unittest.main()
