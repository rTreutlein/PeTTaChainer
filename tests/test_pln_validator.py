import unittest

from pettachainer import check_query, check_stmt


class TestPlnValidator(unittest.TestCase):
    def test_check_stmt_accepts_supported_forms(self):
        for stmt in (
            "(: s1 (Dog fido) (STV 1.0 1.0))",
            "(: s2 (HeightDist g1 alice) (PointMass 170.0))",
            "(: s3 (CountDist g1) (NatDist ((0 0.5) (1 0.5))))",
            "(: s4 (CountDist g1) (ParticleDist 0 1.0))",
        ):
            with self.subTest(stmt=stmt):
                self.assertEqual(check_stmt(stmt), 1.0)

    def test_check_stmt_rejects_invalid_forms(self):
        for stmt in (
            "(: $prf (Dog fido) (STV 1.0 1.0))",
            "(: s5 (Dog fido) (CustomTV 0.9))",
            "!(compileadd kb (Dog fido))",
            "!(compileadd kb (: s2 (Dog fido) (STV 1.0 1.0)))",
        ):
            with self.subTest(stmt=stmt):
                self.assertEqual(check_stmt(stmt), 0.0)

    def test_check_query_accepts_inner_form(self):
        self.assertEqual(check_query("(: $prf (Dog fido) $tv)"), 1.0)

    def test_check_query_rejects_invalid_forms(self):
        for query in (
            "(: proof1 (Dog fido) $tv)",
            "!(query 10 kb (Dog fido))",
            "!(query 10 kb (: $prf (Dog fido) $tv))",
        ):
            with self.subTest(query=query):
                self.assertEqual(check_query(query), 0.0)


if __name__ == "__main__":
    unittest.main()
