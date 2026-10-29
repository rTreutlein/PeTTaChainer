"""Calibration oracles for the probes P1-P12 and P15-P17 (bench/results/fresh-design/distributional-tv.md).

A probe is a small Boolean network on one instance `a`:
  atoms : instance atoms, in topological order
  roots : atom -> (s, c)                           a stored ground fact on a root atom
  rules : child -> (parent, (s1, c1), (s0, c0))    a CTV rule P(child | parent), P(child | not parent)
  comps : [(statement, fn(world) -> bool, s, c)]   stored ground compounds
  goals : statement -> fn(world) -> bool
A world maps each atom to a bool numpy array of any shape.

Event oracle (the STV reading of ground statements): ground atoms and compounds are crisp
events. The parameters theta are the root facts' strengths and the rules' branches, each
Beta(n s + 1, n (1 - s) + 1) with n = k c / (1 - c), its counts on the uniform prior (a point at
c = 1 or from 2^40 observations); a parameter at c = 0 is the prior Beta(1, 1). A stored compound is Pearl
virtual evidence (m, 1 - m) on its statement, m = (n s + 1) / (n + 2) its predictive probability
under its own counts: its strength's uncertainty is marginalised into m, so a compound at c = 0
(m = 1/2) is no evidence, exactly as if it were left out, and one at c = 1 is lambda = (s, 1 - s);
each factor is read relative to its larger value, so neutral ones are exactly 1 and many of them
never underflow. For one theta
the goal's probability g(theta) is exact enumeration over the instance's worlds; the posterior over
theta is prior x Z(theta). The goal's TV is s = E[g], c = ideal-conf-from-var(s, Var[g]), by tensor
Gauss-Jacobi quadrature: each parameter's nodes and weights are those of its own Beta, exact for
the polynomial integrands of a network without compounds at any shape, however far below 1.

Count oracle (the FTV reading): every stored (s, c), c < 1, is n s / n (1 - s) pseudo-observations
on the statement's probability P_theta under the uniform prior, so one fact alone is
Beta(n s + 1, n (1 - s) + 1), as in the event oracle; quadrature in logit space around the posterior mode,
with the exact posterior / proposal ratio as weight.

Both are the prototype's oracles (oracles.py and compound-projection-proto/oracle.py there), with
numpy only: the Beta quantile is Numerical Recipes' inversion of the incomplete beta function, and
the count oracle's mode is a Newton search in place of scipy's BFGS.
"""
import itertools
import math

import numpy as np
from numpy.polynomial.hermite_e import hermegauss

K = 800.0                                   # evidence-confidence-k
A, B, C = 0.7, 0.6, 0.5
# (fact, compound, rule) confidence: high, low and extreme compound evidence, then weak
# evidence: a compound at c 0 and .1, and facts at c 0, .1 and .5.
SETTINGS = {'H': (0.9, 0.9, 0.9), 'L': (0.9, 0.5, 0.9), 'X': (0.9, 0.99, 0.9),
            'K0': (0.9, 0.0, 0.9), 'K1': (0.9, 0.1, 0.9),
            'F0': (0.0, 0.9, 0.9), 'F1': (0.1, 0.9, 0.9), 'F5': (0.5, 0.9, 0.9)}


def count(c):
    return math.inf if c >= 1 else K * c / (1.0 - c)


def predictive(s, c):
    """A compound's virtual-evidence strength m = (n s + 1) / (n + 2)."""
    return s if c >= 1 else (count(c) * s + 1) / (count(c) + 2)


def beta_ab(s, c):
    """A stored (s, c)'s Beta(n s + 1, n (1 - s) + 1): its counts on the uniform prior."""
    n = count(c)
    return n * s + 1.0, n * (1.0 - s) + 1.0


def point_value(s, c):
    """The point a parameter is when certain or of 2^40 observations or more, else None."""
    if c >= 1:
        return s
    return (count(c) * s + 1) / (count(c) + 2) if count(c) >= 2 ** 40 else None


def conf_from_var(s, v):
    """ideal-conf-from-var."""
    if v <= 0:
        return 0.9999
    cs = min(max(s, 1e-6), 1 - 1e-6)
    mv = cs * (1 - cs)
    nb = mv / min(v, mv) - 1.0
    return max(1e-6, nb / (nb + K))


def sd_from_conf(s, c):
    """ideal-var's sd: the spread an (s, c) claims."""
    cs = min(max(s, 1e-6), 1 - 1e-6)
    return math.sqrt(cs * (1 - cs) / (count(c) + 1.0))


def z_score(s, c, oracle):
    """|s - s*| in units of the sd the answer claims (a certain answer: 0 if exact)."""
    d, sd = abs(s - oracle['s']), sd_from_conf(s, c)
    return d / sd if sd > 0 else 0.0 if d == 0 else math.inf


def variance_ratio(s, c, oracle):
    """The variance the answer claims over the oracle's."""
    return sd_from_conf(s, c) ** 2 / oracle['var']


# ---- the Beta quantile --------------------------------------------------------

def _stirling_delta(z):
    if z >= 10:
        z2 = z * z
        return (1 / 12 - (1 / 360 - (1 / 1260 - 1 / (1680 * z2)) / z2) / z2) / z
    return math.lgamma(z) - (z - 0.5) * math.log(z) + z - 0.5 * math.log(2 * math.pi)


def _log_front(a, b, x):
    """log(x^a (1-x)^b / B(a, b)) around the mean, without the lgamma cancellation."""
    mu, nu = a / (a + b), b / (a + b)        # nu as such: 1 - mu loses digits near 1
    # near the mean through log1p, in the tails directly, where the centred ratio rounds
    l1 = math.log1p((x - mu) / mu) if abs(x - mu) < 0.5 * mu else math.log(x) - math.log(mu)
    l2 = math.log1p((mu - x) / nu) if abs(x - mu) < 0.5 * nu else math.log1p(-x) - math.log(nu)
    return (a * l1 + b * l2
            + 0.5 * math.log(a * b / (a + b)) - 0.5 * math.log(2 * math.pi)
            - _stirling_delta(a) - _stirling_delta(b) + _stirling_delta(a + b))


def _fraction(a, b, x):
    tiny = 1e-300
    guard = lambda v: v if abs(v) > tiny else tiny
    c, d = 1.0, 1.0 / guard(1.0 - (a + b) * x / (a + 1.0))
    h = d
    for m in range(1, 100000):
        for aa in (m * (b - m) * x / ((a - 1 + 2 * m) * (a + 2 * m)),
                   -(a + m) * (a + b + m) * x / ((a + 2 * m) * (a + 1 + 2 * m))):
            d = 1.0 / guard(1.0 + aa * d)
            c = guard(1.0 + aa / c)
            h *= d * c
        if abs(d * c - 1.0) < 1e-16:
            break
    return h


def _log_density(a, b, x):
    return _log_front(a, b, x) - math.log(x) - math.log1p(-x)


def beta_log_tails(a, b, x):
    """log I_x(a, b) and log(1 - I_x(a, b)): the continued fraction gives the one on its
    convergent side, the other is its complement, the larger of the two."""
    if x <= 0:
        return -math.inf, 0.0
    if x >= 1:
        return 0.0, -math.inf
    if x < (a + 1) / (a + b + 2):
        lo = _log_front(a, b, x) + math.log(_fraction(a, b, x) / a)
        return lo, math.log1p(-min(math.exp(lo), 1 - 2 ** -53))
    up = _log_front(a, b, x) + math.log(_fraction(b, a, 1 - x) / b)
    return math.log1p(-min(math.exp(up), 1 - 2 ** -53)), up


def beta_ppf(u, a, b):
    """The Beta(a, b) quantile for a, b > 0: Newton steps in the logit of x, safeguarded by
    bisection, on the log of the tail its level lies in (I_x = u below 1/2, 1 - I_x = 1 - u
    above), so that the level and x keep their digits. The level solved is kept at 1e-300
    or more; a guess at a bound of the doubles is no guess (the solve starts at x = 1/2)."""
    if a >= 1 and b >= 1:
        t = math.sqrt(-2 * math.log(max(min(u, 1 - u), 1e-300)))
        g = (2.30753 + t * 0.27061) / (1 + t * (0.99229 + t * 0.04481))
        z = t - g if u < 0.5 else g - t
        al = (z * z - 3) / 6
        h = 2 / (1 / (2 * a - 1) + 1 / (2 * b - 1))
        w = z * math.sqrt(al + h) / h - (1 / (2 * b - 1) - 1 / (2 * a - 1)) * (al + 5 / 6 - 2 / (3 * h))
        L = 2 * w + math.log(b) - math.log(a)            # x0 = a / (a + b e^2w) = 1 / (1 + e^L)
        x = math.exp(-L) / (1 + math.exp(-L)) if L > 0 else 1 / (1 + math.exp(L))
    else:                                                # the tails' power laws
        ta = math.exp(a * math.log(a / (a + b))) / a
        tb = math.exp(b * math.log(b / (a + b))) / b
        if u < ta / (ta + tb):
            x = math.exp(math.log(a * (ta + tb) * max(u, 1e-300)) / a)
        else:
            x = 1 - math.exp(math.log(b * (ta + tb) * max(1 - u, 1e-300)) / b)
    upper = u > 0.5
    lv = math.log(max(1 - u if upper else u, 1e-300))
    lam = max(-744.0, min(744.0, math.log(x) - math.log1p(-x))) if 0 < x < 1 else 0.0
    lo, hi = -745.0, 745.0
    logit_x = lambda l: math.exp(l) / (1 + math.exp(l)) if l < 0 else 1 / (1 + math.exp(-l))
    for _ in range(200):
        x = logit_x(lam)
        lt = beta_log_tails(a, b, x)[upper]
        r = lt - lv
        if r == 0:
            break
        if (r < 0) != upper:                    # below the root: x must grow
            lo = lam
        else:
            hi = lam
        nxt = None
        if lt > -math.inf and 0 < x < 1:
            d = r * math.exp(min(lt - _log_density(a, b, x) - math.log(x) - math.log1p(-x), 700))
            nxt = lam + d if upper else lam - d
        nxt = nxt if nxt is not None and lo < nxt < hi else (lo + hi) / 2
        done = abs(nxt - lam) <= 1e-15 * max(1.0, abs(lam))
        lam = nxt
        if done:
            break
    return logit_x(lam)


# ---- probes ---------------------------------------------------------------------

def probes(cf, cc, rc):
    """P1-P12, P15 (shared parent), P16 (chained observations) and P17 (overlapping part evidence) at fact, compound and rule confidence cf, cc, rc."""
    a = lambda w: w['A']
    b = lambda w: w['B']
    c = lambda w: w['C']
    OR = lambda w: w['A'] | w['B']
    P = {}
    P['P1'] = dict(atoms=['A', 'B'], roots={'A': (A, cf), 'B': (B, cf)}, rules={},
                   comps=[('(Or (A a) (B a))', OR, 1.0, cc)], goals={'(A a)': a})
    P['P2'] = dict(P['P1'], goals={'(And (A a) (B a))': lambda w: w['A'] & w['B']})
    P['P3'] = dict(atoms=['A', 'B'], roots={'A': (A, cf)}, rules={'B': ('A', (0.9, rc), (0.2, rc))},
                   comps=[('(Or (A a) (B a))', OR, 1.0, cc)], goals={'(A a)': a, '(B a)': b})
    P['P4'] = dict(atoms=['C', 'A', 'B'], roots={'C': (C, cf)},
                   rules={'A': ('C', (0.8, rc), (0.3, rc)), 'B': ('C', (0.7, rc), (0.2, rc))},
                   comps=[('(Or (A a) (B a))', OR, 1.0, cc)], goals={'(A a)': a, '(C a)': c})
    r3 = {'A': (A, cf), 'B': (B, cf), 'C': (C, cf)}
    abc = {'(A a)': a, '(B a)': b, '(C a)': c}
    P['P5'] = dict(atoms=['A', 'B', 'C'], roots=r3, rules={},
                   comps=[('(And (Or (A a) (B a)) (Or (A a) (C a)))',
                           lambda w: (w['A'] | w['B']) & (w['A'] | w['C']), 1.0, cc)], goals=abc)
    P['P6'] = dict(atoms=['A', 'B', 'C'], roots=r3, rules={},
                   comps=[('(Or (And (A a) (B a)) (C a))', lambda w: (w['A'] & w['B']) | w['C'], 1.0, cc)],
                   goals=abc)
    P['P7'] = dict(atoms=['A', 'B'], roots={'A': (A, cf), 'B': (B, cf)}, rules={},
                   comps=[('(Not (And (A a) (B a)))', lambda w: ~(w['A'] & w['B']), 1.0, cc)],
                   goals={'(A a)': a, '(B a)': b})
    P['P8'] = dict(atoms=['A', 'B', 'K'], roots={'A': (A, cf), 'B': (B, cf)},
                   rules={'K': ('A', (0.9, rc), (0.2, rc))},
                   comps=[('(Or (A a) (B a))', OR, 1.0, cc)], goals={'(K a)': lambda w: w['K']})
    P['P9'] = dict(P['P1'], goals={'(A a)': a, '(And (A a) (B a))': lambda w: w['A'] & w['B']})
    P['P10'] = dict(atoms=['C', 'A', 'B'], roots={'C': (C, cf), 'B': (B, cf)},
                    rules={'A': ('C', (0.9, rc), (0.1, rc))},
                    comps=[('(Or (A a) (B a))', OR, 1.0, cc)],
                    goals={'(C a)': c, '(And (C a) (A a))': lambda w: w['C'] & w['A']})
    P['P11'] = dict(P['P1'], comps=[('(Or (A a) (B a))', OR, 0.5, cc)])
    P['P12'] = dict(atoms=['A', 'B', 'C'], roots=r3, rules={},
                    comps=[('(Or (A a) (B a))', OR, 1.0, cc),
                           ('(Or (A a) (C a))', lambda w: w['A'] | w['C'], 1.0, cc)], goals=abc)
    # P15: two children of one parent (X = R, Y = R up to .95/.05), no evidence: answers that
    # ignore the shared parent are wrong by up to 1/2 (XOR: about .1 against .5 when independent).
    xr = ('R', (0.95, rc), (0.05, rc))
    P['P15'] = dict(atoms=['R', 'X', 'Y'], roots={'R': (0.5, cf)}, rules={'X': xr, 'Y': xr}, comps=[],
                    goals={'(Or (And (X a) (Not (Y a))) (And (Not (X a)) (Y a)))': lambda w: w['X'] ^ w['Y'],
                           '(And (X a) (Y a))': lambda w: w['X'] & w['Y']})
    # P16: a chain A -> B -> C with two observations, of B and of C (Pearl, .75): their joint
    # weight is not the product of their separate predictive weights, since B and C are dependent.
    P['P16'] = dict(atoms=['A', 'B', 'C'], roots={'A': (0.5, cf)},
                    rules={'B': ('A', (0.95, rc), (0.05, rc)), 'C': ('B', (0.95, rc), (0.05, rc))},
                    comps=[('(B a)', b, 0.75, cc), ('(C a)', c, 0.75, cc)], goals={'(A a)': a})
    # P17: a compound whose parts' evidence overlaps: (And A X) reads fa, fb and (And Y C) reads
    # fb, fc, X and Y both children of B; the shared fb must count once.
    P['P17'] = dict(atoms=['A', 'B', 'C', 'X', 'Y'], roots=r3,
                    rules={'X': ('B', (0.9, rc), (0.2, rc)), 'Y': ('B', (0.8, rc), (0.3, rc))},
                    comps=[('(Or (And (A a) (X a)) (And (Y a) (C a)))',
                            lambda w: (w['A'] & w['X']) | (w['Y'] & w['C']), 1.0, cc)],
                    goals={'(A a)': a, '(B a)': b})
    return P


def params(m):
    """Parameter names -> (s, c): root strengths and rule branches. A compound is no
    parameter: evidence on the others (event) or a likelihood on a function of them (count)."""
    out = {'f_' + r: sc for r, sc in m['roots'].items()}
    for ch, (_p, b1, b0) in m['rules'].items():
        out[ch + '|1'], out[ch + '|0'] = b1, b0
    return out


def enumerate_stats(m, th, event):
    """Z, {goal: sum of goal(w) W(w)}, [P(compound) without the compounds' own factors].
    Under the event reading the world weights are summed in logs, relative to the largest,
    so evidence of any length neither underflows nor loses a world it leaves the only one."""
    lam = [(math.log(m_ / max(m_, 1 - m_)) if m_ > 0 else -math.inf,          # relative to the larger:
            math.log((1 - m_) / max(m_, 1 - m_)) if m_ < 1 else -math.inf)   # a neutral factor is (0, 0)
           for m_ in (predictive(s, c) for _n, _f, s, c in m['comps'])]
    worlds = []
    for bits in itertools.product((False, True), repeat=len(m['atoms'])):
        w = dict(zip(m['atoms'], (np.bool_(x) for x in bits)))
        lw = 0.0
        for r in m['roots']:
            lw = lw + np.log(th['f_' + r] if w[r] else 1.0 - th['f_' + r])
        for ch, (par, _b1, _b0) in m['rules'].items():
            t = th[ch + ('|1' if w[par] else '|0')]
            lw = lw + np.log(t if w[ch] else 1.0 - t)
        if event:
            for i, (_n, f, _s, _c) in enumerate(m['comps']):
                lw = lw + lam[i][0 if f(w) else 1]
        worlds.append((w, lw))
    top = max(np.max(lw) for _w, lw in worlds) if event else 0.0
    Z = 0.0
    N = {g: 0.0 for g in m['goals']}
    F = [0.0 for _ in m['comps']]
    for w, lw in worlds:
        W = np.exp(lw - top)
        Z = Z + W
        for g, gf in m['goals'].items():
            if gf(w):
                N[g] = N[g] + W
        if not event:
            for i, (_n, f, _s, _c) in enumerate(m['comps']):
                if f(w):
                    F[i] = F[i] + W
    return Z, N, F


def gauss_jacobi(a, b, n):
    """The n-point Gauss rule of Beta(a, b) on [0, 1] (Golub-Welsch on the Jacobi
    recurrence, its coefficients written in a and b so that small shapes lose nothing):
    exact for polynomials of degree 2n - 1."""
    k = np.arange(1, n)
    ab = a + b
    s2 = (2 * k - 2) + ab                               # 2k + alpha + beta, alpha = b - 1, beta = a - 1
    diag = np.empty(n)
    diag[0] = (a - b) / (a + b)
    diag[1:] = (a - b) * (ab - 2) / (s2 * (s2 + 2))
    off = np.empty(n - 1)
    off[0] = 4 * a * b / ((a + b) ** 2 * (a + b + 1))
    k2 = k[1:]
    t = (2 * k2 - 2) + ab
    off[1:] = 4 * k2 * ((k2 - 1) + b) * ((k2 - 1) + a) * ((k2 - 2) + ab) / (t ** 2 * (t + 1) * (t - 1))
    x, v = np.linalg.eigh(np.diag(diag) + np.diag(np.sqrt(off), 1) + np.diag(np.sqrt(off), -1))
    return (1 + x) / 2, v[0] ** 2


def event_oracle(m, nodes=9):
    ps = params(m)
    axes = [(np.array([point_value(s, c)]), np.ones(1)) if point_value(s, c) is not None
            else gauss_jacobi(*beta_ab(s, c), nodes) for s, c in ps.values()]
    th = dict(zip(ps, np.meshgrid(*[a for a, _ in axes], indexing='ij')))
    wgrid = np.ones([len(a) for a, _ in axes])
    for i, (_a, wi) in enumerate(axes):
        wgrid = wgrid * wi.reshape([len(wi) if j == i else 1 for j in range(len(axes))])
    Z, N, _ = enumerate_stats(m, th, True)
    EZ = np.sum(wgrid * Z)
    out = {}
    for g in m['goals']:
        mu = float(np.sum(wgrid * N[g]) / EZ)
        var = max(float(np.sum(wgrid * N[g] ** 2 / Z) / EZ) - mu * mu, 0.0)
        out[g] = {'s': mu, 'var': var, 'c': conf_from_var(mu, var)}
    return out


def count_oracle(m, inflate=1.3):
    ps = params(m)
    names = list(ps)
    d = len(names)
    evidence = [(lambda t, n=n: t[n], s, c) for n, (s, c) in ps.items()]
    evidence += [(lambda t, i=i: enumerate_stats(m, t, False)[2][i], s, c)
                 for i, (_n, _f, s, c) in enumerate(m['comps'])]

    def logpost(U):                         # uniform prior on each probability, in logit space
        th = dict(zip(names, (1.0 / (1.0 + np.exp(-U))).T))
        lp = np.sum(-np.logaddexp(0, -U) - np.logaddexp(0, U), axis=-1)
        for f, s, c in evidence:
            fv = np.clip(f(th), 1e-300, 1.0 - 1e-16)
            lp = lp + count(c) * (s * np.log(fv) + (1 - s) * np.log1p(-fv))
        return lp

    u, h, E = np.zeros(d), 1e-4, np.eye(d) * 1e-4
    for _ in range(100):
        pts = np.array([u] + [u + e for e in E] + [u - e for e in E]
                       + [u + si * E[i] + sj * E[j] for si in (1, -1) for sj in (1, -1)
                          for i in range(d) for j in range(d)])
        v = logpost(pts)
        g = (v[1:1 + d] - v[1 + d:1 + 2 * d]) / (2 * h)
        q = [v[1 + 2 * d + k * d * d:1 + 2 * d + (k + 1) * d * d].reshape(d, d) for k in range(4)]
        H = (q[0] - q[1] - q[2] + q[3]) / (4 * h * h)
        if np.any(np.linalg.eigvalsh(H) >= 0):
            H = -np.diag(np.abs(np.diag(H)) + 1.0)
        step, lam = -np.linalg.solve(H, g), 1.0
        while lam > 1e-6 and logpost((u + lam * step)[None])[0] < v[0]:
            lam /= 2
        u = u + lam * step
        if np.abs(lam * step).max() < 1e-9:
            break
    L = np.linalg.cholesky(np.linalg.inv(-H) * inflate ** 2)
    x, w = hermegauss(32 if d <= 3 else 16)
    Zn = np.array(list(itertools.product(x, repeat=d)))
    W = np.prod(np.array(list(itertools.product(w, repeat=d))), axis=1)
    U = u + Zn @ L.T
    lr = logpost(U) + 0.5 * np.sum(Zn * Zn, axis=1)
    Wt = W * np.exp(lr - lr.max())
    Wt /= Wt.sum()
    N = enumerate_stats(m, dict(zip(names, (1.0 / (1.0 + np.exp(-U))).T)), False)[1]
    out = {}
    for g in m['goals']:
        mu = float(np.sum(Wt * N[g]))
        var = float(np.sum(Wt * (N[g] - mu) ** 2))
        out[g] = {'s': mu, 'var': var, 'c': conf_from_var(mu, var)}
    return out


# ---- wide probes: two conjunctions of many facts --------------------------------

WIDE_STRENGTHS = (0.95, 0.9, 0.85, 0.92, 0.88, 0.97, 0.8, 0.93, 0.86, 0.91,
                  0.94, 0.89, 0.83, 0.96, 0.87, 0.9, 0.82, 0.95, 0.84, 0.92)


def conjunction(atoms):
    """(And (F1 a) (And (F2 a) ...)), right-nested."""
    first, *rest = atoms
    return f'({first} a)' if not rest else f'(And ({first} a) {conjunction(rest)})'


def wide_probes(cf):
    """P13 and P14: X and Y each the conjunction of ten facts at confidence cf, combined by
    And; P13's X and Y share no fact (the independent answer), P14's share five."""
    facts = [f'F{i + 1}' for i in range(20)]
    out = {}
    for probe, x, y in (('P13', facts[:10], facts[10:]), ('P14', facts[:10], facts[5:15])):
        used = sorted(set(x) | set(y), key=facts.index)
        out[probe] = dict(roots={f: (WIDE_STRENGTHS[facts.index(f)], cf) for f in used},
                          x=conjunction(x), y=conjunction(y),
                          goals={f'(And {conjunction(x)} {conjunction(y)})': used})
    return out


def wide_oracle(m):
    """The event oracle of a conjunction of independent facts, in closed form: its
    probability given theta is the product over the distinct facts it reads (an atom read
    twice is one event), so s = prod E[theta] and Var = prod E[theta^2] - s^2 under each
    fact's Beta(n s + 1, n (1 - s) + 1)."""
    out = {}
    for goal, used in m['goals'].items():
        mean, second = 1.0, 1.0
        for f in used:
            s, c = m['roots'][f]
            p = point_value(s, c)
            if p is not None:
                mean, second = mean * p, second * p * p
            else:
                a, b = beta_ab(s, c)
                mean, second = mean * a / (a + b), second * a * (a + 1) / ((a + b) * (a + b + 1))
        var = max(second - mean * mean, 0.0)
        out[goal] = {'s': mean, 'var': var, 'c': conf_from_var(mean, var)}
    return out
