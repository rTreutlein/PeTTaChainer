import unittest

from pettachainer import check_query, check_stmt


class TestPlnValidator(unittest.TestCase):
    def test_check_stmt_accepts_inner_stv(self):
        self.assertEqual(check_stmt("(: s1 (Dog fido) (STV 1.0 1.0))"), 1.0)

    def test_check_stmt_accepts_distribution_tv(self):
        self.assertEqual(
            check_stmt("(: s2 (HeightDist g1 alice) (PointMass 170.0))"),
            1.0,
        )

    def test_check_stmt_accepts_natdist_tv(self):
        self.assertEqual(
            check_stmt("(: s3 (CountDist g1) (NatDist ((0 0.5) (1 0.5))))"),
            1.0,
        )

    def test_check_stmt_accepts_particledist_with_scale(self):
        self.assertEqual(
            check_stmt("(: s4 (CountDist g1) (ParticleDist 0 1.0))"),
            1.0,
        )

    def test_check_stmt_rejects_variable_proof(self):
        self.assertEqual(check_stmt("(: $prf (Dog fido) (STV 1.0 1.0))"), 0.0)

    def test_check_stmt_rejects_unsupported_tv(self):
        self.assertEqual(check_stmt("(: s5 (Dog fido) (CustomTV 0.9))"), 0.0)

    def test_check_query_accepts_inner_form(self):
        self.assertEqual(check_query("(: $prf (Dog fido) $tv)"), 1.0)

    def test_check_query_rejects_non_variable_proof(self):
        self.assertEqual(check_query("(: proof1 (Dog fido) $tv)"), 0.0)

    def test_rejects_wrapped_or_malformed_content(self):
        self.assertEqual(check_stmt("!(compileadd kb (Dog fido))"), 0.0)
        self.assertEqual(check_query("!(query 10 kb (Dog fido))"), 0.0)
        self.assertEqual(check_stmt("!(compileadd kb (: s2 (Dog fido) (STV 1.0 1.0)))"), 0.0)
        self.assertEqual(check_query("!(query 10 kb (: $prf (Dog fido) $tv))"), 0.0)


if __name__ == "__main__":
    unittest.main()
