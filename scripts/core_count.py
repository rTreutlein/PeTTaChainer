import sys, pathlib, tiktoken
enc = tiktoken.get_encoding("o200k_base")
root = pathlib.Path(sys.argv[1])
groups = {}
for p in sorted(root.glob("pettachainer/metta/**/*")):
    if p.suffix in (".metta", ".pl") and "benchmark" not in str(p) and "simulation" not in str(p):
        n = len(enc.encode(p.read_text(errors="replace")))
        groups[p.relative_to(root)] = n
for p in sorted(root.glob("pettachainer/*.py")):
    groups[p.relative_to(root)] = len(enc.encode(p.read_text(errors="replace")))
tp = 0
for p in list(root.glob("third_party/pln_formulas/**/*")) + list(root.glob("third_party/metta_lowering/**/*")):
    if p.suffix in (".metta", ".pl"):
        tp += len(enc.encode(p.read_text(errors="replace")))
lib = sum(n for k, n in groups.items() if k.parts[:3] == ("pettachainer", "metta", "lib"))
core = sum(groups.values()) - lib
print(f"core {core}  lib {lib}  third_party {tp}  total {core+lib+tp}")
for k, v in sorted(groups.items(), key=lambda kv: -kv[1])[:8]: print(f"  {v:7d} {k}")
