"""The Assuming examples of LLM_RULE_SPEC.md hold as documented (#130)."""
from pathlib import Path
import re
import unittest

import janus_swi as janus

from pettachainer import PeTTaChainer
from pettachainer.pln_validator import check_query

SPEC = Path(__file__).resolve().parents[1] / 'pettachainer' / 'LLM_RULE_SPEC.md'
KB = ['(: about (About Report1 Topic1) (STV 1.0 1.0))',
      '(: claim_rule (Implication (And (Accepted $r) (About $r $t)) (Claim $t)) (STV 0.9 0.9))',
      '(: covered (Implication (Claim $t) (Covered $t)) (STV 0.7 0.9))']

# Each supported example's answered goal and strength (None: not pinned).
SUPPORTED = {
    '(: $proof (Assuming (: premise (Accepted Report1) (STV 1.0 1.0)) (Claim Topic1)) $tv)': (['Claim', 'Topic1'], 0.9),
    '(: $proof (Assuming (Accepted Report1) (Claim Topic1)) $tv)': (['Claim', 'Topic1'], 0.9),
    '(: $proof (Assuming (: premise (Accepted Report1) (STV 0.8 0.9)) (Claim Topic1)) $tv)': (['Claim', 'Topic1'], 0.82),
    '(: $proof (Assuming (: premise (Not (Accepted Report1)) (STV 0.9 0.9)) (Claim Topic1)) $tv)': (['Claim', 'Topic1'], 0.54),
    '(: $proof (Assuming (And (: premise (Accepted Report2) (STV 0.8 0.9)) (About Report2 Topic2)) (Claim Topic2)) $tv)': (['Claim', 'Topic2'], 0.82),
    '(: $proof (Assuming (Accepted Report1) (Claim $topic)) $tv)': (['Claim', 'Topic1'], 0.9),
    '(: $proof (Assuming (And (Accepted Report1) (: bridge (Implication (Claim $t) (Newsworthy $t)) (STV 0.6 0.8))) (Newsworthy $t)) $tv)': (['Newsworthy', 'Topic1'], None),
    '(: $proof (Assuming (And (Accepted Report1) (: bridge (Implication (Claim $t) (Newsworthy $t)) (CTV (STV 0.6 0.8) (STV 0.1 0.8)))) (Newsworthy Topic1)) $tv)': (['Newsworthy', 'Topic1'], None),
    '(: $proof (Assuming (And (Accepted Report1) (Implication (Claim $t) (Newsworthy $t))) (Newsworthy Topic1)) $tv)': (['Newsworthy', 'Topic1'], None),
    '(: $proof (Assuming (Accepted Report1) (Covered Topic1)) $tv)': (['Covered', 'Topic1'], None),
    '(: $proof (Assuming (Accepted Report1) (Implication (Claim $t) (Covered $t))) $tv)': (None, 0.7),
}
# Each excluded example's error, or None for no answer.
EXCLUDED = {
    '(: $proof (Assuming (: bridge (Implication (Claim $t) (Newsworthy $t)) (STV 0.6 0.8)) (Implication (Claim $t) (Newsworthy $t))) $tv)': None,
    '(: $proof (Assuming ((Accepted Report1) (About Report1 Topic1)) (Claim Topic1)) $tv)': None,
    '(: $proof (Assuming (Accepted Report1) (Assuming (Accepted Report2) (Claim Topic1))) $tv)': 'nested_assuming',
    '(: $proof (Assuming (Accepted Report1)) $tv)': 'assuming_arguments',
    '(: $proof (Assuming (: premise (Accepted Report1) (CTV (STV 1 1) (STV 0 1))) (Claim Topic1)) $tv)': 'weighted_assumption',
    '(: $proof (Assuming (Implication (Claim $t) (Implication (Hot $t) (Newsworthy $t))) (Newsworthy Topic1)) $tv)': 'assumed_rule',
    '(: $proof (Assuming (Implication (Claim $t) (Exists ($x) (Covers $x $t))) (Claim Topic1)) $tv)': 'assumed_rule',
}


def spec_examples():
    text = SPEC.read_text()
    section = text[text.index('## Assuming Queries'):]
    section = section[:section.index('\n## ', 1)]
    return [line for line in section.splitlines() if re.match(r'\(: \$proof \(Assuming ', line)]


def answers(query):
    handler = PeTTaChainer()
    handler.add_atoms_no_check(KB)
    return handler.query_many_refs([query], steps=300)[0]


class LlmSpecAssumingTests(unittest.TestCase):
    def test_every_documented_example_is_pinned(self):
        examples = spec_examples()
        self.assertEqual(len(examples), len(set(examples)))
        self.assertEqual(set(examples), set(SUPPORTED) | set(EXCLUDED))

    def test_examples_pass_the_syntax_validator(self):
        for query in spec_examples():
            with self.subTest(query=query):
                self.assertEqual(check_query(query), 1.0)
        self.assertEqual(check_query('(Assuming (Accepted Report1) (Claim Topic1))'), 0.0)

    def test_supported_examples_answer(self):
        for query, (goal, strength) in SUPPORTED.items():
            with self.subTest(query=query):
                rows = answers(query)
                self.assertEqual(len(rows), 1, rows)
                self.assertEqual(rows[0].statement[0], 'Assuming')
                if goal is not None:
                    self.assertEqual(rows[0].statement[2], goal)
                if strength is not None:
                    self.assertAlmostEqual(rows[0].tv[1], strength)

    def test_excluded_examples_are_rejected_or_unanswered(self):
        for query, error in EXCLUDED.items():
            with self.subTest(query=query):
                if error is None:
                    self.assertEqual(answers(query), [])
                else:
                    with self.assertRaisesRegex(janus.PrologError, error):
                        answers(query)


if __name__ == '__main__':
    unittest.main()
