import re, sys, pathlib, collections
files = sys.argv[1:]
defs = collections.OrderedDict(); fileof = {}
tok = re.compile(r'[^\s()]+')
for f in files:
    src = pathlib.Path(f).read_text()
    # split top-level forms
    depth=0; start=None; forms=[]
    i=0
    while i < len(src):
        c=src[i]
        if c==';':
            j=src.find('\n',i); i = len(src) if j<0 else j; continue
        if c=='"':
            j=i+1
            while j<len(src) and src[j]!='"': j+= 2 if src[j]=='\\' else 1
            i=j+1; continue
        if c=='(':
            if depth==0: start=i
            depth+=1
        elif c==')':
            depth-=1
            if depth==0: forms.append(src[start:i+1])
        i+=1
    for fm in forms:
        m = re.match(r'\(=\s*\(\s*([^\s()]+)', fm)
        if m:
            n=m.group(1); defs.setdefault(n, []).append(fm); fileof.setdefault(n, f)
names=set(defs)
g={n:set() for n in names}
for n,fs in defs.items():
    for fm in fs:
        body = fm[fm.find(')',0)+1:] if False else fm
        for t in tok.findall(fm):
            if t in names and t!=n: g[n].add(t)
# tarjan
sys.setrecursionlimit(100000)
idx={}; low={}; st=[]; on=set(); comps=[]; c=[0]
def sc(v):
    idx[v]=low[v]=c[0]; c[0]+=1; st.append(v); on.add(v)
    for w in g[v]:
        if w not in idx: sc(w); low[v]=min(low[v],low[w])
        elif w in on: low[v]=min(low[v],idx[w])
    if low[v]==idx[v]:
        comp=[]
        while True:
            w=st.pop(); on.discard(w); comp.append(w)
            if w==v: break
        comps.append(comp)
for v in names:
    if v not in idx: sc(v)
comps.sort(key=len, reverse=True)
tot=len(names)
print("functions", tot)
print("largest SCCs:", [len(x) for x in comps[:6]])
big=comps[0]
size=lambda ns: sum(len(f) for n in ns for f in defs[n])
allsize=size(names)
print(f"largest SCC: {len(big)} fns = {100*len(big)/tot:.0f}% of functions, {100*size(big)/allsize:.0f}% of source chars")
byfile=collections.Counter(fileof[n].split('/')[-1] for n in big)
print("largest SCC by file:", byfile.most_common(8))
print(" ".join(sorted(big)))
# edges inside big: count in-degree within SCC to spot hubs
indeg=collections.Counter(w for v in big for w in g[v] if w in set(big))
print("hubs:", indeg.most_common(12))
