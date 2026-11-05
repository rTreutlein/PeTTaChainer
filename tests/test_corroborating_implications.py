"""Tracker #92: merged derived implications remain executable rule values."""
import itertools
import unittest

from pettachainer import PeTTaChainer


# Independent replay of the documented Beta variance and evidence-count rules.
# No expected TV is copied from a query result. All cases use the default k=800.
K = 800


# A confidence of 1 is a point mass: no finite count, variance 0.
def count(confidence):
    return K * confidence / (1 - confidence)


def variance(strength, confidence):
    if confidence <= 0:
        return 1 / 12
    if confidence >= 1:
        return 0.0
    s = min(.999999, max(.000001, strength))
    return s * (1 - s) / (count(confidence) + 1)


def modus_ponens(antecedent, positive, negative=(.5, 0)):
    a, ac = antecedent
    p, pc = positive
    n, nc = negative
    s = a * p + (1 - a) * n
    va, vp, vn = variance(a, ac), variance(p, pc), variance(n, nc)
    v = a*a*vp + (1-a)**2*vn + (p-n)**2*va + va*(vp+vn)
    if v <= 0:
        return s, 1.0
    clipped = min(.999999, max(.000001, s))
    maxvar = clipped * (1 - clipped)
    observations = maxvar / min(v, maxvar) - 1
    return s, max(.000001, observations / (observations + K))


def node_stv(strength, var):
    if var <= 0:
        return strength, 1.0
    clipped = max(.000001, min(.999999, strength))
    maxvar = clipped * (1 - clipped)
    observations = maxvar / min(var, maxvar) - 1
    return strength, max(.000001, observations / (observations + K))


def jeffrey_part(prediction, siblings=2):
    # A predicted (And part ...) moves a part with no value of its own from the
    # uniform prior by probability kinematics (LANGUAGE_SPEC.md, "What a
    # compound's value says about its parts"), its siblings uniform too:
    # P(K | part) = E[sibling]^n, P(K | not part) = 0.
    ps, pc = prediction
    f1 = .5 ** siblings
    v1 = (1 / 3) ** siblings - f1 * f1
    p, vp, f0, v0 = .5, 1 / 12, 0.0, 0.0
    # The exact variance of p f1 + (1 - p) f0 over independent p, f1, f0.
    parts_var = (f1 - f0) ** 2 * vp + (p * p + vp) * v1 + ((1 - p) ** 2 + vp) * v0

    def posterior(p, f1, f0, ps):
        pp = p * f1 + (1 - p) * f0
        n_parts = max(0.0, pp * (1 - pp) / parts_var - 1)
        pstar = ps if pc >= 1 else (n_parts * pp + count(pc) * ps) / (n_parts + count(pc))
        return pstar * p * f1 / pp + (1 - pstar) * p * (1 - f1) / (1 - pp)

    inputs = [(p, vp), (f1, v1), (f0, v0), (ps, variance(ps, pc))]
    strength = posterior(p, f1, f0, ps)
    var = 0.0
    for i, (x, vx) in enumerate(inputs):
        up, down = min(1.0, x + 1e-6), max(0.0, x - 1e-6)
        args_up = [v for v, _ in inputs]
        args_down = list(args_up)
        args_up[i], args_down[i] = up, down
        slope = (posterior(*args_up) - posterior(*args_down)) / (up - down)
        var += slope * slope * vx
    return node_stv(strength, var)


def revise(values):
    points = [s for s, c in values if c >= 1]
    if points:
        return sum(points) / len(points), 1.0
    weights = [count(c) for _, c in values]
    total = sum(weights)
    return sum(s*n for (s, _), n in zip(values, weights)) / total, total / (total + K)


class CorroboratingImplicationTests(unittest.TestCase):
    def answer(self, h, statement, expected, sources, steps=600):
        rows = h.query_many_refs([f'(: $p {statement} $tv)'], steps=steps)[0]
        self.assertEqual(len(rows), 1, rows)
        self.assertEqual(rows[0].tv[0], 'STV')
        for actual, wanted in zip(rows[0].tv[1:], expected):
            self.assertAlmostEqual(actual, wanted, places=10)
        proof = h.expand_proof(rows[0].proof)
        for source in sources:
            self.assertIn(source, proof)
        self.assertNotIn('derived-implication', proof)
        return rows[0]

    def test_source_counts_polarities_and_worlds(self):
        # Includes both one-source baselines, two corroborating sources, a
        # three-source family, and both reproducer budgets. A gated compound
        # event, a prediction, moves its part by Jeffrey without counting its
        # source three times.
        for sources in (('R3',), ('R1',), ('R3', 'R1'), ('R3', 'R1', 'R2')):
            for negative, world, compound in itertools.product((False, True), repeat=3):
                with self.subTest(sources=sources, negative=negative, world=world, compound=compound):
                    h = PeTTaChainer()
                    h.set_evidence_confidence_k(K)
                    consequent = '(Not (Dilutes $e))' if negative else '(KeepsOwnership $e)'
                    target = consequent.replace('$e', 'Event3')
                    event_tv = (1, .9)
                    if compound:
                        h.add_atom('(: ev3 (Implication (AcceptSource R3) '
                                   '(And (AnnouncedBy Event3 C3) (AnnouncedIn Event3 R3) '
                                   '(Member Event3 StockSplit))) (STV 1 0.9))')
                        event_tv = jeffrey_part(modus_ponens((1, 1), event_tv))
                    else:
                        h.add_atom('(: event (Member Event3 StockSplit) (STV 1 0.9))')
                    accepted = tuple(dict.fromkeys(('R3', 'R1', *sources)))
                    if world:
                        h.add_atoms_no_check([f'(: accept-{s} (AcceptSource {s}) (STV 1 1))' for s in accepted])
                        statement = target
                    else:
                        gates = ' '.join(f'(AcceptSource {s})' for s in accepted)
                        statement = f'(Assuming (And {gates}) {target})'
                    h.add_atoms_no_check([
                        f'(: rule-{s} (Implication (AcceptSource {s}) '
                        f'(Implication (Member $e StockSplit) {consequent})) (STV 1 0.9))'
                        for s in sources
                    ])
                    rule_tv = revise([modus_ponens((1, 1), (1, .9)) for _ in sources])
                    expected = modus_ponens(event_tv, rule_tv)
                    self.answer(h, statement, expected, [f'rule-{s}' for s in sources])
                    # Reusing the skeleton must preserve the same evidence.
                    self.answer(h, statement, expected, [f'rule-{s}' for s in sources], steps=5000)
                    if not world:
                        self.assertEqual(h.query_many_refs([f'(: $p {target} $tv)'], steps=600)[0], [])

    def test_ungated_duplicates(self):
        for size in (1, 2, 3):
            with self.subTest(size=size):
                h = PeTTaChainer()
                h.add_atom('(: event (Member Event3 StockSplit) (STV 1 0.9))')
                h.add_atoms_no_check([
                    f'(: rule-{i} (Implication (Member $e StockSplit) (KeepsOwnership $e)) '
                    '(CTV (STV 1 0.9) (STV 0.5 0)))' for i in range(size)
                ])
                # Conditioned on the shared Member observation, the rules
                # revise; the observation is read once.
                residual = (1, .9) if size == 1 else modus_ponens((1, 1), (1, .9))
                expected = modus_ponens((1, .9), revise([residual] * size))
                self.answer(h, '(KeepsOwnership Event3)', expected, [f'rule-{i}' for i in range(size)])

    def test_ungated_stv_reproducer(self):
        # STV rules over the shared Member observation are same-condition
        # estimates: the merge conditions on Member, so they revise.
        for size in (1, 2, 3):
            with self.subTest(size=size):
                residual = (1, .9) if size == 1 else modus_ponens((1, 1), (1, .9))
                expected = modus_ponens((1, .9), revise([residual] * size))
                h = PeTTaChainer()
                h.add_atom('(: event (Member Event3 StockSplit) (STV 1 0.9))')
                h.add_atoms_no_check([
                    f'(: rule-{i} (Implication (Member $e StockSplit) (KeepsOwnership $e)) '
                    '(STV 1 0.9))' for i in range(size)
                ])
                self.answer(h, '(KeepsOwnership Event3)', expected, ['rule-'])

    def test_late_corroboration_and_only_one_accepted_source(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: event (Member Event3 StockSplit) (STV 1 0.9))',
            '(: accept-R3 (AcceptSource R3) (STV 1 1))',
            '(: rule-R3 (Implication (AcceptSource R3) '
            '(Implication (Member $e StockSplit) (KeepsOwnership $e))) (STV 1 0.9))',
        ])
        one = modus_ponens((1, 1), (1, .9))
        self.answer(h, '(KeepsOwnership Event3)', modus_ponens((1, .9), one), ['rule-R3'])
        h.add_atom('(: rule-R1 (Implication (AcceptSource R1) '
                   '(Implication (Member $e StockSplit) (KeepsOwnership $e))) (STV 1 0.9))')
        self.answer(h, '(KeepsOwnership Event3)', modus_ponens((1, .9), one), ['rule-R3'])
        h.add_atom('(: accept-R1 (AcceptSource R1) (STV 1 1))')
        self.answer(h, '(KeepsOwnership Event3)', modus_ponens((1, .9), revise([one, one])), ['rule-R3', 'rule-R1'])

    def test_shared_uncertain_gate_is_not_independent_evidence(self):
        # One uncertain source gate is shared by every application. The CTV
        # overlap path retains its representative rather than adding counts.
        gate, positive, negative = (1, .8), (.8, .9), (.1, .9)
        expected = modus_ponens((1, .9), modus_ponens(gate, positive, negative), negative)
        for size in (1, 2, 3):
            with self.subTest(size=size):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: event (B x) (STV 1 0.9))',
                    '(: gate (A x) (STV 1 0.8))',
                ] + [
                    f'(: rule-{i} (Implication (A $x) (Implication (B $x) (T $x))) '
                    '(CTV (STV 0.8 0.9) (STV 0.1 0.9)))' for i in range(size)
                ])
                self.answer(h, '(T x)', expected, ['rule-'])

    def test_pooled_source_conditions_keep_general_rule_as_prior(self):
        h = PeTTaChainer()
        h.set_bayes_prior_count(.2)
        h.add_atoms_no_check([
            '(: a (A x) (STV 1 1))',
            '(: b (B x) (STV 1 1))',
            '(: c (C x) (STV 1 1))',
            '(: general (Implication (B $x) (T $x)) '
            '(CTV (STV 0.2 0.8) (STV 0.1 0.8)))',
            '(: source-a (Implication (A $x) (Implication (B $x) (T $x))) '
            '(CTV (STV 0.8 0.8) (STV 0.1 0.8)))',
            '(: source-c (Implication (C $x) (Implication (B $x) (T $x))) '
            '(CTV (STV 0.6 0.8) (STV 0.1 0.8)))',
        ])
        negative = (.1, .8)
        pooled = revise([modus_ponens((1, 1), p, negative) for p in ((.8, .8), (.6, .8))])
        # Both source statements carry the same finite negative branch. Its
        # independent stated evidence revises, like their positive branches.
        raw = modus_ponens((1, 1), pooled, revise([negative, negative]))
        general = modus_ponens((1, 1), (.2, .8), negative)
        weight = max(0, 1 / (1 / (count(general[1]) + 1) + 1 / 1.2) - 1)
        expected = ((raw[0]*count(raw[1]) + weight*general[0]) / (count(raw[1]) + weight), raw[1])
        answer = self.answer(h, '(T x)', expected, ['source-a', 'source-c', 'general'])
        self.assertIn('specializes', h.expand_proof(answer.proof))


if __name__ == '__main__':
    unittest.main()
