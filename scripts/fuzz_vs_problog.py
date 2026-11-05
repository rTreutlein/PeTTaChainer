#!/usr/bin/env python3
"""Differential fuzzing of PeTTaChainer against ProbLog (docs/metta/fuzzing.md).

    .venv/bin/python scripts/fuzz_vs_problog.py --seed 1 --n 100 --out DIR

Generates ``--n`` seeded KBs, answers every query with ProbLog (exact) and
PeTTaChainer, flags clear disagreements, shrinks one flagged case per
cluster to a minimal repro, and writes ``cases.jsonl``, ``repros/`` and
``summary.md`` / ``summary.json`` to ``--out``.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import re
import sys
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tests.fuzz.generator import DEFAULT, FEATURES, generate  # noqa: E402
from tests.fuzz.kb import KB, metta_antecedent, metta_file, problog  # noqa: E402
from tests.fuzz.run import EXPECTED, REPO, SEVERITY, Settings, chainer, evaluate, reexec_capped  # noqa: E402
from tests.fuzz.shrink import shrink  # noqa: E402


def features_of(rng: random.Random, chosen: list[str], mix: bool) -> list[str]:
    """With ``mix`` each KB takes a random subset of the chosen features."""
    if not mix:
        return chosen
    return [f for f in chosen if rng.random() < 0.6]


PROOF_WORD = re.compile(r"\(\(?([a-z][a-z/-]*[a-z])")


def proof_shape(proof: str | None) -> list[str]:
    """The proof constructors of an expanded proof, without rule and fact names."""
    if not proof:
        return []
    words = {w for w in PROOF_WORD.findall(proof) if not w.startswith(("obs-", "hist-"))}
    return sorted(words - {"by", "conjunction", "shared"})


def kb_shape(kb: KB) -> list[str]:
    """The features a minimal KB still uses."""
    shape = set()
    for rule in kb.rules:
        shape.add(rule.ant.op)
        if any(part.negated for part in rule.ant.parts):
            shape.add("not")
        if rule.learned:
            shape.add("learned")
        if any(rule.ant.preds) and any(kb.rule_of(p) for p in rule.ant.preds):
            shape.add("chain")
    if any(not f.hard for f in kb.facts):
        shape.add("soft")
    if any(f.hard and f.pred not in kb.roots for f in kb.facts):
        shape.add("evidence")
    if any(f.hard and f.pred in kb.roots for f in kb.facts):
        shape.add("observe")
    if kb.complete:
        shape.add("cycle")
    if any(rate is None for rate in kb.roots.values()):
        shape.add("history_rates")
    if len(kb.individuals) > 1:
        shape.add("two_individuals")
    reads = defaultdict(int)
    for rule in kb.rules:
        for pred in rule.ant.preds:
            reads[pred] += 1
    if any(n > 1 for n in reads.values()):
        shape.add("shared")
    return sorted(shape)


def describe(kb: KB) -> str:
    lines = []
    for pred, rate in kb.roots.items():
        lines.append(f"root {pred}: prior {rate if rate is not None else f'from history ({kb.prior(pred):.4f})'}")
    for rule in kb.rules:
        p, q = kb.rates(rule)
        lines.append(f"{rule.name}: {metta_antecedent(rule.ant)} -> ({rule.head} $x)  CTV({p:.4g}, {q:.4g}){' learned' if rule.learned else ''}")
    lines += [f"obs ({f.pred} {f.ind}) = {f.strength:g}" for f in kb.facts]
    if kb.history:
        lines.append(f"history: {len(kb.history_individuals())} individuals")
    if kb.complete:
        lines.append(f"complete: {' '.join(kb.complete)}")
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--chainer", type=Path, help="target repository with its own repointed .venv")
    parser.add_argument("--quick", action="store_true", help="event + metamorphic builder gate (under ten minutes)")
    parser.add_argument("--long", action="store_true", help="nightly event + metamorphic campaign")
    parser.add_argument("--gate", action="store_true", help="the quick campaign as the verify gate: fail on a BLOCKER outside tests/fuzz/run.py KNOWN or on a known one that no longer occurs")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--n", type=int, default=50)
    parser.add_argument("--features", default=",".join(DEFAULT), help=f"comma-separated, 'all' or 'default'; known: {', '.join(FEATURES)}")
    parser.add_argument("--no-mix", action="store_true", help="give every KB all chosen features (default: a random subset each)")
    parser.add_argument("--budgets", default="100,2000", help="ascending; the last is judged, the first checks that more budget is no worse")
    parser.add_argument("--k", type=float, default=None)
    parser.add_argument("--threshold", type=float, default=None)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--shrink", type=int, default=2, help="flagged KBs to shrink per cluster (0: none)")
    parser.add_argument("--shrink-limit", type=int, default=120, help="chainer runs per shrink")
    parser.add_argument("--out", type=Path, help="results directory (required unless --replay)")
    parser.add_argument("--replay", type=Path, help="a repro .json (or a KB as JSON): print both sides' answers and the chainer's proofs")
    args = parser.parse_args()
    reexec_capped()
    if args.chainer:
        from tests.fuzz import run
        target = args.chainer.resolve()
        run.CHAINER_PYTHON = str(target / '.venv/bin/python')
        os.environ['FUZZ_CHAINER_REPO'] = str(target)
    if args.quick or args.long or args.gate:
        from tests.fuzz.run import event_campaign
        if args.out is None:
            parser.error('--out is required')
        raise SystemExit(event_campaign(args))
    if args.replay:
        replay(args.replay, Settings(budgets=tuple(int(b) for b in args.budgets.split(",")), k=args.k if args.k is not None else 5.0, threshold=args.threshold if args.threshold is not None else 0.05))
        return
    if args.out is None:
        parser.error("--out is required")

    chosen = list(FEATURES) if args.features == "all" else DEFAULT if args.features == "default" else [f for f in args.features.split(",") if f]
    unknown = set(chosen) - set(FEATURES)
    if unknown:
        parser.error(f"unknown features {sorted(unknown)}")
    settings = Settings(budgets=tuple(int(b) for b in args.budgets.split(",")), k=args.k if args.k is not None else 5.0, threshold=args.threshold if args.threshold is not None else 0.05)
    out = args.out
    (out / "repros").mkdir(parents=True, exist_ok=True)

    def log(message: str) -> None:
        print(message, flush=True)
        with open(out / "log.txt", "a") as handle:
            handle.write(message + "\n")

    started = time.time()
    kbs = []
    for i in range(args.n):
        kb_seed = args.seed * 1_000_003 + i
        kbs.append((kb_seed, generate(kb_seed, features_of(random.Random(kb_seed), chosen, not args.no_mix))))
    log(f"{len(kbs)} KBs, features {chosen}, mix {not args.no_mix}, budgets {settings.budgets}, k {settings.k}")

    cases = []
    batch = 10
    for start in range(0, len(kbs), batch):
        chunk = kbs[start : start + batch]
        for (kb_seed, kb), (exact, answers, verdict) in zip(chunk, evaluate([kb for _, kb in chunk], settings, args.jobs)):
            case = {"seed": kb_seed, "kb": kb.to_json(), "exact": exact}
            if verdict is None:
                case["skipped"] = exact.get("error")
            else:
                case |= {"rows": verdict.rows, "flags": verdict.flags, "category": verdict.category, "error": verdict.error,
                         "unsupported": verdict.unsupported}
            cases.append(case)
        log(f"  {len(cases)}/{len(kbs)} done, {sum(1 for c in cases if c.get('category') in SEVERITY)} flagged, "
            f"{sum(1 for c in cases if c.get('category') == 'unsupported')} unsupported, {time.time() - started:.0f} s")
    with open(out / "cases.jsonl", "w") as handle:
        for case in cases:
            handle.write(json.dumps(case) + "\n")

    evaluated = [c for c in cases if "rows" in c]
    judged = [c for c in evaluated if c["rows"]]
    unsupported = defaultdict(int)
    for c in evaluated:
        if c["unsupported"] is not None:
            unsupported[c["unsupported"]] += 1
    queries = sum(len(c["rows"]) for c in judged)
    counts = defaultdict(int)
    for c in evaluated:
        for category, _ in c["flags"]:
            counts[category] += 1
    errors = [r["err"] for c in judged for r in c["rows"] if r["err"] is not None]

    # Group every flagged KB by its worst category, the direction of the
    # error and the constructors of the judged proof; shrink up to --shrink
    # KBs per group. A group's KBs are then counted under the root-cause
    # cluster of its first minimal repro: category, direction, the features
    # the repro still uses and its proof's constructors.
    groups: dict[str, list[dict]] = defaultdict(list)
    for case in judged:
        if case["category"] is not None:
            row = case["rows"][worst(case)]
            groups[f"{case['category']}|{direction(row)}|{'+'.join(proof_shape(row['proof']))}"].append(case)
    tasks = [case for members in groups.values() for case in members[: args.shrink]]
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:  # each shrink is sequential; --jobs run at once
        repros = dict(zip((case["seed"] for case in tasks), pool.map(lambda case: minimise(case, settings, args, out, log), tasks)))
    clusters: dict[str, dict] = {}
    for group_key, members in groups.items():
        home = None
        for case in members[: args.shrink]:
            repro = repros[case["seed"]]
            if repro is None:
                continue
            key = f"{case['category']}|{direction(repro['row'])}|{'+'.join(repro['shape'])}|{'+'.join(proof_shape(repro['proof']))}"
            cluster = clusters.setdefault(key, {"category": case["category"], "direction": direction(repro["row"]), "shape": repro["shape"], "proof": proof_shape(repro["proof"]), "cases": [], "repros": []})
            cluster["repros"].append(repro)
            home = home or cluster
        home = home or clusters.setdefault(f"{group_key}|unshrunk", {"category": members[0]["category"], "direction": group_key.split("|")[1], "shape": [], "proof": group_key.split("|")[2].split("+"), "cases": [], "repros": []})
        home["cases"] += [case["seed"] for case in members]
    summary = {
        "seed": args.seed, "n": args.n, "features": chosen, "mix": not args.no_mix, "budgets": settings.budgets, "k": settings.k,
        "threshold": settings.threshold, "kbs_judged": len(judged), "kbs_skipped": len(cases) - len(evaluated), "queries": queries,
        "kbs_unsupported": sum(unsupported.values()), "unsupported_reasons": dict(unsupported),
        "flag_counts": dict(counts), "flagged_kbs": {c: sum(1 for x in evaluated if x["category"] == c) for c in SEVERITY},
        "mean_abs_error": sum(errors) / len(errors) if errors else None, "answered": len(errors), "seconds": round(time.time() - started),
        "clusters": sorted(clusters.values(), key=lambda c: -len(c["cases"])),
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=1))
    (out / "summary.md").write_text(report(summary))
    log(report(summary))


def replay(path: Path, settings: Settings) -> None:
    data = json.loads(path.read_text())
    raw = data.get("kb", data)
    if raw.get('event'):
        from tests.fuzz.kb import EventKB
        from tests.fuzz.run import event_evaluate
        if 'settings' in data:
            settings = Settings(**data['settings'])
        print(json.dumps(event_evaluate(EventKB.from_json(raw), settings,
                         lambda kb: chainer(kb, settings)), indent=2))
        return
    kb = KB.from_json(raw)
    print(describe(kb))
    print(problog(kb))
    ((exact, answers, verdict),) = evaluate([kb], settings, 1)
    if verdict is None:
        print("ProbLog:", exact["error"])
        return
    if verdict.unsupported is not None:
        print("unsupported:", verdict.unsupported)
        return
    for i, row in enumerate(verdict.rows):
        print(f"{row['atom']}: exact {row['exact']:.6f} (prior {row['prior']:.6f}), PeTTaChainer {row['pln']} (budget {settings.budgets[0]}: {row['pln_low']})")
        for strength, confidence, proof in answers[settings.budgets[-1]][i]:
            print(f"    STV {strength:.6f} {confidence:.4f}  {proof}")
    print("flags:", verdict.flags, verdict.error or "")


def worst(case: dict) -> int:
    """The flagged query of the case's worst category with the largest error."""
    return max((i for c, i in case["flags"] if c == case["category"]), key=lambda i: case["rows"][i]["err"] if case["rows"][i]["err"] is not None else 2.0)


def direction(row: dict) -> str:
    return "none" if row["pln"] is None else "over" if row["pln"] > row["exact"] else "under"


def minimise(case: dict, settings: Settings, args, out: Path, log) -> dict | None:
    """Shrink a flagged case and write its repro files; None when the failure
    does not reproduce."""
    category = case["category"]
    kb = KB.from_json(case["kb"])
    atom = kb.queries[worst(case)]
    log(f"shrinking seed {case['seed']} ({category} on ({atom[0]} {atom[1]}))")
    budgets = settings.budgets if category == "budget_regression" else settings.budgets[-1:]
    small, verdict, runs = shrink(kb, category, atom, Settings(budgets, settings.k, settings.threshold), log, args.shrink_limit)
    if verdict is None:
        log("  did not reproduce")
        return None
    detail = chainer(small, Settings(settings.budgets[-1:], settings.k, settings.threshold))
    row = verdict.rows[small.queries.index(atom)]
    answers = [] if "error" in detail or "unsupported" in detail else detail[settings.budgets[-1]][small.queries.index(atom)]
    best = max(answers, key=lambda a: a[1]) if answers else None
    name = f"seed{case['seed']}_{category}"
    header = f";; fuzz_vs_problog seed {case['seed']}: {category} on ({atom[0]} {atom[1]})\n;; exact {row['exact']:.6f}, PeTTaChainer {row['pln']}\n"
    (out / "repros" / f"{name}.metta").write_text(header + "".join(f";; {line}\n" for line in describe(small).splitlines()) + metta_file(small, settings.budgets[-1], settings.k, str(REPO)))
    (out / "repros" / f"{name}.pl").write_text(problog(small))
    (out / "repros" / f"{name}.json").write_text(json.dumps({"seed": case["seed"], "category": category, "atom": atom, "row": row, "answers": answers, "kb": small.to_json(), "runs": runs}, indent=1))
    log(f"  minimal: {len(small.rules)} rules, {len(small.facts)} facts, exact {row['exact']:.4f}, PeTTaChainer {row['pln']} ({runs} runs)")
    return {"name": name, "size": len(small.rules) + len(small.facts), "row": row, "proof": best[2] if best else None, "kb": describe(small), "shape": kb_shape(small)}


def report(s: dict) -> str:
    lines = [
        f"# fuzz_vs_problog seed {s['seed']}, {s['n']} KBs",
        "",
        f"Features {', '.join(s['features'])} (mix: {s['mix']}); budgets {s['budgets']}; k {s['k']}; threshold {s['threshold']}; {s['seconds']} s.",
        "",
        f"KBs judged {s['kbs_judged']} (skipped {s['kbs_skipped']}: impossible evidence), queries {s['queries']}, answered {s['answered']}, mean |PLN - exact| {s['mean_abs_error'] if s['mean_abs_error'] is None else round(s['mean_abs_error'], 4)}.",
        f"Unsupported KBs {s['kbs_unsupported']} (separate from crashes and query errors).",
        "",
        "| category | flagged queries | KBs (worst category) |",
        "|---|---|---|",
    ]
    for category in SEVERITY + EXPECTED:
        lines.append(f"| {category} | {s['flag_counts'].get(category, 0)} | {s['flagged_kbs'].get(category, '-')} |")
    lines += ["", "Unsupported feature/stage labels:"]
    lines += [f"- {label}: {count} KBs" for label, count in sorted(s["unsupported_reasons"].items())] or ["- none"]
    lines += ["", "## Clusters (by frequency)", ""]
    for i, cluster in enumerate(s["clusters"], 1):
        lines.append(f"### {i}. {cluster['category']} ({len(cluster['cases'])} cases), PLN {cluster.get('direction', '?')}")
        lines.append(f"repro features: {', '.join(cluster['shape']) or '-'}; proof constructors: {', '.join(cluster['proof']) or '-'}; seeds {cluster['cases']}")
        for repro in sorted(cluster["repros"], key=lambda r: r["size"])[:1]:
            row = repro["row"]
            lines += ["", f"smallest repro `repros/{repro['name']}.metta` ({', '.join(repro['shape'])}): {row['atom']} exact {row['exact']:.4f}, PLN {row['pln']}", "```", repro["kb"], f"proof: {repro['proof']}", "```", ""]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
