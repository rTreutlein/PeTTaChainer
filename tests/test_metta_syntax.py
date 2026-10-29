import unittest

from pettachainer.metta_syntax import parse_source, parse_term, render


class MettaSyntaxTests(unittest.TestCase):
    def test_inert_roundtrip_preserves_tokens(self):
        for text in ['(A "two words" (B $x))', '(A "escaped \\" quote")',
                     '(STV 1.0e-7 0.9)', '()', '$open', 'symbol']:
            self.assertEqual(render(parse_term(text)), text)
        self.assertEqual(parse_source('(A) ; ignored\n (B ";data")'),
                         [['A'], ['B', '";data"']])

    def test_single_term_rejects_malformed_and_multiple_terms(self):
        for text in ['(', ')', 'A B', '', '"unfinished']:
            with self.assertRaises(RuntimeError):
                parse_term(text)
        self.assertIsNone(parse_source('(A'))

    def test_native_numbers_render_as_petta_source(self):
        self.assertEqual(render(['STV', 1e-7, 1]), '(STV 1.0e-07 1)')
